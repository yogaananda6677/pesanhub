package waha

import (
	"crypto/hmac"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"regexp"
	"strconv"
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

type WebhookHandler struct {
	secret   []byte
	logger   *slog.Logger
	now      func() time.Time
	maxSkew  time.Duration
	replays  *replayGuard
	counters webhookCounters
}

func NewWebhookHandler(secret string, logger *slog.Logger) *WebhookHandler {
	return &WebhookHandler{
		secret:  []byte(secret),
		logger:  logger,
		now:     time.Now,
		maxSkew: 5 * time.Minute,
		replays: newReplayGuard(10*time.Minute, 10_000),
	}
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
	requestID := r.Header.Get("X-Webhook-Request-Id")
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxWebhookBody))
	if err != nil {
		status := http.StatusBadRequest
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			status = http.StatusRequestEntityTooLarge
		}
		h.rejectValidation(w, status, "invalid_body", requestID, started)
		return
	}
	timestamp := r.Header.Get("X-Webhook-Timestamp")
	algorithm := r.Header.Get("X-Webhook-Hmac-Algorithm")
	signature := r.Header.Get("X-Webhook-Hmac")
	if !validWebhookRequestID.MatchString(requestID) || timestamp == "" {
		h.rejectValidation(w, http.StatusBadRequest, "invalid_headers", requestID, started)
		return
	}
	if !strings.EqualFold(algorithm, "sha512") || !h.validSignature(body, signature) {
		h.rejectAuthentication(w, "authentication_failed", requestID, started)
		return
	}
	millis, err := strconv.ParseInt(timestamp, 10, 64)
	if err != nil {
		h.rejectValidation(w, http.StatusBadRequest, "invalid_timestamp", requestID, started)
		return
	}
	now := h.now()
	age := now.Sub(time.UnixMilli(millis))
	if age < -h.maxSkew || age > h.maxSkew {
		h.rejectAuthentication(w, "stale_timestamp", requestID, started)
		return
	}
	var envelope struct {
		Event   string `json:"event"`
		Session string `json:"session"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil || envelope.Event == "" || envelope.Session == "" {
		h.rejectValidation(w, http.StatusBadRequest, "invalid_payload", requestID, started)
		return
	}
	if h.replays.Seen(requestID, now) {
		h.counters.duplicate.Add(1)
		h.counters.retry.Add(1)
		h.observe("duplicate", requestID, started)
		w.Header().Set("X-PesenHub-Deduplicated", "true")
		w.WriteHeader(http.StatusNoContent)
		return
	}
	h.counters.accepted.Add(1)
	h.observe("accepted", requestID, started)
	w.WriteHeader(http.StatusNoContent)
}

func (h *WebhookHandler) validSignature(body []byte, value string) bool {
	provided, err := hex.DecodeString(value)
	if err != nil || len(provided) != sha512.Size {
		return false
	}
	mac := hmac.New(sha512.New, h.secret)
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
		h.logger.Info("WAHA webhook verified", attributes...)
	}
}
