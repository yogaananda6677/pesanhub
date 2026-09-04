package hermes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrRunNotFound = errors.New("agent run not found")
)

// RunStore defines the persistence contract for agent extraction runs.
type RunStore interface {
	RecordRun(ctx context.Context, run *AgentRun) error
	GetByID(ctx context.Context, id string) (*AgentRun, error)
	GetByCorrelationID(ctx context.Context, correlationID string) (*AgentRun, error)
}

// Store is the PostgreSQL implementation of RunStore.
type Store struct {
	db *pgxpool.Pool
}

// NewStore creates a new Store with a PostgreSQL connection pool.
func NewStore(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

// RecordRun persists an AgentRun record into PostgreSQL.
func (s *Store) RecordRun(ctx context.Context, run *AgentRun) error {
	if s == nil || s.db == nil {
		return nil
	}

	if run.ID == "" {
		run.ID = newID()
	}
	if run.CreatedAt.IsZero() {
		run.CreatedAt = time.Now().UTC()
	}
	if len(run.ExtractedDraft) == 0 {
		run.ExtractedDraft = json.RawMessage("{}")
	}
	if len(run.ToolCalls) == 0 {
		run.ToolCalls = json.RawMessage("[]")
	}

	query := `
		INSERT INTO agent_runs (
			id, inbound_message_id, session, customer_phone, model,
			prompt_version, confidence_score, is_ambiguous, ambiguity_reasons,
			extracted_draft, tool_calls, duration_ms, status, error_message,
			correlation_id, created_at
		) VALUES (
			$1, $2, $3, $4, $5,
			$6, $7, $8, $9,
			$10, $11, $12, $13, $14,
			$15, $16
		)
	`

	_, err := s.db.Exec(ctx, query,
		run.ID,
		run.InboundMessageID,
		run.Session,
		run.CustomerPhone,
		run.Model,
		run.PromptVersion,
		run.ConfidenceScore,
		run.IsAmbiguous,
		run.AmbiguityReasons,
		run.ExtractedDraft,
		run.ToolCalls,
		run.DurationMs,
		run.Status,
		run.ErrorMessage,
		run.CorrelationID,
		run.CreatedAt,
	)
	if err != nil {
		return fmt.Errorf("failed to insert agent_run: %w", err)
	}

	return nil
}

// GetByID retrieves an AgentRun by its UUID.
func (s *Store) GetByID(ctx context.Context, id string) (*AgentRun, error) {
	if s == nil || s.db == nil {
		return nil, ErrRunNotFound
	}

	query := `
		SELECT id::text, inbound_message_id::text, session, COALESCE(customer_phone, ''),
		       model, prompt_version, confidence_score, is_ambiguous,
		       COALESCE(ambiguity_reasons, '{}'), extracted_draft, tool_calls,
		       duration_ms, status, error_message, correlation_id, created_at
		FROM agent_runs
		WHERE id = $1
	`
	row := s.db.QueryRow(ctx, query, id)
	return scanAgentRun(row)
}

// GetByCorrelationID retrieves an AgentRun by correlation ID.
func (s *Store) GetByCorrelationID(ctx context.Context, correlationID string) (*AgentRun, error) {
	if s == nil || s.db == nil {
		return nil, ErrRunNotFound
	}

	query := `
		SELECT id::text, inbound_message_id::text, session, COALESCE(customer_phone, ''),
		       model, prompt_version, confidence_score, is_ambiguous,
		       COALESCE(ambiguity_reasons, '{}'), extracted_draft, tool_calls,
		       duration_ms, status, error_message, correlation_id, created_at
		FROM agent_runs
		WHERE correlation_id = $1
		ORDER BY created_at DESC
		LIMIT 1
	`
	row := s.db.QueryRow(ctx, query, correlationID)
	return scanAgentRun(row)
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanAgentRun(row rowScanner) (*AgentRun, error) {
	var run AgentRun
	var inboundID *string
	var reasons []string

	err := row.Scan(
		&run.ID,
		&inboundID,
		&run.Session,
		&run.CustomerPhone,
		&run.Model,
		&run.PromptVersion,
		&run.ConfidenceScore,
		&run.IsAmbiguous,
		&reasons,
		&run.ExtractedDraft,
		&run.ToolCalls,
		&run.DurationMs,
		&run.Status,
		&run.ErrorMessage,
		&run.CorrelationID,
		&run.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrRunNotFound
		}
		return nil, err
	}

	run.InboundMessageID = inboundID
	run.AmbiguityReasons = reasons
	return &run, nil
}

// MemoryStore is an in-memory implementation of RunStore for testing.
type MemoryStore struct {
	Runs           []*AgentRun
	RunsByID       map[string]*AgentRun
	RunsByCorr     map[string]*AgentRun
	RecordRunError error
}

// NewMemoryStore creates a new in-memory RunStore.
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		Runs:       make([]*AgentRun, 0),
		RunsByID:   make(map[string]*AgentRun),
		RunsByCorr: make(map[string]*AgentRun),
	}
}

func (m *MemoryStore) RecordRun(ctx context.Context, run *AgentRun) error {
	if m.RecordRunError != nil {
		return m.RecordRunError
	}
	if run.ID == "" {
		run.ID = newID()
	}
	if run.CreatedAt.IsZero() {
		run.CreatedAt = time.Now().UTC()
	}
	m.Runs = append(m.Runs, run)
	m.RunsByID[run.ID] = run
	m.RunsByCorr[run.CorrelationID] = run
	return nil
}

func (m *MemoryStore) GetByID(ctx context.Context, id string) (*AgentRun, error) {
	run, ok := m.RunsByID[id]
	if !ok {
		return nil, ErrRunNotFound
	}
	return run, nil
}

func (m *MemoryStore) GetByCorrelationID(ctx context.Context, correlationID string) (*AgentRun, error) {
	run, ok := m.RunsByCorr[correlationID]
	if !ok {
		return nil, ErrRunNotFound
	}
	return run, nil
}
