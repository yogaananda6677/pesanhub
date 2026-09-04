package hermes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrConversationNotFound = errors.New("conversation state not found")
)

// ConversationStore defines persistence operations for customer conversation sessions.
type ConversationStore interface {
	GetOrCreate(ctx context.Context, session, customerPhone, correlationID string) (*ConversationState, error)
	Save(ctx context.Context, state *ConversationState) error
	Reset(ctx context.Context, session, customerPhone string) error
}

// PGConversationStore is the PostgreSQL implementation of ConversationStore.
type PGConversationStore struct {
	db *pgxpool.Pool
}

// NewPGConversationStore creates a new PGConversationStore.
func NewPGConversationStore(db *pgxpool.Pool) *PGConversationStore {
	return &PGConversationStore{db: db}
}

// GetOrCreate retrieves an active conversation or creates an initial one if none exists.
func (s *PGConversationStore) GetOrCreate(ctx context.Context, session, customerPhone, correlationID string) (*ConversationState, error) {
	if s == nil || s.db == nil {
		return &ConversationState{
			ID:            newID(),
			Session:       session,
			CustomerPhone: customerPhone,
			Status:        ConversationCollecting,
			CorrelationID: correlationID,
			CreatedAt:     time.Now().UTC(),
			UpdatedAt:     time.Now().UTC(),
		}, nil
	}

	querySelect := `
		SELECT id::text, session, customer_phone, status, current_draft,
		       COALESCE(pending_ambiguity, ''), clarification_attempts,
		       COALESCE(last_question, ''), last_inbound_message_id::text,
		       correlation_id, created_at, updated_at
		FROM agent_conversations
		WHERE session = $1 AND customer_phone = $2
	`

	row := s.db.QueryRow(ctx, querySelect, session, customerPhone)
	state, err := scanConversationState(row)
	if err == nil {
		return state, nil
	}
	if !errors.Is(err, ErrConversationNotFound) {
		return nil, fmt.Errorf("failed to query conversation: %w", err)
	}

	// Create new record
	newRecord := &ConversationState{
		ID:            newID(),
		Session:       session,
		CustomerPhone: customerPhone,
		Status:        ConversationCollecting,
		CorrelationID: correlationID,
		CreatedAt:     time.Now().UTC(),
		UpdatedAt:     time.Now().UTC(),
	}

	queryInsert := `
		INSERT INTO agent_conversations (
			id, session, customer_phone, status, current_draft,
			pending_ambiguity, clarification_attempts, last_question,
			last_inbound_message_id, correlation_id, created_at, updated_at
		) VALUES (
			$1, $2, $3, $4, $5,
			$6, $7, $8,
			$9, $10, $11, $12
		)
		ON CONFLICT (session, customer_phone) DO NOTHING
		RETURNING id::text, session, customer_phone, status, current_draft,
		          COALESCE(pending_ambiguity, ''), clarification_attempts,
		          COALESCE(last_question, ''), last_inbound_message_id::text,
		          correlation_id, created_at, updated_at
	`

	insertRow := s.db.QueryRow(ctx, queryInsert,
		newRecord.ID,
		newRecord.Session,
		newRecord.CustomerPhone,
		newRecord.Status,
		json.RawMessage("{}"),
		nil,
		0,
		nil,
		nil,
		newRecord.CorrelationID,
		newRecord.CreatedAt,
		newRecord.UpdatedAt,
	)

	insertedState, err := scanConversationState(insertRow)
	if err == nil {
		return insertedState, nil
	}
	if errors.Is(err, ErrConversationNotFound) {
		// Conflict happened, re-fetch
		return s.GetOrCreate(ctx, session, customerPhone, correlationID)
	}
	return nil, fmt.Errorf("failed to insert initial conversation: %w", err)
}

