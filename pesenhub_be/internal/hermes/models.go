package hermes

import (
	"encoding/json"
	"time"
)

// AgentRun status constants.
const (
	StatusSuccess           = "SUCCESS"
	StatusAmbiguous         = "AMBIGUOUS"
	StatusFailed            = "FAILED"
	StatusRejectedInjection = "REJECTED_INJECTION"
)

// Prompt and Model constants.
const (
	DefaultPromptVersion = "v1.0.0"
	DefaultModelName     = "hermes-3-llama-3.1-8b"
)

// ExtractionRequest carries the input data to extract an order draft candidate.
type ExtractionRequest struct {
	InboundMessageID *string `json:"inbound_message_id,omitempty"`
	MessageText      string  `json:"message_text"`
	SenderPhone      string  `json:"sender_phone"`
	CorrelationID    string  `json:"correlation_id"`
	Session          string  `json:"session"`
}

// RawExtractedItem is the JSON structure parsed directly from the LLM output.
type RawExtractedItem struct {
	MenuName   string   `json:"menu_name"`
	Quantity   int      `json:"quantity"`
	Modifiers  []string `json:"modifiers,omitempty"`
	Notes      string   `json:"notes,omitempty"`
	Confidence float64  `json:"confidence"`
}

// RawExtractedOrder is the JSON response schema produced by the LLM.
type RawExtractedOrder struct {
	Items           []RawExtractedItem `json:"items"`
	Notes           string             `json:"notes,omitempty"`
	FulfillmentType string             `json:"fulfillment_type,omitempty"`
	PaymentMethod   string             `json:"payment_method,omitempty"`
	Confidence      float64            `json:"confidence"`
}

// SelectedModifier represents a validated modifier option matched against the catalog.
type SelectedModifier struct {
	GroupID          string `json:"group_id"`
	GroupName        string `json:"group_name"`
	OptionID         string `json:"option_id"`
	OptionCode       string `json:"option_code"`
	OptionName       string `json:"option_name"`
	PriceDeltaAmount int64  `json:"price_delta_amount"`
}

// ExtractedItem is a catalog-resolved order item with exact catalog pricing.
type ExtractedItem struct {
	MenuID               string             `json:"menu_id"`
	SKU                  string             `json:"sku"`
	Name                 string             `json:"name"`
	Quantity             int                `json:"quantity"`
	UnitPriceAmount      int64              `json:"unit_price_amount"`
	ModifiersTotalAmount int64              `json:"modifiers_total_amount"`
	LineTotalAmount      int64              `json:"line_total_amount"`
	SelectedModifiers    []SelectedModifier `json:"selected_modifiers"`
	Notes                string             `json:"notes,omitempty"`
	Confidence           float64            `json:"confidence"`
}

// DraftCandidate is the verified candidate draft produced by the Hermes extraction pipeline.
type DraftCandidate struct {
	CustomerPhone     string          `json:"customer_phone"`
	Items             []ExtractedItem `json:"items"`
	SubtotalAmount    int64           `json:"subtotal_amount"`
	TotalAmount       int64           `json:"total_amount"`
	Notes             string          `json:"notes,omitempty"`
	FulfillmentType   string          `json:"fulfillment_type,omitempty"`
	PaymentMethod     string          `json:"payment_method,omitempty"`
	OverallConfidence float64         `json:"overall_confidence"`
	IsAmbiguous       bool            `json:"is_ambiguous"`
	AmbiguityReasons  []string        `json:"ambiguity_reasons,omitempty"`
}

// ToolCallAudit records an individual tool invocation during extraction for audit.
type ToolCallAudit struct {
	ToolName       string         `json:"tool_name"`
	InputRedacted  map[string]any `json:"input_redacted"`
	OutputRedacted map[string]any `json:"output_redacted"`
	DurationMs     int            `json:"duration_ms"`
	Error          string         `json:"error,omitempty"`
}

// AgentRun represents an audit record stored in the agent_runs table.
type AgentRun struct {
	ID               string          `json:"id"`
	InboundMessageID *string         `json:"inbound_message_id,omitempty"`
	Session          string          `json:"session"`
	CustomerPhone    string          `json:"customer_phone,omitempty"`
	Model            string          `json:"model"`
	PromptVersion    string          `json:"prompt_version"`
	ConfidenceScore  float64         `json:"confidence_score"`
	IsAmbiguous      bool            `json:"is_ambiguous"`
	AmbiguityReasons []string        `json:"ambiguity_reasons,omitempty"`
	ExtractedDraft   json.RawMessage `json:"extracted_draft"`
	ToolCalls        json.RawMessage `json:"tool_calls"`
	DurationMs       int             `json:"duration_ms"`
	Status           string          `json:"status"`
	ErrorMessage     *string         `json:"error_message,omitempty"`
	CorrelationID    string          `json:"correlation_id"`
	CreatedAt        time.Time       `json:"created_at"`
}
