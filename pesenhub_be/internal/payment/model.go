package payment

import (
	"errors"
	"time"
)

var (
	ErrInvalidInput        = errors.New("invalid payment input")
	ErrMalformedInput      = errors.New("malformed payment request")
	ErrOrderNotFound       = errors.New("order not found")
	ErrAmountMismatch      = errors.New("payment amount does not match order total")
	ErrOrderNotPayable     = errors.New("order cannot be paid")
	ErrIdempotencyConflict = errors.New("idempotency key was already used with a different request")
	ErrMidtransUnavailable = errors.New("midtrans is temporarily unavailable")
	ErrMidtransRejected    = errors.New("midtrans rejected the transaction")
	ErrMidtransNotReady    = errors.New("midtrans payment creation is not configured")
)

type CashInput struct {
	Amount int64 `json:"amount"`
}

type Payment struct {
	ID                string     `json:"id"`
	OrderID           string     `json:"order_id"`
	Method            string     `json:"method"`
	Status            string     `json:"status"`
	Amount            int64      `json:"amount"`
	Version           int64      `json:"version"`
	PaidAt            *time.Time `json:"paid_at,omitempty"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at"`
	ProviderOrderID   string     `json:"provider_order_id,omitempty"`
	ProviderReference string     `json:"provider_reference,omitempty"`
	QRCodeURL         string     `json:"qr_code_url,omitempty"`
	ExpiresAt         *time.Time `json:"expires_at,omitempty"`
}

type QRISCharge struct {
	ProviderOrderID   string
	ProviderReference string
	Status            string
	QRCodeURL         string
	ExpiresAt         *time.Time
}

type ProviderError struct {
	Kind string
}

func (e *ProviderError) Error() string { return "midtrans request failed: " + e.Kind }

type ValidationError struct{ Field, Reason string }

func (e *ValidationError) Error() string { return e.Field + ": " + e.Reason }
func (e *ValidationError) Unwrap() error { return ErrInvalidInput }
