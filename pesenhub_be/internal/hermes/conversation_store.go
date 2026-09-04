package hermes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrConversationNotFound = errors.New("conversation state not found")
)

// ConversationStore defines persistence and handoff operations for customer conversation sessions.
type ConversationStore interface {
	GetOrCreate(ctx context.Context, session, customerPhone, correlationID string) (*ConversationState, error)
	Save(ctx context.Context, state *ConversationState) error
	Reset(ctx context.Context, session, customerPhone string) error
	Pause(ctx context.Context, session, customerPhone, actor, actorRole, reason, correlationID string) (*ConversationState, error)
	Resume(ctx context.Context, session, customerPhone, actor, actorRole, reason, correlationID string) (*ConversationState, error)
	Assign(ctx context.Context, session, customerPhone, actor, actorRole, assignedTo, correlationID string) (*ConversationState, error)
	Resolve(ctx context.Context, session, customerPhone, actor, actorRole, resolution string, resumeAutomation bool, correlationID string) (*ConversationState, error)
	ListHandoffQueue(ctx context.Context, filter HandoffQueueFilter) ([]HandoffQueueItem, int, error)
	RecordAuditEvent(ctx context.Context, event *ConversationAuditEvent) error
	GetAuditEvents(ctx context.Context, conversationID string) ([]ConversationAuditEvent, error)
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
			ID:              newID(),
			Session:         session,
			CustomerPhone:   customerPhone,
			Status:          ConversationCollecting,
			HandoffStatus:   HandoffStatusNone,
			HandoffPriority: HandoffPriorityNormal,
			CorrelationID:   correlationID,
			CreatedAt:       time.Now().UTC(),
			UpdatedAt:       time.Now().UTC(),
		}, nil
	}

	querySelect := `
		SELECT id::text, session, customer_phone, status, current_draft,
		       COALESCE(pending_ambiguity, ''), clarification_attempts,
		       COALESCE(last_question, ''), last_inbound_message_id::text,
		       correlation_id, is_paused, paused_by, paused_at, paused_reason,
		       resumed_by, resumed_at, handoff_status, handoff_reason,
		       handoff_priority, assigned_to, assigned_at, resolved_at,
		       tool_failure_count, COALESCE(confirmation_token, ''), draft_version, last_order_id::text,
		       created_at, updated_at
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
		ID:              newID(),
		Session:         session,
		CustomerPhone:   customerPhone,
		Status:          ConversationCollecting,
		HandoffStatus:   HandoffStatusNone,
		HandoffPriority: HandoffPriorityNormal,
		CorrelationID:   correlationID,
		DraftVersion:    1,
		CreatedAt:       time.Now().UTC(),
		UpdatedAt:       time.Now().UTC(),
	}

	queryInsert := `
		INSERT INTO agent_conversations (
			id, session, customer_phone, status, current_draft,
			pending_ambiguity, clarification_attempts, last_question,
			last_inbound_message_id, correlation_id, is_paused,
			handoff_status, handoff_priority, tool_failure_count,
			confirmation_token, draft_version, last_order_id,
			created_at, updated_at
		) VALUES (
			$1, $2, $3, $4, $5,
			$6, $7, $8,
			$9, $10, $11,
			$12, $13, $14,
			$15, $16, $17,
			$18, $19
		)
		ON CONFLICT (session, customer_phone) DO NOTHING
		RETURNING id::text, session, customer_phone, status, current_draft,
		          COALESCE(pending_ambiguity, ''), clarification_attempts,
		          COALESCE(last_question, ''), last_inbound_message_id::text,
		          correlation_id, is_paused, paused_by, paused_at, paused_reason,
		          resumed_by, resumed_at, handoff_status, handoff_reason,
		          handoff_priority, assigned_to, assigned_at, resolved_at,
		          tool_failure_count, COALESCE(confirmation_token, ''), draft_version, last_order_id::text,
		          created_at, updated_at
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
		false,
		newRecord.HandoffStatus,
		newRecord.HandoffPriority,
		0,
		nil,
		newRecord.DraftVersion,
		nil,
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

	if state.HandoffStatus == "" {
		state.HandoffStatus = HandoffStatusNone
	}
	var confToken *string
	if state.ConfirmationToken != "" {
		t := state.ConfirmationToken
		confToken = &t
	}
	draftVersion := state.DraftVersion
	if draftVersion < 1 {
		draftVersion = 1
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
		    is_paused = $10,
		    paused_by = $11,
		    paused_at = $12,
		    paused_reason = $13,
		    resumed_by = $14,
		    resumed_at = $15,
		    handoff_status = $16,
		    handoff_reason = $17,
		    handoff_priority = $18,
		    assigned_to = $19,
		    assigned_at = $20,
		    resolved_at = $21,
		    tool_failure_count = $22,
		    confirmation_token = $23,
		    draft_version = $24,
		    last_order_id = $25,
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
		state.IsPaused,
		state.PausedBy,
		state.PausedAt,
		state.PausedReason,
		state.ResumedBy,
		state.ResumedAt,
		state.HandoffStatus,
		state.HandoffReason,
		state.HandoffPriority,
		state.AssignedTo,
		state.AssignedAt,
		state.ResolvedAt,
		state.ToolFailureCount,
		confToken,
		draftVersion,
		state.LastOrderID,
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
		    is_paused = false,
		    handoff_status = 'NONE',
		    handoff_reason = NULL,
		    handoff_priority = 'NORMAL',
		    assigned_to = NULL,
		    assigned_at = NULL,
		    resolved_at = NULL,
		    tool_failure_count = 0,
		    updated_at = now()
		WHERE session = $1 AND customer_phone = $2
	`
	_, err := s.db.Exec(ctx, query, session, customerPhone)
	return err
}

// Pause pauses automation for a conversation and records audit log.
func (s *PGConversationStore) Pause(ctx context.Context, session, customerPhone, actor, actorRole, reason, correlationID string) (*ConversationState, error) {
	state, err := s.GetOrCreate(ctx, session, customerPhone, correlationID)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	state.IsPaused = true
	state.Status = ConversationPaused
	state.PausedBy = &actor
	state.PausedAt = &now
	state.PausedReason = &reason
	if state.HandoffStatus == HandoffStatusNone {
		state.HandoffStatus = HandoffStatusPending
	}
	if state.HandoffReason == nil {
		state.HandoffReason = &reason
	}
	state.CorrelationID = correlationID

	if err := s.Save(ctx, state); err != nil {
		return nil, err
	}

	meta, _ := json.Marshal(map[string]any{
		"status":         state.Status,
		"handoff_status": state.HandoffStatus,
	})
	audit := &ConversationAuditEvent{
		ID:             newID(),
		ConversationID: state.ID,
		Session:        session,
		CustomerPhone:  customerPhone,
		Action:         HandoffActionPaused,
		Actor:          actor,
		ActorRole:      actorRole,
		Reason:         reason,
		Metadata:       meta,
		CorrelationID:  correlationID,
		CreatedAt:      now,
	}
	_ = s.RecordAuditEvent(ctx, audit)

	return state, nil
}

// Resume unpauses automation for a conversation without replaying old messages.
func (s *PGConversationStore) Resume(ctx context.Context, session, customerPhone, actor, actorRole, reason, correlationID string) (*ConversationState, error) {
	state, err := s.GetOrCreate(ctx, session, customerPhone, correlationID)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	state.IsPaused = false
	state.Status = ConversationCollecting
	state.ResumedBy = &actor
	state.ResumedAt = &now
	state.HandoffStatus = HandoffStatusResolved
	state.ResolvedAt = &now
	state.PendingAmbiguity = ""
	state.ClarificationAttempts = 0
	state.ToolFailureCount = 0
	state.CorrelationID = correlationID

	if err := s.Save(ctx, state); err != nil {
		return nil, err
	}

	meta, _ := json.Marshal(map[string]any{
		"status":         state.Status,
		"handoff_status": state.HandoffStatus,
	})
	audit := &ConversationAuditEvent{
		ID:             newID(),
		ConversationID: state.ID,
		Session:        session,
		CustomerPhone:  customerPhone,
		Action:         HandoffActionResumed,
		Actor:          actor,
		ActorRole:      actorRole,
		Reason:         reason,
		Metadata:       meta,
		CorrelationID:  correlationID,
		CreatedAt:      now,
	}
	_ = s.RecordAuditEvent(ctx, audit)

	return state, nil
}

// Assign assigns a staff member to handle the conversation.
func (s *PGConversationStore) Assign(ctx context.Context, session, customerPhone, actor, actorRole, assignedTo, correlationID string) (*ConversationState, error) {
	state, err := s.GetOrCreate(ctx, session, customerPhone, correlationID)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	state.HandoffStatus = HandoffStatusAssigned
	state.AssignedTo = &assignedTo
	state.AssignedAt = &now
	state.CorrelationID = correlationID

	if err := s.Save(ctx, state); err != nil {
		return nil, err
	}

	meta, _ := json.Marshal(map[string]any{
		"assigned_to": assignedTo,
	})
	audit := &ConversationAuditEvent{
		ID:             newID(),
		ConversationID: state.ID,
		Session:        session,
		CustomerPhone:  customerPhone,
		Action:         HandoffActionAssigned,
		Actor:          actor,
		ActorRole:      actorRole,
		Reason:         fmt.Sprintf("assigned to %s", assignedTo),
		Metadata:       meta,
		CorrelationID:  correlationID,
		CreatedAt:      now,
	}
	_ = s.RecordAuditEvent(ctx, audit)

	return state, nil
}

// Resolve marks handoff as resolved, optionally resuming agent automation.
func (s *PGConversationStore) Resolve(ctx context.Context, session, customerPhone, actor, actorRole, resolution string, resumeAutomation bool, correlationID string) (*ConversationState, error) {
	state, err := s.GetOrCreate(ctx, session, customerPhone, correlationID)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	state.HandoffStatus = HandoffStatusResolved
	state.ResolvedAt = &now
	if resumeAutomation {
		state.IsPaused = false
		state.Status = ConversationCollecting
		state.ResumedBy = &actor
		state.ResumedAt = &now
		state.PendingAmbiguity = ""
		state.ClarificationAttempts = 0
		state.ToolFailureCount = 0
	}
	state.CorrelationID = correlationID

	if err := s.Save(ctx, state); err != nil {
		return nil, err
	}

	meta, _ := json.Marshal(map[string]any{
		"resume_automation": resumeAutomation,
	})
	audit := &ConversationAuditEvent{
		ID:             newID(),
		ConversationID: state.ID,
		Session:        session,
		CustomerPhone:  customerPhone,
		Action:         HandoffActionResolved,
		Actor:          actor,
		ActorRole:      actorRole,
		Reason:         resolution,
		Metadata:       meta,
		CorrelationID:  correlationID,
		CreatedAt:      now,
	}
	_ = s.RecordAuditEvent(ctx, audit)

	return state, nil
}

// ListHandoffQueue queries conversations requiring staff attention.
func (s *PGConversationStore) ListHandoffQueue(ctx context.Context, filter HandoffQueueFilter) ([]HandoffQueueItem, int, error) {
	if s == nil || s.db == nil {
		return nil, 0, nil
	}

	var whereClauses []string
	var args []any
	argIdx := 1

	if filter.Status != "" && strings.ToUpper(filter.Status) != "ALL" {
		whereClauses = append(whereClauses, fmt.Sprintf("handoff_status = $%d", argIdx))
		args = append(args, strings.ToUpper(filter.Status))
		argIdx++
	} else {
		whereClauses = append(whereClauses, "handoff_status IN ('PENDING', 'ASSIGNED')")
	}

	if filter.Priority != "" {
		whereClauses = append(whereClauses, fmt.Sprintf("handoff_priority = $%d", argIdx))
		args = append(args, strings.ToUpper(filter.Priority))
		argIdx++
	}

	whereSQL := strings.Join(whereClauses, " AND ")

	countQuery := fmt.Sprintf("SELECT count(*) FROM agent_conversations WHERE %s", whereSQL)
	var total int
	err := s.db.QueryRow(ctx, countQuery, args...).Scan(&total)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to count handoff queue: %w", err)
	}

	limit := filter.Limit
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	offset := filter.Offset
	if offset < 0 {
		offset = 0
	}

	selectQuery := fmt.Sprintf(`
		SELECT id::text, session, customer_phone, status, is_paused,
		       handoff_status, handoff_reason, handoff_priority,
		       assigned_to, assigned_at, clarification_attempts,
		       COALESCE(last_question, ''), last_inbound_message_id::text,
		       current_draft, COALESCE(confirmation_token, ''), draft_version, last_order_id::text,
		       created_at, updated_at
		FROM agent_conversations
		WHERE %s
		ORDER BY CASE handoff_priority
		             WHEN 'URGENT' THEN 1
		             WHEN 'HIGH' THEN 2
		             WHEN 'NORMAL' THEN 3
		             ELSE 4
		         END ASC,
		         updated_at DESC
		LIMIT $%d OFFSET $%d
	`, whereSQL, argIdx, argIdx+1)

	args = append(args, limit, offset)

	rows, err := s.db.Query(ctx, selectQuery, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to query handoff queue: %w", err)
	}
	defer rows.Close()

	var items []HandoffQueueItem
	for rows.Next() {
		var it HandoffQueueItem
		var draftRaw json.RawMessage
		err := rows.Scan(
			&it.ID,
			&it.Session,
			&it.CustomerPhone,
			&it.Status,
			&it.IsPaused,
			&it.HandoffStatus,
			&it.HandoffReason,
			&it.HandoffPriority,
			&it.AssignedTo,
			&it.AssignedAt,
			&it.ClarificationAttempts,
			&it.LastQuestion,
			&it.LastInboundMessageID,
			&draftRaw,
			&it.ConfirmationToken,
			&it.DraftVersion,
			&it.LastOrderID,
			&it.CreatedAt,
			&it.UpdatedAt,
		)
		if err != nil {
			return nil, 0, fmt.Errorf("failed to scan handoff queue item: %w", err)
		}
		if len(draftRaw) > 0 && string(draftRaw) != "{}" && string(draftRaw) != "null" {
			var draft DraftCandidate
			if err := json.Unmarshal(draftRaw, &draft); err == nil {
				it.CurrentDraft = &draft
			}
		}
		items = append(items, it)
	}

	return items, total, nil
}

// RecordAuditEvent writes an audit event entry.
func (s *PGConversationStore) RecordAuditEvent(ctx context.Context, event *ConversationAuditEvent) error {
	if s == nil || s.db == nil || event == nil {
		return nil
	}

	query := `
		INSERT INTO agent_conversation_audits (
			id, conversation_id, session, customer_phone,
			action, actor, actor_role, reason,
			metadata, correlation_id, created_at
		) VALUES (
			$1, $2, $3, $4,
			$5, $6, $7, $8,
			$9, $10, $11
		)
	`
	meta := event.Metadata
	if len(meta) == 0 {
		meta = json.RawMessage("{}")
	}

	createdAt := event.CreatedAt
	if createdAt.IsZero() {
		createdAt = time.Now().UTC()
	}

	_, err := s.db.Exec(ctx, query,
		event.ID,
		event.ConversationID,
		event.Session,
		event.CustomerPhone,
		event.Action,
		event.Actor,
		event.ActorRole,
		event.Reason,
		meta,
		event.CorrelationID,
		createdAt,
	)
	return err
}

// GetAuditEvents lists audit events for a conversation.
func (s *PGConversationStore) GetAuditEvents(ctx context.Context, conversationID string) ([]ConversationAuditEvent, error) {
	if s == nil || s.db == nil {
		return nil, nil
	}

	query := `
		SELECT id::text, conversation_id::text, session, customer_phone,
		       action, actor, actor_role, reason,
		       metadata, correlation_id, created_at
		FROM agent_conversation_audits
		WHERE conversation_id = $1
		ORDER BY created_at ASC
	`

	rows, err := s.db.Query(ctx, query, conversationID)
	if err != nil {
		return nil, fmt.Errorf("failed to query audit events: %w", err)
	}
	defer rows.Close()

	var events []ConversationAuditEvent
	for rows.Next() {
		var e ConversationAuditEvent
		var meta json.RawMessage
		err := rows.Scan(
			&e.ID,
			&e.ConversationID,
			&e.Session,
			&e.CustomerPhone,
			&e.Action,
			&e.Actor,
			&e.ActorRole,
			&e.Reason,
			&meta,
			&e.CorrelationID,
			&e.CreatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan audit event: %w", err)
		}
		e.Metadata = meta
		events = append(events, e)
	}

	return events, nil
}

func scanConversationState(row rowScanner) (*ConversationState, error) {
	var state ConversationState
	var draftRaw json.RawMessage
	var pendingAmb string
	var lastQ string
	var lastInboundID *string
	var pausedBy *string
	var pausedAt *time.Time
	var pausedReason *string
	var resumedBy *string
	var resumedAt *time.Time
	var handoffReason *string
	var assignedTo *string
	var assignedAt *time.Time
	var resolvedAt *time.Time
	var confToken string
	var draftVersion int
	var lastOrderID *string

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
		&state.IsPaused,
		&pausedBy,
		&pausedAt,
		&pausedReason,
		&resumedBy,
		&resumedAt,
		&state.HandoffStatus,
		&handoffReason,
		&state.HandoffPriority,
		&assignedTo,
		&assignedAt,
		&resolvedAt,
		&state.ToolFailureCount,
		&confToken,
		&draftVersion,
		&lastOrderID,
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
	state.PausedBy = pausedBy
	state.PausedAt = pausedAt
	state.PausedReason = pausedReason
	state.ResumedBy = resumedBy
	state.ResumedAt = resumedAt
	state.HandoffReason = handoffReason
	state.AssignedTo = assignedTo
	state.AssignedAt = assignedAt
	state.ResolvedAt = resolvedAt
	state.ConfirmationToken = confToken
	state.DraftVersion = draftVersion
	state.LastOrderID = lastOrderID

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
	audits        []ConversationAuditEvent
}

// NewMemoryConversationStore creates a new MemoryConversationStore.
func NewMemoryConversationStore() *MemoryConversationStore {
	return &MemoryConversationStore{
		conversations: make(map[string]*ConversationState),
		audits:        make([]ConversationAuditEvent, 0),
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
		ID:              newID(),
		Session:         session,
		CustomerPhone:   customerPhone,
		Status:          ConversationCollecting,
		HandoffStatus:   HandoffStatusNone,
		HandoffPriority: HandoffPriorityNormal,
		CorrelationID:   correlationID,
		CreatedAt:       time.Now().UTC(),
		UpdatedAt:       time.Now().UTC(),
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
		state.IsPaused = false
		state.HandoffStatus = HandoffStatusNone
		state.HandoffReason = nil
		state.HandoffPriority = HandoffPriorityNormal
		state.AssignedTo = nil
		state.AssignedAt = nil
		state.ResolvedAt = nil
		state.ToolFailureCount = 0
		state.ConfirmationToken = ""
		state.DraftVersion = 1
		state.LastOrderID = nil
		state.UpdatedAt = time.Now().UTC()
	}
	return nil
}

func (m *MemoryConversationStore) Pause(ctx context.Context, session, customerPhone, actor, actorRole, reason, correlationID string) (*ConversationState, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	k := key(session, customerPhone)
	state, ok := m.conversations[k]
	if !ok {
		state = &ConversationState{
			ID:              newID(),
			Session:         session,
			CustomerPhone:   customerPhone,
			Status:          ConversationCollecting,
			HandoffStatus:   HandoffStatusNone,
			HandoffPriority: HandoffPriorityNormal,
			CorrelationID:   correlationID,
			CreatedAt:       time.Now().UTC(),
			UpdatedAt:       time.Now().UTC(),
		}
		m.conversations[k] = state
	}

	now := time.Now().UTC()
	state.IsPaused = true
	state.Status = ConversationPaused
	state.PausedBy = &actor
	state.PausedAt = &now
	state.PausedReason = &reason
	if state.HandoffStatus == HandoffStatusNone {
		state.HandoffStatus = HandoffStatusPending
	}
	if state.HandoffReason == nil {
		state.HandoffReason = &reason
	}
	state.CorrelationID = correlationID
	state.UpdatedAt = now

	meta, _ := json.Marshal(map[string]any{
		"status":         state.Status,
		"handoff_status": state.HandoffStatus,
	})
	m.audits = append(m.audits, ConversationAuditEvent{
		ID:             newID(),
		ConversationID: state.ID,
		Session:        session,
		CustomerPhone:  customerPhone,
		Action:         HandoffActionPaused,
		Actor:          actor,
		ActorRole:      actorRole,
		Reason:         reason,
		Metadata:       meta,
		CorrelationID:  correlationID,
		CreatedAt:      now,
	})

	return state, nil
}

func (m *MemoryConversationStore) Resume(ctx context.Context, session, customerPhone, actor, actorRole, reason, correlationID string) (*ConversationState, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	k := key(session, customerPhone)
	state, ok := m.conversations[k]
	if !ok {
		return nil, ErrConversationNotFound
	}

	now := time.Now().UTC()
	state.IsPaused = false
	state.Status = ConversationCollecting
	state.ResumedBy = &actor
	state.ResumedAt = &now
	state.HandoffStatus = HandoffStatusResolved
	state.ResolvedAt = &now
	state.PendingAmbiguity = ""
	state.ClarificationAttempts = 0
	state.ToolFailureCount = 0
	state.CorrelationID = correlationID
	state.UpdatedAt = now

	meta, _ := json.Marshal(map[string]any{
		"status":         state.Status,
		"handoff_status": state.HandoffStatus,
	})
	m.audits = append(m.audits, ConversationAuditEvent{
		ID:             newID(),
		ConversationID: state.ID,
		Session:        session,
		CustomerPhone:  customerPhone,
		Action:         HandoffActionResumed,
		Actor:          actor,
		ActorRole:      actorRole,
		Reason:         reason,
		Metadata:       meta,
		CorrelationID:  correlationID,
		CreatedAt:      now,
	})

	return state, nil
}

func (m *MemoryConversationStore) Assign(ctx context.Context, session, customerPhone, actor, actorRole, assignedTo, correlationID string) (*ConversationState, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	k := key(session, customerPhone)
	state, ok := m.conversations[k]
	if !ok {
		return nil, ErrConversationNotFound
	}

	now := time.Now().UTC()
	state.HandoffStatus = HandoffStatusAssigned
	state.AssignedTo = &assignedTo
	state.AssignedAt = &now
	state.CorrelationID = correlationID
	state.UpdatedAt = now

	meta, _ := json.Marshal(map[string]any{
		"assigned_to": assignedTo,
	})
	m.audits = append(m.audits, ConversationAuditEvent{
		ID:             newID(),
		ConversationID: state.ID,
		Session:        session,
		CustomerPhone:  customerPhone,
		Action:         HandoffActionAssigned,
		Actor:          actor,
		ActorRole:      actorRole,
		Reason:         fmt.Sprintf("assigned to %s", assignedTo),
		Metadata:       meta,
		CorrelationID:  correlationID,
		CreatedAt:      now,
	})

	return state, nil
}

func (m *MemoryConversationStore) Resolve(ctx context.Context, session, customerPhone, actor, actorRole, resolution string, resumeAutomation bool, correlationID string) (*ConversationState, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	k := key(session, customerPhone)
	state, ok := m.conversations[k]
	if !ok {
		return nil, ErrConversationNotFound
	}

	now := time.Now().UTC()
	state.HandoffStatus = HandoffStatusResolved
	state.ResolvedAt = &now
	if resumeAutomation {
		state.IsPaused = false
		state.Status = ConversationCollecting
		state.ResumedBy = &actor
		state.ResumedAt = &now
		state.PendingAmbiguity = ""
		state.ClarificationAttempts = 0
		state.ToolFailureCount = 0
	}
	state.CorrelationID = correlationID
	state.UpdatedAt = now

	meta, _ := json.Marshal(map[string]any{
		"resume_automation": resumeAutomation,
	})
	m.audits = append(m.audits, ConversationAuditEvent{
		ID:             newID(),
		ConversationID: state.ID,
		Session:        session,
		CustomerPhone:  customerPhone,
		Action:         HandoffActionResolved,
		Actor:          actor,
		ActorRole:      actorRole,
		Reason:         resolution,
		Metadata:       meta,
		CorrelationID:  correlationID,
		CreatedAt:      now,
	})

	return state, nil
}

func (m *MemoryConversationStore) ListHandoffQueue(ctx context.Context, filter HandoffQueueFilter) ([]HandoffQueueItem, int, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	var matching []HandoffQueueItem
	for _, conv := range m.conversations {
		status := conv.HandoffStatus
		if filter.Status != "" && strings.ToUpper(filter.Status) != "ALL" {
			if !strings.EqualFold(status, filter.Status) {
				continue
			}
		} else {
			if status != HandoffStatusPending && status != HandoffStatusAssigned {
				continue
			}
		}

		if filter.Priority != "" && !strings.EqualFold(conv.HandoffPriority, filter.Priority) {
			continue
		}

		matching = append(matching, HandoffQueueItem{
			ID:                    conv.ID,
			Session:               conv.Session,
			CustomerPhone:         conv.CustomerPhone,
			Status:                conv.Status,
			IsPaused:              conv.IsPaused,
			HandoffStatus:         conv.HandoffStatus,
			HandoffReason:         conv.HandoffReason,
			HandoffPriority:       conv.HandoffPriority,
			AssignedTo:            conv.AssignedTo,
			AssignedAt:            conv.AssignedAt,
			ClarificationAttempts: conv.ClarificationAttempts,
			LastQuestion:          conv.LastQuestion,
			LastInboundMessageID:  conv.LastInboundMessageID,
			CurrentDraft:          conv.CurrentDraft,
			ConfirmationToken:     conv.ConfirmationToken,
			DraftVersion:          conv.DraftVersion,
			LastOrderID:           conv.LastOrderID,
			CreatedAt:             conv.CreatedAt,
			UpdatedAt:             conv.UpdatedAt,
		})
	}

	priorityWeight := func(p string) int {
		switch strings.ToUpper(p) {
		case HandoffPriorityUrgent:
			return 1
		case HandoffPriorityHigh:
			return 2
		case HandoffPriorityNormal:
			return 3
		default:
			return 4
		}
	}

	sort.Slice(matching, func(i, j int) bool {
		pi, pj := priorityWeight(matching[i].HandoffPriority), priorityWeight(matching[j].HandoffPriority)
		if pi != pj {
			return pi < pj
		}
		return matching[i].UpdatedAt.After(matching[j].UpdatedAt)
	})

	total := len(matching)
	offset := filter.Offset
	if offset < 0 {
		offset = 0
	}
	if offset > total {
		offset = total
	}
	limit := filter.Limit
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	end := offset + limit
	if end > total {
		end = total
	}

	return matching[offset:end], total, nil
}

func (m *MemoryConversationStore) RecordAuditEvent(ctx context.Context, event *ConversationAuditEvent) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if event == nil {
		return nil
	}
	if event.CreatedAt.IsZero() {
		event.CreatedAt = time.Now().UTC()
	}
	m.audits = append(m.audits, *event)
	return nil
}

func (m *MemoryConversationStore) GetAuditEvents(ctx context.Context, conversationID string) ([]ConversationAuditEvent, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	var matched []ConversationAuditEvent
	for _, a := range m.audits {
		if a.ConversationID == conversationID {
			matched = append(matched, a)
		}
	}
	return matched, nil
}