// Save updates the conversation state in PostgreSQL.
func (s *PGConversationStore) Save(ctx context.Context, state *ConversationState) error {
	if s == nil || s.db == nil || state == nil {
		return nil
	}

	var draftBytes []byte
	var err error
	if state.CurrentDraft != nil {
		draftBytes, err = json.Marshal(state.CurrentDraft)
		if err != nil {
			return fmt.Errorf("failed to marshal current draft: %w", err)
		}
	} else {
		draftBytes = []byte("{}")
	}

	var pendingAmb *string
	if state.PendingAmbiguity != "" {
		p := state.PendingAmbiguity
		pendingAmb = &p
	}

	var lastQ *string
	if state.LastQuestion != "" {
		q := state.LastQuestion
		lastQ = &q
	}

	query := `
		UPDATE agent_conversations
		SET status = $3,
		    current_draft = $4,
		    pending_ambiguity = $5,
		    clarification_attempts = $6,
		    last_question = $7,
		    last_inbound_message_id = $8,
		    correlation_id = $9,
		    updated_at = now()
		WHERE session = $1 AND customer_phone = $2
	`

	_, err = s.db.Exec(ctx, query,
		state.Session,
		state.CustomerPhone,
		state.Status,
		draftBytes,
		pendingAmb,
		state.ClarificationAttempts,
		lastQ,
		state.LastInboundMessageID,
		state.CorrelationID,
	)
	if err != nil {
		return fmt.Errorf("failed to save conversation: %w", err)
	}

	return nil
}

// Reset clears the conversation state back to COLLECTING.
func (s *PGConversationStore) Reset(ctx context.Context, session, customerPhone string) error {
	if s == nil || s.db == nil {
		return nil
	}

	query := `
		UPDATE agent_conversations
		SET status = 'COLLECTING',
		    current_draft = '{}'::jsonb,
		    pending_ambiguity = NULL,
		    clarification_attempts = 0,
		    last_question = NULL,
		    updated_at = now()
		WHERE session = $1 AND customer_phone = $2
	`
	_, err := s.db.Exec(ctx, query, session, customerPhone)
	return err
}

func scanConversationState(row rowScanner) (*ConversationState, error) {
	var state ConversationState
	var draftRaw json.RawMessage
	var pendingAmb string
	var lastQ string
	var lastInboundID *string

	err := row.Scan(
		&state.ID,
		&state.Session,
		&state.CustomerPhone,
		&state.Status,
		&draftRaw,
		&pendingAmb,
		&state.ClarificationAttempts,
		&lastQ,
		&lastInboundID,
		&state.CorrelationID,
		&state.CreatedAt,
		&state.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrConversationNotFound
		}
		return nil, err
	}

	state.PendingAmbiguity = pendingAmb
	state.LastQuestion = lastQ
	state.LastInboundMessageID = lastInboundID

	if len(draftRaw) > 0 && string(draftRaw) != "{}" && string(draftRaw) != "null" {
		var draft DraftCandidate
		if err := json.Unmarshal(draftRaw, &draft); err == nil {
			state.CurrentDraft = &draft
		}
	}

	return &state, nil
}

// MemoryConversationStore is an in-memory thread-safe implementation of ConversationStore for unit tests.
type MemoryConversationStore struct {
	mu            sync.Mutex
	conversations map[string]*ConversationState
}

// NewMemoryConversationStore creates a new MemoryConversationStore.
func NewMemoryConversationStore() *MemoryConversationStore {
	return &MemoryConversationStore{
		conversations: make(map[string]*ConversationState),
	}
}

func key(session, phone string) string {
	return fmt.Sprintf("%s:%s", session, phone)
}

func (m *MemoryConversationStore) GetOrCreate(ctx context.Context, session, customerPhone, correlationID string) (*ConversationState, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	k := key(session, customerPhone)
	if existing, ok := m.conversations[k]; ok {
		return existing, nil
	}

	newState := &ConversationState{
		ID:            newID(),
		Session:       session,
		CustomerPhone: customerPhone,
		Status:        ConversationCollecting,
		CorrelationID: correlationID,
		CreatedAt:     time.Now().UTC(),
		UpdatedAt:     time.Now().UTC(),
	}
	m.conversations[k] = newState
	return newState, nil
}

func (m *MemoryConversationStore) Save(ctx context.Context, state *ConversationState) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if state == nil {
		return nil
	}

	k := key(state.Session, state.CustomerPhone)
	state.UpdatedAt = time.Now().UTC()
	m.conversations[k] = state
	return nil
}

func (m *MemoryConversationStore) Reset(ctx context.Context, session, customerPhone string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	k := key(session, customerPhone)
	if state, ok := m.conversations[k]; ok {
		state.Status = ConversationCollecting
		state.CurrentDraft = nil
		state.PendingAmbiguity = ""
		state.ClarificationAttempts = 0
		state.LastQuestion = ""
		state.UpdatedAt = time.Now().UTC()
	}
	return nil
}
