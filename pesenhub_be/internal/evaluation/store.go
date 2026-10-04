package evaluation

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"pesenhub/backend/internal/customer"
	dbx "pesenhub/backend/internal/database"
)

type Store struct {
	db *dbx.Pool
}

func NewStore(db *dbx.Pool) *Store {
	return &Store{db: db}
}

func (s *Store) RecordTurn(ctx context.Context, in RecordTurnInput) (*Evaluation, error) {
	id := customer.NewID()
	branchID := strings.TrimSpace(in.BranchID)
	if branchID == "" {
		branchID = "b0000000-0000-0000-0000-000000000001"
	}

	draft := in.ExtractedDraft
	if len(draft) == 0 {
		draft = json.RawMessage("{}")
	}

	now := time.Now()
	q := `INSERT INTO ai_evaluations (
	        id, branch_id, inbound_message_id, conversation_id, sender_phone, customer_name,
	        input_text, ai_reply, extracted_draft, rating, is_reviewed, created_at, updated_at
	      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)`

	_, err := s.db.Exec(ctx, q,
		id, branchID, in.InboundMessageID, in.ConversationID, in.SenderPhone, strings.TrimSpace(in.CustomerName),
		in.InputText, in.AIReply, string(draft), RatingUnrated, false, now, now,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to record AI turn evaluation: %w", err)
	}

	return s.GetByID(ctx, id)
}

func (s *Store) List(ctx context.Context, filter ListFilter) ([]Evaluation, error) {
	q := `SELECT id, branch_id, inbound_message_id, conversation_id, sender_phone, COALESCE(customer_name, ''),
	             input_text, ai_reply, extracted_draft, rating, feedback_category,
	             correction_notes, expected_reply, is_reviewed, reviewed_by, reviewed_at, created_at, updated_at
	      FROM ai_evaluations
	      WHERE 1=1`

	var args []any
	argIdx := 1

	if filter.BranchID != "" {
		q += fmt.Sprintf(" AND branch_id = $%d", argIdx)
		args = append(args, filter.BranchID)
		argIdx++
	}

	if filter.Rating != "" {
		q += fmt.Sprintf(" AND rating = $%d", argIdx)
		args = append(args, filter.Rating)
		argIdx++
	}

	if filter.IsReviewed != nil {
		q += fmt.Sprintf(" AND is_reviewed = $%d", argIdx)
		args = append(args, *filter.IsReviewed)
		argIdx++
	}

	if filter.Search != "" {
		q += fmt.Sprintf(" AND (sender_phone LIKE $%d OR LOWER(input_text) LIKE $%d OR LOWER(ai_reply) LIKE $%d)", argIdx, argIdx, argIdx)
		args = append(args, "%"+strings.ToLower(filter.Search)+"%")
		argIdx++
	}

	q += " ORDER BY created_at DESC"

	if filter.Limit > 0 {
		q += fmt.Sprintf(" LIMIT $%d", argIdx)
		args = append(args, filter.Limit)
	} else {
		q += " LIMIT 100"
	}

	rows, err := s.db.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to query AI evaluations: %w", err)
	}
	defer rows.Close()

	var evals []Evaluation
	for rows.Next() {
		var e Evaluation
		var rawDraft string
		if err := rows.Scan(
			&e.ID, &e.BranchID, &e.InboundMessageID, &e.ConversationID, &e.SenderPhone, &e.CustomerName,
			&e.InputText, &e.AIReply, &rawDraft, &e.Rating, &e.FeedbackCategory,
			&e.CorrectionNotes, &e.ExpectedReply, &e.IsReviewed, &e.ReviewedBy, &e.ReviewedAt, &e.CreatedAt, &e.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("failed to scan AI evaluation: %w", err)
		}
		e.ExtractedDraft = json.RawMessage(rawDraft)
		evals = append(evals, e)
	}

	return evals, nil
}

