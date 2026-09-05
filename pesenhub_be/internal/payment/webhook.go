package payment

import (
	"context"
	"crypto/sha512"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"sync/atomic"
	"time"

	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

const maxMidtransWebhookBody = 1 << 20

type MidtransWebhookStore interface {
	ApplyMidtransWebhook(context.Context, MidtransNotification, string, string, *time.Time) (WebhookResult, error)
}

type MidtransWebhookMetrics struct {
	Accepted, Applied, Duplicate, Ignored, ValidationFailed, AuthenticationFailed, StoreFailed uint64
	TotalLatencyMilliseconds                                                                   uint64
}

type midtransWebhookCounters struct {
	accepted, applied, duplicate, ignored, validationFailed, authenticationFailed, storeFailed atomic.Uint64
	totalLatencyMilliseconds                                                                   atomic.Uint64
}

type MidtransWebhookHandler struct {
	serverKey, merchantID string
	store                 MidtransWebhookStore
	logger                *slog.Logger
	now                   func() time.Time
	counters              midtransWebhookCounters
}

func NewMidtransWebhookHandler(serverKey, merchantID string, store MidtransWebhookStore, logger *slog.Logger) *MidtransWebhookHandler {
	return &MidtransWebhookHandler{serverKey: serverKey, merchantID: merchantID, store: store, logger: logger, now: time.Now}
}

func (h *MidtransWebhookHandler) Metrics() MidtransWebhookMetrics {
	return MidtransWebhookMetrics{
		Accepted: h.counters.accepted.Load(), Applied: h.counters.applied.Load(), Duplicate: h.counters.duplicate.Load(), Ignored: h.counters.ignored.Load(),
		ValidationFailed: h.counters.validationFailed.Load(), AuthenticationFailed: h.counters.authenticationFailed.Load(), StoreFailed: h.counters.storeFailed.Load(),
		TotalLatencyMilliseconds: h.counters.totalLatencyMilliseconds.Load(),
	}
}

func (h *MidtransWebhookHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	started := h.now()
	requestID := httpserver.RequestID(r.Context())
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxMidtransWebhookBody))
	if err != nil {
		status := http.StatusBadRequest
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			status = http.StatusRequestEntityTooLarge
		}
		h.reject(w, status, "INVALID_WEBHOOK", requestID, "invalid_body", started, false)
		return
	}
	var notification MidtransNotification
	if json.Unmarshal(body, &notification) != nil || !requiredNotificationFields(notification) {
		h.reject(w, http.StatusBadRequest, "INVALID_WEBHOOK", requestID, "invalid_payload", started, false)
		return
	}
	if !validMidtransSignature(notification, h.serverKey) {
		h.reject(w, http.StatusUnauthorized, "INVALID_WEBHOOK_SIGNATURE", requestID, "authentication_failed", started, true)
		return
	}
	if notification.MerchantID != h.merchantID || notification.PaymentType != "qris" || notification.Currency != "IDR" {
		h.reject(w, http.StatusBadRequest, "INVALID_WEBHOOK", requestID, "invalid_merchant_or_channel", started, false)
		return
	}
	if _, err := mapMidtransStatus(notification); err != nil {
		h.reject(w, http.StatusBadRequest, "INVALID_WEBHOOK", requestID, "invalid_status", started, false)
		return
	}
	eventID := midtransEventID(notification)
	occurredAt, err := midtransOccurredAt(notification)
	if err != nil {
		h.reject(w, http.StatusBadRequest, "INVALID_WEBHOOK", requestID, "invalid_timestamp", started, false)
		return
	}
	result, err := h.store.ApplyMidtransWebhook(r.Context(), notification, eventID, requestID, occurredAt)
	if err != nil {
		switch {
		case errors.Is(err, ErrPaymentNotFound):
			h.reject(w, http.StatusNotFound, "PAYMENT_NOT_FOUND", requestID, "payment_not_found", started, false)
		case errors.Is(err, ErrWebhookAmount), errors.Is(err, ErrWebhookReference):
			h.reject(w, http.StatusUnprocessableEntity, "WEBHOOK_MISMATCH", requestID, "payment_mismatch", started, false)
		default:
			h.counters.storeFailed.Add(1)
			h.observe("store_failed", requestID, started, slog.LevelError)
			httpapi.WriteError(w, http.StatusServiceUnavailable, "WEBHOOK_PROCESSING_UNAVAILABLE", "Webhook processing is temporarily unavailable.", requestID, nil)
		}
		return
	}
	h.counters.accepted.Add(1)
	if result.Duplicate {
		h.counters.duplicate.Add(1)
		w.Header().Set("X-PesenHub-Deduplicated", "true")
	} else if result.Applied {
		h.counters.applied.Add(1)
	} else {
		h.counters.ignored.Add(1)
	}
	h.observe("accepted", requestID, started, slog.LevelInfo)
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"status": "ok", "payment_id": result.Payment.ID, "payment_status": result.Payment.Status, "applied": result.Applied})
}

