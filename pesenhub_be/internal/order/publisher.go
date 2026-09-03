package order

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"sync"
	"time"

	"pesenhub/backend/internal/ws"

	"github.com/jackc/pgx/v5/pgxpool"
)

type EventBroadcaster interface {
	Broadcast(staffPayload, kdsPayload []byte)
}

type OrderEventEnvelope struct {
	EventID   string          `json:"event_id"`
	EventType string          `json:"event_type"`
	OrderID   string          `json:"order_id"`
	Version   int64           `json:"version"`
	Source    string          `json:"source,omitempty"`
	Status    string          `json:"status"`
	Timestamp time.Time       `json:"timestamp"`
	Payload   json.RawMessage `json:"payload"`
}

type OutboxPublisher struct {
	db       *pgxpool.Pool
	hub      EventBroadcaster
	logger   *slog.Logger
	notifyCh chan struct{}
	mu       sync.Mutex
	running  bool
}

func NewOutboxPublisher(db *pgxpool.Pool, hub EventBroadcaster, logger *slog.Logger) *OutboxPublisher {
	if logger == nil {
		logger = slog.Default()
	}
	return &OutboxPublisher{
		db:       db,
		hub:      hub,
		logger:   logger,
		notifyCh: make(chan struct{}, 100),
	}
}

func (p *OutboxPublisher) Notify() {
	select {
	case p.notifyCh <- struct{}{}:
	default:
	}
}

func (p *OutboxPublisher) Start(ctx context.Context, pollInterval time.Duration) {
	p.mu.Lock()
	if p.running {
		p.mu.Unlock()
		return
	}
	p.running = true
	p.mu.Unlock()

	if pollInterval <= 0 {
		pollInterval = 500 * time.Millisecond
	}

	ticker := time.NewTicker(pollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-p.notifyCh:
			p.drainPending(ctx)
		case <-ticker.C:
			p.drainPending(ctx)
		}
	}
}

func (p *OutboxPublisher) drainPending(ctx context.Context) {
	for {
		count, err := p.ProcessBatch(ctx)
		if err != nil {
			p.logger.Error("failed to process outbox batch", "error", err)
			return
		}
		if count == 0 {
			return
		}
	}
}

func (p *OutboxPublisher) ProcessBatch(ctx context.Context) (int, error) {
	if p.db == nil {
		return 0, nil
	}

	tx, err := p.db.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	rows, err := tx.Query(ctx, `SELECT id::text, aggregate_id::text, event_type, payload, created_at
		FROM outbox_events
		WHERE status IN ('PENDING', 'FAILED') AND available_at <= now()
		ORDER BY created_at ASC, id ASC
		LIMIT 50
		FOR UPDATE SKIP LOCKED`)
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	type rawEvent struct {
		id        string
		orderID   string
		eventType string
		payload   []byte
		createdAt time.Time
	}

	var events []rawEvent
	for rows.Next() {
		var e rawEvent
		if err = rows.Scan(&e.id, &e.orderID, &e.eventType, &e.payload, &e.createdAt); err != nil {
			return 0, err
		}
		events = append(events, e)
	}
	if err = rows.Err(); err != nil {
		return 0, err
	}

	if len(events) == 0 {
		return 0, nil
	}

	publishedIDs := make([]string, 0, len(events))

	for _, e := range events {
		var rawMap map[string]any
		if err = json.Unmarshal(e.payload, &rawMap); err != nil {
			rawMap = make(map[string]any)
		}

		version := int64(1)
		if v, ok := rawMap["version"].(float64); ok {
			version = int64(v)
		}

		status := ""
		if s, ok := rawMap["status"].(string); ok {
			status = s
		} else if s, ok := rawMap["to_status"].(string); ok {
			status = s
		}

		source := ""
		if s, ok := rawMap["source"].(string); ok {
			source = s
		}

		staffEnv := OrderEventEnvelope{
			EventID:   e.id,
			EventType: e.eventType,
			OrderID:   e.orderID,
			Version:   version,
			Source:    source,
			Status:    status,
			Timestamp: e.createdAt,
			Payload:   e.payload,
		}

		// KDS Payload: redact sensitive customer PII if present
		kdsMap := make(map[string]any, len(rawMap))
		for k, v := range rawMap {
			if k == "customer_phone" || k == "customer_id" {
				continue
			}
			kdsMap[k] = v
		}
		kdsPayloadBytes, _ := json.Marshal(kdsMap)

		kdsEnv := OrderEventEnvelope{
			EventID:   e.id,
			EventType: e.eventType,
			OrderID:   e.orderID,
			Version:   version,
			Source:    source,
			Status:    status,
			Timestamp: e.createdAt,
			Payload:   kdsPayloadBytes,
		}

		staffBytes, err1 := json.Marshal(staffEnv)
		kdsBytes, err2 := json.Marshal(kdsEnv)
		if err1 == nil && err2 == nil && p.hub != nil {
			p.hub.Broadcast(staffBytes, kdsBytes)
		}

		publishedIDs = append(publishedIDs, e.id)
	}

	_, err = tx.Exec(ctx, `UPDATE outbox_events
		SET status = 'PUBLISHED', published_at = now(), updated_at = now()
		WHERE id = ANY($1)`, publishedIDs)
	if err != nil {
		return 0, err
	}

	if err = tx.Commit(ctx); err != nil {
		return 0, err
	}

	return len(publishedIDs), nil
}

// HubBroadcasterAdapter adapts *ws.Hub to EventBroadcaster
type HubBroadcasterAdapter struct {
	hub *ws.Hub
}

func NewHubBroadcasterAdapter(hub *ws.Hub) *HubBroadcasterAdapter {
	return &HubBroadcasterAdapter{hub: hub}
}

func (a *HubBroadcasterAdapter) Broadcast(staffPayload, kdsPayload []byte) {
	if a.hub != nil {
		a.hub.Broadcast(staffPayload, kdsPayload)
	}
}

var ErrPublisherNil = errors.New("publisher is nil")
