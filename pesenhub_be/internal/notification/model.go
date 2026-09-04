package notification

import (
	"errors"
	"time"
)

// NotificationType defines the type of notification sent to the customer.
type NotificationType string

const (
	TypeConfirmation NotificationType = "CONFIRMATION"
	TypeAccepted     NotificationType = "ACCEPTED"
	TypeCompleted    NotificationType = "COMPLETED"
)

// NotificationStatus defines the delivery status of a notification record.
type NotificationStatus string

const (
	StatusPending    NotificationStatus = "PENDING"
	StatusSent       NotificationStatus = "SENT"
	StatusFailed     NotificationStatus = "FAILED"
	StatusSuppressed NotificationStatus = "SUPPRESSED"
)

// SuppressReason explains why an automated notification was suppressed.
type SuppressReason string

const (
	SuppressCustomerOptedOut   SuppressReason = "CUSTOMER_OPTED_OUT"
	SuppressConversationPaused SuppressReason = "CONVERSATION_PAUSED"
	SuppressHandoffActive      SuppressReason = "HANDOFF_ACTIVE"
)

var (
	ErrDuplicateNotification = errors.New("duplicate_notification")
	ErrSuppressed            = errors.New("notification_suppressed")
	ErrInvalidRecipient      = errors.New("invalid_recipient")
)

// NotificationRecord represents a row in order_notifications.
type NotificationRecord struct {
	ID                string             `json:"id"`
	OrderID           string             `json:"order_id"`
	CustomerPhone     string             `json:"customer_phone"`
	NotificationType  NotificationType   `json:"notification_type"`
	TemplateVersion   string             `json:"template_version"`
	IdempotencyKey    string             `json:"idempotency_key"`
	MessageText       string             `json:"message_text"`
	Status            NotificationStatus `json:"status"`
	SuppressReason    *string            `json:"suppress_reason,omitempty"`
	ProviderMessageID *string            `json:"provider_message_id,omitempty"`
	Attempts          int                `json:"attempts"`
	LastError         *string            `json:"last_error,omitempty"`
	SentAt            *time.Time         `json:"sent_at,omitempty"`
	CreatedAt         time.Time          `json:"created_at"`
	UpdatedAt         time.Time          `json:"updated_at"`
}

// OrderItemSummary contains simplified line item details for notifications.
type OrderItemSummary struct {
	Name      string   `json:"name"`
	Quantity  int      `json:"quantity"`
	UnitPrice int64    `json:"unit_price"`
	LineTotal int64    `json:"line_total"`
	Modifiers []string `json:"modifiers,omitempty"`
	Notes     string   `json:"notes,omitempty"`
}

// OrderNotificationData provides all data needed to render templates and dispatch.
type OrderNotificationData struct {
	OrderID         string             `json:"order_id"`
	OrderNumber     string             `json:"order_number"`
	CustomerName    string             `json:"customer_name"`
	CustomerPhone   string             `json:"customer_phone"`
	TotalAmount     int64              `json:"total_amount"`
	TrackingToken   string             `json:"tracking_token"`
	TrackingBaseURL string             `json:"tracking_base_url"`
	Items           []OrderItemSummary `json:"items"`
}

// NotificationResult provides structured output from notification dispatch.
type NotificationResult struct {
	RecordID          string             `json:"record_id"`
	OrderID           string             `json:"order_id"`
	NotificationType  NotificationType   `json:"notification_type"`
	Status            NotificationStatus `json:"status"`
	SuppressReason    string             `json:"suppress_reason,omitempty"`
	ProviderMessageID string             `json:"provider_message_id,omitempty"`
	IsDuplicate       bool               `json:"is_duplicate"`
	Error             error              `json:"-"`
}
