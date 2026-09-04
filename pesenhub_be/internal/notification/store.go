package notification

import (
	"context"
	"errors"
	"sort"
	"sync"
	"time"

	"pesenhub/backend/internal/customer"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store provides persistence for notification records, opt-outs, and pause status checks.
type Store interface {
	CreatePending(ctx context.Context, record *NotificationRecord) (*NotificationRecord, bool, error)
	GetByIdempotencyKey(ctx context.Context, key string) (*NotificationRecord, error)
	MarkSent(ctx context.Context, id, providerMessageID string) error
	MarkFailed(ctx context.Context, id, lastError string) error
	MarkSuppressed(ctx context.Context, id string, reason SuppressReason) error
	IsOptedOut(ctx context.Context, phoneE164 string) (bool, error)
	SetOptOut(ctx context.Context, phoneE164, reason string) error
	RemoveOptOut(ctx context.Context, phoneE164 string) error
	IsConversationPaused(ctx context.Context, phoneE164 string) (bool, SuppressReason, error)

	ScheduleRetry(ctx context.Context, id string, nextRetryAt time.Time, category ErrorCategory, safeError string) error
	MarkDeadLetter(ctx context.Context, id string, category ErrorCategory, safeError string) error
	ClaimBatchForProcessing(ctx context.Context, limit int) ([]*NotificationRecord, error)
	RecoverStaleProcessing(ctx context.Context, staleThreshold time.Duration) (int64, error)
}

// PGStore is the PostgreSQL implementation of Store.
type PGStore struct {
	db *pgxpool.Pool
}

// NewPGStore creates a new PGStore.
func NewPGStore(db *pgxpool.Pool) *PGStore {
	return &PGStore{db: db}
}

func (s *PGStore) CreatePending(ctx context.Context, r *NotificationRecord) (*NotificationRecord, bool, error) {
	if s == nil || s.db == nil {
		return nil, false, errors.New("pgstore db is nil")
	}

	if r.ID == "" {
		r.ID = customer.NewID()
	}
	if r.TemplateVersion == "" {
		r.TemplateVersion = DefaultTemplateVersion
	}

	if r.MaxAttempts <= 0 {
		r.MaxAttempts = 5
	}

	query := `
		INSERT INTO order_notifications (
			id, order_id, customer_phone, notification_type, template_version,
			idempotency_key, message_text, status, attempts, max_attempts, next_retry_at, created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, 'PENDING', 0, $8, $9, now(), now())
		ON CONFLICT (idempotency_key) DO NOTHING
		RETURNING id, order_id, customer_phone, notification_type, template_version,
		          idempotency_key, message_text, status, suppress_reason,
		          provider_message_id, attempts, max_attempts, next_retry_at,
		          error_category, last_error, sent_at, created_at, updated_at
	`

	var rec NotificationRecord
	err := s.db.QueryRow(ctx, query,
		r.ID, r.OrderID, r.CustomerPhone, string(r.NotificationType), r.TemplateVersion,
		r.IdempotencyKey, r.MessageText, r.MaxAttempts, r.NextRetryAt,
	).Scan(
		&rec.ID, &rec.OrderID, &rec.CustomerPhone, &rec.NotificationType, &rec.TemplateVersion,
		&rec.IdempotencyKey, &rec.MessageText, &rec.Status, &rec.SuppressReason,
		&rec.ProviderMessageID, &rec.Attempts, &rec.MaxAttempts, &rec.NextRetryAt,
		&rec.ErrorCategory, &rec.LastError, &rec.SentAt, &rec.CreatedAt, &rec.UpdatedAt,
	)

	if err == nil {
		return &rec, true, nil
	}

	if errors.Is(err, pgx.ErrNoRows) {
		// Conflict occurred; fetch existing
		existing, getErr := s.GetByIdempotencyKey(ctx, r.IdempotencyKey)
		if getErr != nil {
			return nil, false, getErr
		}
		return existing, false, nil
	}

	return nil, false, err
}

func (s *PGStore) GetByIdempotencyKey(ctx context.Context, key string) (*NotificationRecord, error) {
	if s == nil || s.db == nil {
		return nil, errors.New("pgstore db is nil")
	}

	query := `
		SELECT id, order_id, customer_phone, notification_type, template_version,
		       idempotency_key, message_text, status, suppress_reason,
		       provider_message_id, attempts, max_attempts, next_retry_at,
		       error_category, last_error, sent_at, created_at, updated_at
		FROM order_notifications
		WHERE idempotency_key = $1
	`

	var rec NotificationRecord
	err := s.db.QueryRow(ctx, query, key).Scan(
		&rec.ID, &rec.OrderID, &rec.CustomerPhone, &rec.NotificationType, &rec.TemplateVersion,
		&rec.IdempotencyKey, &rec.MessageText, &rec.Status, &rec.SuppressReason,
		&rec.ProviderMessageID, &rec.Attempts, &rec.MaxAttempts, &rec.NextRetryAt,
		&rec.ErrorCategory, &rec.LastError, &rec.SentAt, &rec.CreatedAt, &rec.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &rec, nil
}

func (s *PGStore) MarkSent(ctx context.Context, id, providerMessageID string) error {
	if s == nil || s.db == nil {
		return errors.New("pgstore db is nil")
	}
	_, err := s.db.Exec(ctx, `
		UPDATE order_notifications
		SET status = 'SENT', provider_message_id = $2, sent_at = now(), updated_at = now()
		WHERE id = $1
	`, id, providerMessageID)
	return err
}

func (s *PGStore) MarkFailed(ctx context.Context, id, lastError string) error {
	if s == nil || s.db == nil {
		return errors.New("pgstore db is nil")
	}
	_, err := s.db.Exec(ctx, `
		UPDATE order_notifications
		SET status = 'FAILED', last_error = $2, updated_at = now()
		WHERE id = $1
	`, id, lastError)
	return err
}

func (s *PGStore) MarkSuppressed(ctx context.Context, id string, reason SuppressReason) error {
	if s == nil || s.db == nil {
		return errors.New("pgstore db is nil")
	}
	_, err := s.db.Exec(ctx, `
		UPDATE order_notifications
		SET status = 'SUPPRESSED', suppress_reason = $2, updated_at = now()
		WHERE id = $1
	`, id, string(reason))
	return err
}

func (s *PGStore) IsOptedOut(ctx context.Context, phoneE164 string) (bool, error) {
	if s == nil || s.db == nil {
		return false, errors.New("pgstore db is nil")
	}
	var exists bool
	err := s.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM customer_opt_outs WHERE phone_e164 = $1)`, phoneE164).Scan(&exists)
	return exists, err
}

func (s *PGStore) SetOptOut(ctx context.Context, phoneE164, reason string) error {
	if s == nil || s.db == nil {
		return errors.New("pgstore db is nil")
	}
	_, err := s.db.Exec(ctx, `
		INSERT INTO customer_opt_outs (id, phone_e164, reason, created_at)
		VALUES ($1, $2, $3, now())
		ON CONFLICT (phone_e164) DO UPDATE SET reason = EXCLUDED.reason
	`, customer.NewID(), phoneE164, reason)
	return err
}

func (s *PGStore) RemoveOptOut(ctx context.Context, phoneE164 string) error {
	if s == nil || s.db == nil {
		return errors.New("pgstore db is nil")
	}
	_, err := s.db.Exec(ctx, `DELETE FROM customer_opt_outs WHERE phone_e164 = $1`, phoneE164)
	return err
}

func (s *PGStore) IsConversationPaused(ctx context.Context, phoneE164 string) (bool, SuppressReason, error) {
	if s == nil || s.db == nil {
		return false, "", errors.New("pgstore db is nil")
	}

	query := `
		SELECT is_paused, status, handoff_status
		FROM agent_conversations
		WHERE customer_phone = $1
		ORDER BY updated_at DESC
		LIMIT 1
	`
	var isPaused bool
	var status, handoffStatus string
	err := s.db.QueryRow(ctx, query, phoneE164).Scan(&isPaused, &status, &handoffStatus)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, "", nil
	}
	if err != nil {
		return false, "", err
	}

	if isPaused || status == "PAUSED" {
		return true, SuppressConversationPaused, nil
	}
	if status == "HANDOFF" || handoffStatus == "PENDING" || handoffStatus == "ASSIGNED" {
		return true, SuppressHandoffActive, nil
	}

	return false, "", nil
}

func (s *PGStore) ScheduleRetry(ctx context.Context, id string, nextRetryAt time.Time, category ErrorCategory, safeError string) error {
	if s == nil || s.db == nil {
		return errors.New("pgstore db is nil")
	}
	query := `
		UPDATE order_notifications
		SET status = 'FAILED',
		    attempts = attempts + 1,
		    next_retry_at = $2,
		    error_category = $3,
		    last_error = $4,
		    updated_at = now()
		WHERE id = $1
	`
	_, err := s.db.Exec(ctx, query, id, nextRetryAt, string(category), safeError)
	return err
}

func (s *PGStore) MarkDeadLetter(ctx context.Context, id string, category ErrorCategory, safeError string) error {
	if s == nil || s.db == nil {
		return errors.New("pgstore db is nil")
	}
	query := `
		UPDATE order_notifications
		SET status = 'DEAD_LETTER',
		    error_category = $2,
		    last_error = $3,
		    next_retry_at = NULL,
		    updated_at = now()
		WHERE id = $1
	`
	_, err := s.db.Exec(ctx, query, id, string(category), safeError)
	return err
}

func (s *PGStore) ClaimBatchForProcessing(ctx context.Context, limit int) ([]*NotificationRecord, error) {
	if s == nil || s.db == nil {
		return nil, errors.New("pgstore db is nil")
	}
	if limit <= 0 {
		limit = 10
	}

	query := `
		WITH selected AS (
			SELECT id
			FROM order_notifications
			WHERE (status = 'PENDING' OR status = 'FAILED')
			  AND (next_retry_at IS NULL OR next_retry_at <= now())
			ORDER BY created_at ASC, id ASC
			LIMIT $1
			FOR UPDATE SKIP LOCKED
		)
		UPDATE order_notifications n
		SET status = 'PROCESSING', updated_at = now()
		FROM selected
		WHERE n.id = selected.id
		RETURNING n.id, n.order_id, n.customer_phone, n.notification_type, n.template_version,
		          n.idempotency_key, n.message_text, n.status, n.suppress_reason,
		          n.provider_message_id, n.attempts, n.max_attempts, n.next_retry_at,
		          n.error_category, n.last_error, n.sent_at, n.created_at, n.updated_at
	`

	rows, err := s.db.Query(ctx, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var records []*NotificationRecord
	for rows.Next() {
		var rec NotificationRecord
		if err := rows.Scan(
			&rec.ID, &rec.OrderID, &rec.CustomerPhone, &rec.NotificationType, &rec.TemplateVersion,
			&rec.IdempotencyKey, &rec.MessageText, &rec.Status, &rec.SuppressReason,
			&rec.ProviderMessageID, &rec.Attempts, &rec.MaxAttempts, &rec.NextRetryAt,
			&rec.ErrorCategory, &rec.LastError, &rec.SentAt, &rec.CreatedAt, &rec.UpdatedAt,
		); err != nil {
			return nil, err
		}
		records = append(records, &rec)
	}
	return records, rows.Err()
}

func (s *PGStore) RecoverStaleProcessing(ctx context.Context, staleThreshold time.Duration) (int64, error) {
	if s == nil || s.db == nil {
		return 0, errors.New("pgstore db is nil")
	}
	if staleThreshold <= 0 {
		tag, err := s.db.Exec(ctx, `
			UPDATE order_notifications
			SET status = 'FAILED',
			    error_category = 'TRANSIENT_TIMEOUT',
			    last_error = 'recovered from stale processing state on startup',
			    updated_at = now()
			WHERE status = 'PROCESSING'
		`)
		if err != nil {
			return 0, err
		}
		return tag.RowsAffected(), nil
	}

	cutoff := time.Now().Add(-staleThreshold)
	tag, err := s.db.Exec(ctx, `
		UPDATE order_notifications
		SET status = 'FAILED',
		    error_category = 'TRANSIENT_TIMEOUT',
		    last_error = 'recovered from stale processing state',
		    updated_at = now()
		WHERE status = 'PROCESSING' AND updated_at < $1
	`, cutoff)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}

// MemoryStore provides in-memory implementation of Store for tests.
type MemoryStore struct {
	mu            sync.Mutex
	records       map[string]*NotificationRecord // keyed by idempotency_key
	recordsByID   map[string]*NotificationRecord
	optOuts       map[string]string // phone -> reason
	pausedPhones  map[string]bool
	handoffPhones map[string]bool
}

// NewMemoryStore creates a new in-memory Store.
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		records:       make(map[string]*NotificationRecord),
		recordsByID:   make(map[string]*NotificationRecord),
		optOuts:       make(map[string]string),
		pausedPhones:  make(map[string]bool),
		handoffPhones: make(map[string]bool),
	}
}

func (m *MemoryStore) CreatePending(_ context.Context, r *NotificationRecord) (*NotificationRecord, bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if existing, ok := m.records[r.IdempotencyKey]; ok {
		return existing, false, nil
	}

	if r.ID == "" {
		r.ID = customer.NewID()
	}
	if r.TemplateVersion == "" {
		r.TemplateVersion = DefaultTemplateVersion
	}
	if r.MaxAttempts <= 0 {
		r.MaxAttempts = 5
	}
	now := time.Now().UTC()
	r.Status = StatusPending
	r.CreatedAt = now
	r.UpdatedAt = now

	copied := *r
	m.records[r.IdempotencyKey] = &copied
	m.recordsByID[r.ID] = &copied
	return &copied, true, nil
}

func (m *MemoryStore) GetByIdempotencyKey(_ context.Context, key string) (*NotificationRecord, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	rec, ok := m.records[key]
	if !ok {
		return nil, errors.New("not found")
	}
	copied := *rec
	return &copied, nil
}

func (m *MemoryStore) MarkSent(_ context.Context, id, providerMessageID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	rec, ok := m.recordsByID[id]
	if !ok {
		return errors.New("not found")
	}
	now := time.Now().UTC()
	rec.Status = StatusSent
	rec.ProviderMessageID = &providerMessageID
	rec.SentAt = &now
	rec.UpdatedAt = now
	return nil
}

func (m *MemoryStore) MarkFailed(_ context.Context, id, lastError string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	rec, ok := m.recordsByID[id]
	if !ok {
		return errors.New("not found")
	}
	rec.Status = StatusFailed
	rec.LastError = &lastError
	rec.UpdatedAt = time.Now().UTC()
	return nil
}

func (m *MemoryStore) MarkSuppressed(_ context.Context, id string, reason SuppressReason) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	rec, ok := m.recordsByID[id]
	if !ok {
		return errors.New("not found")
	}
	rStr := string(reason)
	rec.Status = StatusSuppressed
	rec.SuppressReason = &rStr
	rec.UpdatedAt = time.Now().UTC()
	return nil
}

func (m *MemoryStore) ScheduleRetry(_ context.Context, id string, nextRetryAt time.Time, category ErrorCategory, safeError string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	rec, ok := m.recordsByID[id]
	if !ok {
		return errors.New("not found")
	}
	now := time.Now().UTC()
	rec.Status = StatusFailed
	rec.Attempts++
	rec.NextRetryAt = &nextRetryAt
	rec.ErrorCategory = &category
	rec.LastError = &safeError
	rec.UpdatedAt = now
	return nil
}

func (m *MemoryStore) MarkDeadLetter(_ context.Context, id string, category ErrorCategory, safeError string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	rec, ok := m.recordsByID[id]
	if !ok {
		return errors.New("not found")
	}
	now := time.Now().UTC()
	rec.Status = StatusDeadLetter
	rec.ErrorCategory = &category
	rec.LastError = &safeError
	rec.NextRetryAt = nil
	rec.UpdatedAt = now
	return nil
}

func (m *MemoryStore) ClaimBatchForProcessing(_ context.Context, limit int) ([]*NotificationRecord, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if limit <= 0 {
		limit = 10
	}
	now := time.Now().UTC()
	var candidates []*NotificationRecord
	for _, rec := range m.recordsByID {
		if (rec.Status == StatusPending || rec.Status == StatusFailed) &&
			(rec.NextRetryAt == nil || !rec.NextRetryAt.After(now)) {
			candidates = append(candidates, rec)
		}
	}

	sort.Slice(candidates, func(i, j int) bool {
		if candidates[i].CreatedAt.Equal(candidates[j].CreatedAt) {
			return candidates[i].ID < candidates[j].ID
		}
		return candidates[i].CreatedAt.Before(candidates[j].CreatedAt)
	})

	var claimed []*NotificationRecord
	for _, rec := range candidates {
		if len(claimed) >= limit {
			break
		}
		rec.Status = StatusProcessing
		rec.UpdatedAt = now
		copied := *rec
		claimed = append(claimed, &copied)
	}
	return claimed, nil
}

func (m *MemoryStore) RecoverStaleProcessing(_ context.Context, staleThreshold time.Duration) (int64, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	now := time.Now().UTC()
	var count int64
	for _, rec := range m.recordsByID {
		if rec.Status == StatusProcessing {
			if staleThreshold <= 0 || rec.UpdatedAt.Before(now.Add(-staleThreshold)) {
				rec.Status = StatusFailed
				cat := CategoryTransientTimeout
				rec.ErrorCategory = &cat
				msg := "recovered from stale processing state"
				rec.LastError = &msg
				rec.UpdatedAt = now
				count++
			}
		}
	}
	return count, nil
}

func (m *MemoryStore) IsOptedOut(_ context.Context, phoneE164 string) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	_, ok := m.optOuts[phoneE164]
	return ok, nil
}

func (m *MemoryStore) SetOptOut(_ context.Context, phoneE164, reason string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.optOuts[phoneE164] = reason
	return nil
}

func (m *MemoryStore) RemoveOptOut(_ context.Context, phoneE164 string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.optOuts, phoneE164)
	return nil
}

func (m *MemoryStore) IsConversationPaused(_ context.Context, phoneE164 string) (bool, SuppressReason, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.pausedPhones[phoneE164] {
		return true, SuppressConversationPaused, nil
	}
	if m.handoffPhones[phoneE164] {
		return true, SuppressHandoffActive, nil
	}
	return false, "", nil
}

func (m *MemoryStore) SetPausedPhone(phoneE164 string, paused bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if paused {
		m.pausedPhones[phoneE164] = true
	} else {
		delete(m.pausedPhones, phoneE164)
	}
}

func (m *MemoryStore) SetHandoffPhone(phoneE164 string, handoff bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if handoff {
		m.handoffPhones[phoneE164] = true
	} else {
		delete(m.handoffPhones, phoneE164)
	}
}
