package gowa

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const maxWebhookBody = 1 << 20

var validWebhookRequestID = regexp.MustCompile(`^[A-Za-z0-9._:-]{1,128}$`)

type WebhookMetrics struct {
	Accepted                 uint64
	ValidationFailed         uint64
	AuthenticationFailed     uint64
	Duplicate                uint64
	Retry                    uint64
	TotalLatencyMilliseconds uint64
}

type webhookCounters struct {
	accepted, validationFailed, authenticationFailed atomic.Uint64
	duplicate, retry, totalLatencyMilliseconds       atomic.Uint64
}

type replayGuard struct {
	mu      sync.Mutex
	expires map[string]time.Time
	ttl     time.Duration
	limit   int
}

func newReplayGuard(ttl time.Duration, limit int) *replayGuard {
	return &replayGuard{expires: make(map[string]time.Time), ttl: ttl, limit: limit}
}

// Seen atomically records an authenticated request ID and reports a replay.
func (g *replayGuard) Seen(id string, now time.Time) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	for key, expiry := range g.expires {
		if !expiry.After(now) {
			delete(g.expires, key)
		}
	}
	if expiry, ok := g.expires[id]; ok && expiry.After(now) {
		return true
	}
	if len(g.expires) >= g.limit {
		var oldestKey string
		var oldest time.Time
		for key, expiry := range g.expires {
			if oldestKey == "" || expiry.Before(oldest) {
				oldestKey, oldest = key, expiry
			}
		}
		delete(g.expires, oldestKey)
	}
	g.expires[id] = now.Add(g.ttl)
	return false
}

type WebhookOption func(*WebhookHandler)

func WithStore(store InboundStore) WebhookOption {
	return func(h *WebhookHandler) {
		h.store = store
	}
}

func WithOnMessage(fn func(context.Context, *InboundMessage)) WebhookOption {
	return func(h *WebhookHandler) {
		h.onMessage = fn
	}
}

type WebhookHandler struct {
	secret    []byte
	logger    *slog.Logger
	now       func() time.Time
	replays   *replayGuard
	counters  webhookCounters
	store     InboundStore
	onMessage func(context.Context, *InboundMessage)
}

func NewWebhookHandler(secret string, logger *slog.Logger, opts ...WebhookOption) *WebhookHandler {
	h := &WebhookHandler{
		secret:  []byte(secret),
		logger:  logger,
		now:     time.Now,
		replays: newReplayGuard(10*time.Minute, 10_000),
	}
	for _, opt := range opts {
		opt(h)
	}
	return h
}

func (h *WebhookHandler) Metrics() WebhookMetrics {
	return WebhookMetrics{
		Accepted:                 h.counters.accepted.Load(),
		ValidationFailed:         h.counters.validationFailed.Load(),
		AuthenticationFailed:     h.counters.authenticationFailed.Load(),
		Duplicate:                h.counters.duplicate.Load(),
		Retry:                    h.counters.retry.Load(),
		TotalLatencyMilliseconds: h.counters.totalLatencyMilliseconds.Load(),
	}
}