func (s *Store) GetByID(ctx context.Context, id string) (*Evaluation, error) {
	q := `SELECT id, branch_id, inbound_message_id, conversation_id, sender_phone, COALESCE(customer_name, ''),
	             input_text, ai_reply, extracted_draft, rating, feedback_category,
	             correction_notes, expected_reply, is_reviewed, reviewed_by, reviewed_at, created_at, updated_at
	      FROM ai_evaluations
	      WHERE id = $1
	      LIMIT 1`

	var e Evaluation
	var rawDraft string
	err := s.db.QueryRow(ctx, q, id).Scan(
		&e.ID, &e.BranchID, &e.InboundMessageID, &e.ConversationID, &e.SenderPhone, &e.CustomerName,
		&e.InputText, &e.AIReply, &rawDraft, &e.Rating, &e.FeedbackCategory,
		&e.CorrectionNotes, &e.ExpectedReply, &e.IsReviewed, &e.ReviewedBy, &e.ReviewedAt, &e.CreatedAt, &e.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrEvaluationNotFound
		}
		return nil, fmt.Errorf("failed to get AI evaluation by id: %w", err)
	}

	e.ExtractedDraft = json.RawMessage(rawDraft)
	return &e, nil
}

func (s *Store) SubmitReview(ctx context.Context, id string, reviewer string, in SubmitReviewInput) (*Evaluation, error) {
	rating := strings.TrimSpace(in.Rating)
	if rating == "" {
		rating = RatingGood
	}

	var cat *string
	if strings.TrimSpace(in.FeedbackCategory) != "" {
		c := strings.TrimSpace(in.FeedbackCategory)
		cat = &c
	}

	var notes *string
	if strings.TrimSpace(in.CorrectionNotes) != "" {
		n := strings.TrimSpace(in.CorrectionNotes)
		notes = &n
	}

	var expected *string
	if strings.TrimSpace(in.ExpectedReply) != "" {
		ex := strings.TrimSpace(in.ExpectedReply)
		expected = &ex
	}

	now := time.Now()
	var revBy *string
	if strings.TrimSpace(reviewer) != "" {
		r := strings.TrimSpace(reviewer)
		revBy = &r
	}

	q := `UPDATE ai_evaluations
	      SET rating = $1, feedback_category = $2, correction_notes = $3, expected_reply = $4,
	          is_reviewed = true, reviewed_by = $5, reviewed_at = $6, updated_at = $7
	      WHERE id = $8`

	res, err := s.db.Exec(ctx, q, rating, cat, notes, expected, revBy, now, now, id)
	if err != nil {
		return nil, fmt.Errorf("failed to update evaluation review: %w", err)
	}
	if res.RowsAffected() == 0 {
		return nil, ErrEvaluationNotFound
	}

	return s.GetByID(ctx, id)
}

func (s *Store) ExportDataset(ctx context.Context, branchID string, reviewedOnly bool) ([]TrainingDatasetItem, error) {
	q := `SELECT id, sender_phone, input_text, ai_reply, expected_reply, rating, feedback_category, correction_notes
	      FROM ai_evaluations
	      WHERE 1=1`

	var args []any
	argIdx := 1

	if branchID != "" {
		q += fmt.Sprintf(" AND branch_id = $%d", argIdx)
		args = append(args, branchID)
		argIdx++
	}

	if reviewedOnly {
		q += " AND is_reviewed = true"
	}

	q += " ORDER BY created_at ASC"

	rows, err := s.db.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to export evaluations: %w", err)
	}
	defer rows.Close()

	var dataset []TrainingDatasetItem
	for rows.Next() {
		var id, phone, input, reply string
		var expected, rating, feedbackCat, notes *string
		if err := rows.Scan(&id, &phone, &input, &reply, &expected, &rating, &feedbackCat, &notes); err != nil {
			return nil, fmt.Errorf("failed to scan export row: %w", err)
		}

		targetReply := reply
		if expected != nil && strings.TrimSpace(*expected) != "" {
			targetReply = strings.TrimSpace(*expected)
		}

		item := TrainingDatasetItem{
			Messages: []ChatMessage{
				{
					Role:    "system",
					Content: "Anda adalah Asisten Jenggirat AI, asisten virtual ramah dan komunikatif untuk Martabak & Terang Bulan Jenggirat Kediri.",
				},
				{
					Role:    "user",
					Content: input,
				},
				{
					Role:    "assistant",
					Content: targetReply,
				},
			},
			Metadata: map[string]any{
				"evaluation_id": id,
				"phone":         phone,
			},
		}

		if rating != nil {
			item.Metadata["rating"] = *rating
		}
		if feedbackCat != nil {
			item.Metadata["category"] = *feedbackCat
		}

		dataset = append(dataset, item)
	}

	return dataset, nil
}
