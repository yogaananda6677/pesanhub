package waha

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// InboundStore defines the persistence interface for WAHA inbound messages and deduplication.
type InboundStore interface {
	StoreInbound(ctx context.Context, msg *InboundMessage) (*InboundMessage, bool, error)
	GetByProviderMessageID(ctx context.Context, providerID string) (*InboundMessage, error)
	GetByID(ctx context.Context, id string) (*InboundMessage, error)
}

// Store is a PostgreSQL implementation of InboundStore.
type Store struct {
	db *pgxpool.Pool
}

// NewStore creates a new PostgreSQL InboundStore.
func NewStore(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

// StoreInbound inserts an inbound message atomically.
// If the message with provider_message_id already exists, it returns the existing record and isDuplicate = true.
func (s *Store) StoreInbound(ctx context.Context, msg *InboundMessage) (*InboundMessage, bool, error) {
	if s == nil || s.db == nil {
		return msg, false, nil
	}

	queryInsert := `
		INSERT INTO waha_inbound_messages (
			id, provider_message_id, webhook_request_id, session, event_type,
			from_raw, phone_e164, sender_name, message_body, payload_redacted,
			status, quarantine_reason, received_at, created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
		ON CONFLICT (provider_message_id) DO NOTHING
		RETURNING id::text, provider_message_id, COALESCE(webhook_request_id, ''), session, event_type,
		          from_raw, phone_e164, COALESCE(sender_name, ''), COALESCE(message_body, ''), payload_redacted,
		          status, COALESCE(quarantine_reason, ''), received_at, processed_at, created_at, updated_at
	`

	row := s.db.QueryRow(ctx, queryInsert,
		msg.ID, msg.ProviderMessageID, msg.WebhookRequestID, msg.Session, msg.EventType,
		msg.FromRaw, msg.PhoneE164, msg.SenderName, msg.MessageBody, msg.PayloadRedacted,
		msg.Status, msg.QuarantineReason, msg.ReceivedAt, msg.CreatedAt, msg.UpdatedAt,
	)

	stored, err := scanInboundMessage(row)
	if err == nil {
		return stored, false, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, false, err
	}

	// Conflict occurred - retrieve the existing record
	existing, err := s.GetByProviderMessageID(ctx, msg.ProviderMessageID)
	if err != nil {
		return nil, false, err
	}
	return existing, true, nil
}

// GetByProviderMessageID retrieves an inbound message by provider message ID.
func (s *Store) GetByProviderMessageID(ctx context.Context, providerID string) (*InboundMessage, error) {
	if s == nil || s.db == nil {
		return nil, errors.New("database not available")
	}

	query := `
		SELECT id::text, provider_message_id, COALESCE(webhook_request_id, ''), session, event_type,
		       from_raw, phone_e164, COALESCE(sender_name, ''), COALESCE(message_body, ''), payload_redacted,
		       status, COALESCE(quarantine_reason, ''), received_at, processed_at, created_at, updated_at
		FROM waha_inbound_messages
		WHERE provider_message_id = $1
	`
	row := s.db.QueryRow(ctx, query, providerID)
	return scanInboundMessage(row)
}

// GetByID retrieves an inbound message by primary key UUID.
func (s *Store) GetByID(ctx context.Context, id string) (*InboundMessage, error) {
	if s == nil || s.db == nil {
		return nil, errors.New("database not available")
	}

	query := `
		SELECT id::text, provider_message_id, COALESCE(webhook_request_id, ''), session, event_type,
		       from_raw, phone_e164, COALESCE(sender_name, ''), COALESCE(message_body, ''), payload_redacted,
		       status, COALESCE(quarantine_reason, ''), received_at, processed_at, created_at, updated_at
		FROM waha_inbound_messages
		WHERE id = $1
	`
	row := s.db.QueryRow(ctx, query, id)
	return scanInboundMessage(row)
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanInboundMessage(r rowScanner) (*InboundMessage, error) {
	var (
		m           InboundMessage
		phone       *string
		processedAt *time.Time
	)

	err := r.Scan(
		&m.ID, &m.ProviderMessageID, &m.WebhookRequestID, &m.Session, &m.EventType,
		&m.FromRaw, &phone, &m.SenderName, &m.MessageBody, &m.PayloadRedacted,
		&m.Status, &m.QuarantineReason, &m.ReceivedAt, &processedAt, &m.CreatedAt, &m.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}

	m.PhoneE164 = phone
	m.ProcessedAt = processedAt
	return &m, nil
}