func requiredNotificationFields(n MidtransNotification) bool {
	return n.OrderID != "" && n.TransactionID != "" && n.TransactionStatus != "" && n.StatusCode != "" && n.GrossAmount != "" && n.PaymentType != "" && n.MerchantID != "" && n.Currency != "" && n.SignatureKey != ""
}

func validMidtransSignature(n MidtransNotification, serverKey string) bool {
	provided, err := hex.DecodeString(strings.TrimSpace(n.SignatureKey))
	if err != nil || len(provided) != sha512.Size {
		return false
	}
	expected := sha512.Sum512([]byte(n.OrderID + n.StatusCode + n.GrossAmount + serverKey))
	return subtle.ConstantTimeCompare(provided, expected[:]) == 1
}

func mapMidtransStatus(n MidtransNotification) (string, error) {
	status, fraud := strings.ToLower(n.TransactionStatus), strings.ToLower(n.FraudStatus)
	switch status {
	case "capture", "settlement":
		if n.StatusCode != "200" {
			return "", ErrWebhookInvalid
		}
		if fraud == "deny" {
			return "FAILED", nil
		}
		if fraud != "" && fraud != "accept" {
			return "PENDING_PAYMENT", nil
		}
		return "PAID", nil
	case "pending", "authorize":
		return "PENDING_PAYMENT", nil
	case "deny", "cancel", "failure":
		return "FAILED", nil
	case "expire":
		return "EXPIRED", nil
	case "refund", "partial_refund":
		return "REFUNDED", nil
	default:
		return "", ErrWebhookInvalid
	}
}

func midtransEventID(n MidtransNotification) string {
	sum := sha512.Sum512_256([]byte(strings.Join([]string{n.TransactionID, n.TransactionStatus, n.StatusCode, n.GrossAmount, n.FraudStatus}, "\x00")))
	return "notification:" + hex.EncodeToString(sum[:])
}

func midtransOccurredAt(n MidtransNotification) (*time.Time, error) {
	value := n.TransactionTime
	if n.SettlementTime != "" {
		value = n.SettlementTime
	}
	if value == "" {
		return nil, nil
	}
	parsed, err := time.ParseInLocation("2006-01-02 15:04:05", value, time.FixedZone("WIB", 7*60*60))
	if err != nil {
		return nil, err
	}
	parsed = parsed.UTC()
	return &parsed, nil
}

func (h *MidtransWebhookHandler) reject(w http.ResponseWriter, status int, code, requestID, outcome string, started time.Time, authentication bool) {
	if authentication {
		h.counters.authenticationFailed.Add(1)
	} else {
		h.counters.validationFailed.Add(1)
	}
	h.observe(outcome, requestID, started, slog.LevelWarn)
	httpapi.WriteError(w, status, code, "Webhook request rejected.", requestID, nil)
}

func (h *MidtransWebhookHandler) observe(outcome, requestID string, started time.Time, level slog.Level) {
	duration := h.now().Sub(started).Milliseconds()
	if duration < 0 {
		duration = 0
	}
	h.counters.totalLatencyMilliseconds.Add(uint64(duration))
	if h.logger != nil {
		h.logger.Log(context.Background(), level, "Midtrans webhook processed", "outcome", outcome, "request_id", requestID, "duration_ms", duration)
	}
}