func (h *WebhookHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	started := h.now()
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxWebhookBody))
	requestID := r.Header.Get("X-Request-ID")
	if !validWebhookRequestID.MatchString(requestID) {
		sum := sha256.Sum256(body)
		requestID = "gowa-" + hex.EncodeToString(sum[:8])
	}
	if err != nil {
		status := http.StatusBadRequest
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			status = http.StatusRequestEntityTooLarge
		}
		h.rejectValidation(w, status, "invalid_body", requestID, started)
		return
	}
	signature := r.Header.Get("X-Hub-Signature-256")
	if !h.validSignature(body, signature) {
		h.rejectAuthentication(w, "authentication_failed", requestID, started)
		return
	}
	now := h.now()
	var envelope struct {
		Event    string `json:"event"`
		DeviceID string `json:"device_id"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil || envelope.Event == "" || envelope.DeviceID == "" {
		h.rejectValidation(w, http.StatusBadRequest, "invalid_payload", requestID, started)
		return
	}

	// Layer 1: In-memory request ID replay guard
	if h.replays.Seen(requestID, now) {
		h.counters.duplicate.Add(1)
		h.counters.retry.Add(1)
		h.observe("duplicate", requestID, started)
		w.Header().Set("X-PesenHub-Deduplicated", "true")
		w.WriteHeader(http.StatusNoContent)
		return
	}

	// Layer 2: Message-level parsing, persistent deduplication and quarantine
	if IsMessageEvent(envelope.Event) {
		msg, isMsg, isFromMe, err := ParseInboundMessage(body, requestID, now)
		if err != nil {
			h.rejectValidation(w, http.StatusBadRequest, "invalid_message_payload", requestID, started)
			return
		}
		if isFromMe {
			h.observe("outgoing_message_ignored", requestID, started)
			h.counters.accepted.Add(1)
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if isMsg && msg != nil && h.store != nil {
			stored, isDuplicate, err := h.store.StoreInbound(r.Context(), msg)
			if err != nil {
				h.rejectInternal(w, "store_error", requestID, started, err)
				return
			}
			if isDuplicate {
				h.counters.duplicate.Add(1)
				h.counters.retry.Add(1)
				h.observe("duplicate_message", requestID, started)
				w.Header().Set("X-PesenHub-Deduplicated", "true")
				w.WriteHeader(http.StatusNoContent)
				return
			}

			if stored.Status == StatusQuarantined {
				h.observe("quarantined", requestID, started)
			} else {
				h.observe("accepted_message", requestID, started)
				if h.onMessage != nil {
					h.onMessage(r.Context(), stored)
				}
			}

			h.counters.accepted.Add(1)
			w.WriteHeader(http.StatusNoContent)
			return
		}
	}

	h.counters.accepted.Add(1)
	h.observe("accepted", requestID, started)
	w.WriteHeader(http.StatusNoContent)
}

func (h *WebhookHandler) validSignature(body []byte, value string) bool {
	value = strings.TrimSpace(value)
	if !strings.HasPrefix(value, "sha256=") {
		return false
	}
	provided, err := hex.DecodeString(strings.TrimPrefix(value, "sha256="))
	if err != nil || len(provided) != sha256.Size {
		return false
	}
	mac := hmac.New(sha256.New, h.secret)
	_, _ = mac.Write(body)
	return hmac.Equal(mac.Sum(nil), provided)
}

func (h *WebhookHandler) rejectValidation(w http.ResponseWriter, status int, reason, requestID string, started time.Time) {
	h.counters.validationFailed.Add(1)
	h.reject(w, status, reason, requestID, started)
}

func (h *WebhookHandler) rejectAuthentication(w http.ResponseWriter, reason, requestID string, started time.Time) {
	h.counters.authenticationFailed.Add(1)
	h.reject(w, http.StatusUnauthorized, reason, requestID, started)
}

func (h *WebhookHandler) rejectInternal(w http.ResponseWriter, reason, requestID string, started time.Time, err error) {
	h.observe(reason, requestID, started)
	if h.logger != nil {
		h.logger.Error("GOWA webhook internal error", "reason", reason, "request_id", requestID, "error", err)
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusInternalServerError)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"error": map[string]string{
			"code":    "INTERNAL_SERVER_ERROR",
			"message": "Internal error occurred while processing webhook.",
		},
	})
}

func (h *WebhookHandler) reject(w http.ResponseWriter, status int, reason, requestID string, started time.Time) {
	h.observe(reason, requestID, started)
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]string{"code": strings.ToUpper(reason), "message": "Webhook request rejected."}})
}

func (h *WebhookHandler) observe(outcome, requestID string, started time.Time) {
	duration := h.now().Sub(started).Milliseconds()
	if duration < 0 {
		duration = 0
	}
	h.counters.totalLatencyMilliseconds.Add(uint64(duration))
	if h.logger != nil {
		attributes := []any{"outcome", outcome, "duration_ms", duration}
		if validWebhookRequestID.MatchString(requestID) {
			attributes = append(attributes, "webhook_request_id", requestID)
		}
		h.logger.Info("GOWA webhook processed", attributes...)
	}
}
