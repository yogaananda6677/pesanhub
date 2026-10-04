package evaluation

import (
	"encoding/json"
	"errors"
	"time"
)

const (
	RatingUnrated         = "UNRATED"
	RatingGood            = "GOOD"
	RatingBad             = "BAD"
	RatingNeedsCorrection = "NEEDS_CORRECTION"

	FeedbackCorrect           = "CORRECT"
	FeedbackWrongMenu         = "WRONG_MENU"
	FeedbackWrongModifier     = "WRONG_MODIFIER"
	FeedbackWrongIntent       = "WRONG_INTENT"
	FeedbackInappropriateTone = "INAPPROPRIATE_TONE"
	FeedbackHallucination     = "HALLUCINATION"
)

var (
	ErrEvaluationNotFound = errors.New("evaluation not found")
	ErrInvalidInput       = errors.New("invalid evaluation input")
)

type Evaluation struct {
	ID               string          `json:"id"`
	BranchID         string          `json:"branch_id"`
	InboundMessageID *string         `json:"inbound_message_id,omitempty"`
	ConversationID   *string         `json:"conversation_id,omitempty"`
	SenderPhone      string          `json:"sender_phone"`
	CustomerName     string          `json:"customer_name,omitempty"`
	InputText        string          `json:"input_text"`
	AIReply          string          `json:"ai_reply"`
	ExtractedDraft   json.RawMessage `json:"extracted_draft"`
	Rating           string          `json:"rating"`
	FeedbackCategory *string         `json:"feedback_category,omitempty"`
	CorrectionNotes  *string         `json:"correction_notes,omitempty"`
	ExpectedReply    *string         `json:"expected_reply,omitempty"`
	IsReviewed       bool            `json:"is_reviewed"`
	ReviewedBy       *string         `json:"reviewed_by,omitempty"`
	ReviewedAt       *time.Time      `json:"reviewed_at,omitempty"`
	CreatedAt        time.Time       `json:"created_at"`
	UpdatedAt        time.Time       `json:"updated_at"`
}

type RecordTurnInput struct {
	BranchID         string          `json:"branch_id"`
	InboundMessageID *string         `json:"inbound_message_id,omitempty"`
	ConversationID   *string         `json:"conversation_id,omitempty"`
	SenderPhone      string          `json:"sender_phone"`
	CustomerName     string          `json:"customer_name,omitempty"`
	InputText        string          `json:"input_text"`
	AIReply          string          `json:"ai_reply"`
	ExtractedDraft   json.RawMessage `json:"extracted_draft,omitempty"`
}

type SubmitReviewInput struct {
	Rating           string `json:"rating"`
	FeedbackCategory string `json:"feedback_category,omitempty"`
	CorrectionNotes  string `json:"correction_notes,omitempty"`
	ExpectedReply    string `json:"expected_reply,omitempty"`
}

type ListFilter struct {
	BranchID   string
	Rating     string
	IsReviewed *bool
	Search     string
	Limit      int
}

type ChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type TrainingDatasetItem struct {
	Messages []ChatMessage  `json:"messages"`
	Metadata map[string]any `json:"metadata,omitempty"`
}
