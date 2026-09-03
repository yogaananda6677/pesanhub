package order

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/httpapi"
)

var (
	ErrInvalidInput        = errors.New("invalid order input")
	ErrMalformedInput      = errors.New("malformed order request")
	ErrIdempotencyConflict = errors.New("idempotency key was already used with a different request")
	ErrInvalidTransition   = errors.New("order status transition is not allowed")
	ErrVersionConflict     = errors.New("order version conflict")
	ErrNotFound            = errors.New("order not found")
)

type ItemInput struct {
	MenuID     string              `json:"menu_id"`
	Quantity   int                 `json:"quantity"`
	Notes      string              `json:"notes,omitempty"`
	Selections []catalog.Selection `json:"modifier_groups,omitempty"`
}

type CreateInput struct {
	ClientOrderID string      `json:"client_order_id"`
	CustomerID    string      `json:"customer_id,omitempty"`
	CustomerName  string      `json:"customer_name"`
	CustomerPhone string      `json:"customer_phone,omitempty"`
	Notes         string      `json:"notes,omitempty"`
	Items         []ItemInput `json:"items"`
}

type Item struct {
	ID              string `json:"id"`
	MenuID          string `json:"menu_id"`
	Name            string `json:"name"`
	SKU             string `json:"sku"`
	UnitPriceAmount int64  `json:"unit_price_amount"`
	Quantity        int    `json:"quantity"`
	LineTotalAmount int64  `json:"line_total_amount"`
}

type Order struct {
	ID            string    `json:"id"`
	OrderNumber   string    `json:"order_number"`
	ClientOrderID string    `json:"client_order_id"`
	Source        string    `json:"source"`
	Status        string    `json:"status"`
	TotalAmount   int64     `json:"total_amount"`
	Version       int64     `json:"version"`
	CreatedAt     time.Time `json:"created_at"`
	Items         []Item    `json:"items"`
}

type ValidationError struct {
	Field  string
	Reason string
}

func (e *ValidationError) Error() string {
	if e.Reason != "" {
		return e.Field + ": " + e.Reason
	}
	return e.Field + ": " + ErrInvalidInput.Error()
}
func (e *ValidationError) Unwrap() error { return ErrInvalidInput }

type TransitionInput struct {
	TargetStatus    string `json:"target_status"`
	ExpectedVersion int64  `json:"expected_version"`
	ReasonCode      string `json:"reason_code,omitempty"`
}

type StatusResult struct {
	ID      string `json:"id"`
	Status  string `json:"status"`
	Version int64  `json:"version"`
}

type OrderFilter struct {
	Sources     []string
	Statuses    []string
	CreatedFrom *time.Time
	CreatedTo   *time.Time
	Pagination  httpapi.Pagination
}

type ModifierSnapshot struct {
	ID               string `json:"id"`
	Name             string `json:"name"`
	PriceDeltaAmount int64  `json:"price_delta_amount"`
}

type OrderItemDetail struct {
	ID              string             `json:"id"`
	MenuID          string             `json:"menu_id"`
	Name            string             `json:"name"`
	SKU             string             `json:"sku"`
	CategoryName    string             `json:"category_name,omitempty"`
	Quantity        int                `json:"quantity"`
	UnitPriceAmount int64              `json:"unit_price_amount"`
	LineTotalAmount int64              `json:"line_total_amount"`
	Notes           string             `json:"notes,omitempty"`
	Modifiers       []ModifierSnapshot `json:"modifiers,omitempty"`
}

