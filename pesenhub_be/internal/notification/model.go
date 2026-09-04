package notification

import (
	"context"
	"errors"
	"regexp"
	"strings"
	"time"

	"pesenhub/backend/internal/waha"
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
	StatusProcessing NotificationStatus = "PROCESSING"
	StatusSent       NotificationStatus = "SENT"
	StatusFailed     NotificationStatus = "FAILED"
	StatusSuppressed NotificationStatus = "SUPPRESSED"
	StatusDeadLetter NotificationStatus = "DEAD_LETTER"
)

// ErrorCategory defines the classification of notification dispatch failures.
type ErrorCategory string

const (
	CategoryTransientTimeout    ErrorCategory = "TRANSIENT_TIMEOUT"
	CategoryTransientNetwork    ErrorCategory = "TRANSIENT_NETWORK"
	CategoryTransientProvider   ErrorCategory = "TRANSIENT_PROVIDER"
	CategorySessionNotReady     ErrorCategory = "SESSION_NOT_READY"
	CategoryPermanentValidation ErrorCategory = "PERMANENT_VALIDATION"
	CategoryPermanentAuth       ErrorCategory = "PERMANENT_AUTH"
	CategoryMaxAttemptsExceeded ErrorCategory = "MAX_ATTEMPTS_EXCEEDED"
	CategoryUnknown             ErrorCategory = "UNKNOWN"
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
	MaxAttempts       int                `json:"max_attempts"`
	NextRetryAt       *time.Time         `json:"next_retry_at,omitempty"`
	ErrorCategory     *ErrorCategory     `json:"error_category,omitempty"`
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
	Attempts          int                `json:"attempts,omitempty"`
	NextRetryAt       *time.Time         `json:"next_retry_at,omitempty"`
	ErrorCategory     *ErrorCategory     `json:"error_category,omitempty"`
	IsDuplicate       bool               `json:"is_duplicate"`
	Error             error              `json:"-"`
}

var (
	phoneRegex  = regexp.MustCompile(`(?:\+?62|08)[0-9]{8,13}`)
	secretRegex = regexp.MustCompile(`(?i)(api[-_]?key|authorization|bearer|token|secret|password)[=:\s]+[^\s,]+`)
)

// CalculateBackoff computes exponential backoff delay based on attempt number.
// Formula: baseDelay * 2^(attempt-1), capped by maxDelay.
func CalculateBackoff(attempt int, baseDelay, maxDelay time.Duration) time.Duration {
	if baseDelay <= 0 {
		baseDelay = 1 * time.Second
	}
	if maxDelay <= 0 {
		maxDelay = 60 * time.Second
	}
	if attempt < 1 {
		attempt = 1
	}
	shift := attempt - 1
	if shift > 30 {
		return maxDelay
	}
	multiplier := int64(1) << shift
	delay := baseDelay * time.Duration(multiplier)
	if delay > maxDelay || delay <= 0 {
		return maxDelay
	}
	return delay
}

// ClassifyError categorizes an error into safe taxonomy and reports whether it is retryable.
func ClassifyError(err error) (ErrorCategory, bool) {
	if err == nil {
		return "", false
	}
	if errors.Is(err, waha.ErrValidation) || errors.Is(err, ErrInvalidRecipient) {
		return CategoryPermanentValidation, false
	}
	if errors.Is(err, waha.ErrAuthentication) {
		return CategoryPermanentAuth, false
	}
	if errors.Is(err, waha.ErrTimeout) || errors.Is(err, context.DeadlineExceeded) {
		return CategoryTransientTimeout, true
	}
	if errors.Is(err, waha.ErrSessionNotReady) {
		return CategorySessionNotReady, true
	}
	if errors.Is(err, waha.ErrSessionAbsent) {
		return CategorySessionNotReady, true
	}
	if errors.Is(err, waha.ErrProvider) {
		return CategoryTransientProvider, true
	}

	errMsg := strings.ToLower(err.Error())
	if strings.Contains(errMsg, "timeout") || strings.Contains(errMsg, "deadline exceeded") {
		return CategoryTransientTimeout, true
	}
	if strings.Contains(errMsg, "connection refused") || strings.Contains(errMsg, "no such host") ||
		strings.Contains(errMsg, "network") || strings.Contains(errMsg, "reset by peer") ||
		strings.Contains(errMsg, "broken pipe") {
		return CategoryTransientNetwork, true
	}
	if strings.Contains(errMsg, "validation") || strings.Contains(errMsg, "invalid") ||
		strings.Contains(errMsg, "status 400") || strings.Contains(errMsg, "status 422") {
		return CategoryPermanentValidation, false
	}
	if strings.Contains(errMsg, "auth") || strings.Contains(errMsg, "status 401") ||
		strings.Contains(errMsg, "status 403") {
		return CategoryPermanentAuth, false
	}
	return CategoryUnknown, true
}

// SanitizeError scrubs sensitive credentials, authorization headers, and raw phone numbers from error text.
func SanitizeError(err error) string {
	if err == nil {
		return ""
	}
	text := err.Error()
	text = secretRegex.ReplaceAllString(text, "$1=[REDACTED]")
	text = phoneRegex.ReplaceAllStringFunc(text, func(match string) string {
		return waha.MaskPhone(match)
	})
	text = strings.TrimSpace(text)
	if len(text) > 255 {
		text = text[:252] + "..."
	}
	return text
}
