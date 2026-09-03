package order

import (
	"errors"
	"time"

	"pesenhub/backend/internal/catalog"
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

type ValidationError struct{ Field string }

func (e *ValidationError) Error() string { return e.Field + ": " + ErrInvalidInput.Error() }
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