type OrderStatusHistoryEntry struct {
	FromStatus string    `json:"from_status,omitempty"`
	ToStatus   string    `json:"to_status"`
	Version    int64     `json:"order_version"`
	ActorType  string    `json:"actor_type"`
	ActorID    string    `json:"actor_id,omitempty"`
	ReasonCode string    `json:"reason_code,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}

type OrderDetail struct {
	ID            string                    `json:"id"`
	OrderNumber   string                    `json:"order_number"`
	ClientOrderID string                    `json:"client_order_id,omitempty"`
	CustomerID    string                    `json:"customer_id,omitempty"`
	Source        string                    `json:"source"`
	Status        string                    `json:"status"`
	CustomerName  string                    `json:"customer_name"`
	CustomerPhone *string                   `json:"customer_phone,omitempty"`
	Notes         string                    `json:"notes,omitempty"`
	TotalAmount   int64                     `json:"total_amount"`
	Version       int64                     `json:"version"`
	CreatedAt     time.Time                 `json:"created_at"`
	UpdatedAt     time.Time                 `json:"updated_at"`
	Items         []OrderItemDetail         `json:"items"`
	History       []OrderStatusHistoryEntry `json:"history,omitempty"`
}

func (o *OrderDetail) RedactForRole(role string) {
	if role == "KDS" {
		o.CustomerPhone = nil
		o.CustomerID = ""
	}
}

type OrderCollection struct {
	Data []OrderDetail    `json:"data"`
	Page httpapi.PageMeta `json:"page"`
}

func EncodeCursor(t time.Time, id string) string {
	raw := fmt.Sprintf("%s,%s", t.UTC().Format(time.RFC3339Nano), id)
	return base64.RawURLEncoding.EncodeToString([]byte(raw))
}

func DecodeCursor(cursor string) (time.Time, string, error) {
	if cursor == "" {
		return time.Time{}, "", nil
	}
	b, err := base64.RawURLEncoding.DecodeString(cursor)
	if err != nil {
		return time.Time{}, "", ErrInvalidInput
	}
	parts := strings.SplitN(string(b), ",", 2)
	if len(parts) != 2 {
		return time.Time{}, "", ErrInvalidInput
	}
	t, err := time.Parse(time.RFC3339Nano, parts[0])
	if err != nil {
		return time.Time{}, "", ErrInvalidInput
	}
	if err := validateUUID(parts[1]); err != nil {
		return time.Time{}, "", ErrInvalidInput
	}
	return t, parts[1], nil
}

type PublicOrderCreateInput struct {
	CustomerName  string      `json:"customer_name"`
	CustomerPhone string      `json:"customer_phone"`
	Notes         string      `json:"notes"`
	Items         []ItemInput `json:"items"`
}

type PublicOrderResponse struct {
	OrderNumber         string    `json:"order_number"`
	PublicTrackingToken string    `json:"public_tracking_token"`
	Status              string    `json:"status"`
	TotalAmount         int64     `json:"total_amount"`
	CreatedAt           time.Time `json:"created_at"`
}

type PreviewInput struct {
	Items []ItemInput `json:"items"`
}

type PreviewItem struct {
	MenuID          string             `json:"menu_id"`
	Name            string             `json:"name"`
	Quantity        int                `json:"quantity"`
	UnitPriceAmount int64              `json:"unit_price_amount"`
	LineTotalAmount int64              `json:"line_total_amount"`
	Modifiers       []ModifierSnapshot `json:"modifiers"`
}

type PreviewResponse struct {
	SubtotalAmount int64         `json:"subtotal_amount"`
	TotalAmount    int64         `json:"total_amount"`
	Items          []PreviewItem `json:"items"`
}

type PublicTrackingDetail struct {
	OrderNumber  string            `json:"order_number"`
	Status       string            `json:"status"`
	CustomerName string            `json:"customer_name"`
	TotalAmount  int64             `json:"total_amount"`
	CreatedAt    time.Time         `json:"created_at"`
	UpdatedAt    time.Time         `json:"updated_at"`
	Items        []OrderItemDetail `json:"items"`
}

type AuditLogEntry struct {
	ID            string          `json:"id"`
	AggregateType string          `json:"aggregate_type"`
	AggregateID   string          `json:"aggregate_id"`
	Action        string          `json:"action"`
	ActorType     string          `json:"actor_type"`
	ActorID       string          `json:"actor_id,omitempty"`
	RequestID     string          `json:"request_id"`
	Metadata      json.RawMessage `json:"metadata"`
	CreatedAt     time.Time       `json:"created_at"`
}
