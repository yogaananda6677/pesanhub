package gowa

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

func signedWebhook(t *testing.T, h *WebhookHandler, body, id string, _ time.Time) *http.Request {
	t.Helper()
	mac := hmac.New(sha256.New, h.secret)
	_, _ = mac.Write([]byte(body))
	r := httptest.NewRequest(http.MethodPost, "/webhooks/gowa", strings.NewReader(body))
	r.Header.Set("X-Request-ID", id)
	r.Header.Set("X-Hub-Signature-256", "sha256="+hex.EncodeToString(mac.Sum(nil)))
	return r
}

func TestWebhookAcceptsOfficialGOWAHMACShape(t *testing.T) {
	now := time.UnixMilli(1_800_000_000_000)
	h := NewWebhookHandler("my-secret-key", nil)
	h.now = func() time.Time { return now }
	body := `{"event":"message","device_id":"pesenhub-dev","session_id":"default","payload":{"id":"3EB0TEST","from":"628123456789@s.whatsapp.net","body":"test"}}`
	mac := hmac.New(sha256.New, []byte("my-secret-key"))
	_, _ = mac.Write([]byte(body))
	if len(hex.EncodeToString(mac.Sum(nil))) != sha256.Size*2 {
		t.Fatal("unexpected HMAC-SHA256 size")
	}
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, signedWebhook(t, h, body, "evt-1", now))
	if rr.Code != http.StatusNoContent || h.Metrics().Accepted != 1 {
		t.Fatalf("response=%d metrics=%+v", rr.Code, h.Metrics())
	}
}

func TestWebhookRejectsInvalidProof(t *testing.T) {
	now := time.UnixMilli(1_800_000_000_000)
	h := NewWebhookHandler("my-secret-key", nil)
	h.now = func() time.Time { return now }

	badProof := signedWebhook(t, h, `{}`, "evt-bad", now)
	badProof.Header.Set("X-Hub-Signature-256", strings.Repeat("0", sha256.Size*2))
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, badProof)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("invalid proof response=%d", rr.Code)
	}
	if h.Metrics().AuthenticationFailed != 1 {
		t.Fatalf("metrics=%+v", h.Metrics())
	}
}

func TestWebhookDuplicateIsAcknowledgedWithoutSecondAcceptance(t *testing.T) {
	now := time.UnixMilli(1_800_000_000_000)
	h := NewWebhookHandler("my-secret-key", nil)
	h.now = func() time.Time { return now }
	for range 2 {
		rr := httptest.NewRecorder()
		h.ServeHTTP(rr, signedWebhook(t, h, `{"event":"message","device_id":"pesenhub-dev","session_id":"default"}`, "evt-retry", now))
		if rr.Code != http.StatusNoContent {
			t.Fatalf("response=%d", rr.Code)
		}
		if h.Metrics().Duplicate == 1 && rr.Header().Get("X-PesenHub-Deduplicated") != "true" {
			t.Fatal("duplicate marker missing")
		}
	}
	if got := h.Metrics(); got.Accepted != 1 || got.Duplicate != 1 || got.Retry != 1 {
		t.Fatalf("metrics=%+v", got)
	}
}

func TestWebhookRejectsAuthenticatedInvalidPayload(t *testing.T) {
	now := time.UnixMilli(1_800_000_000_000)
	h := NewWebhookHandler("my-secret-key", nil)
	h.now = func() time.Time { return now }
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, signedWebhook(t, h, `{"event":"message"}`, "evt-invalid", now))
	if rr.Code != http.StatusBadRequest || h.Metrics().ValidationFailed != 1 {
		t.Fatalf("response=%d metrics=%+v", rr.Code, h.Metrics())
	}
}

func TestWebhookReplayGuardIsAtomic(t *testing.T) {
	now := time.UnixMilli(1_800_000_000_000)
	h := NewWebhookHandler("my-secret-key", nil)
	h.now = func() time.Time { return now }
	const requests = 20
	var wg sync.WaitGroup
	for range requests {
		request := signedWebhook(t, h, `{"event":"message","device_id":"pesenhub-dev","session_id":"default"}`, "evt-concurrent", now)
		wg.Add(1)
		go func() {
			defer wg.Done()
			h.ServeHTTP(httptest.NewRecorder(), request)
		}()
	}
	wg.Wait()
	if got := h.Metrics(); got.Accepted != 1 || got.Duplicate != requests-1 || got.Retry != requests-1 {
		t.Fatalf("metrics=%+v", got)
	}
}

func TestWebhookLimitsBodyAndDoesNotLogPayloadOrSecret(t *testing.T) {
	var logs bytes.Buffer
	h := NewWebhookHandler("do-not-log-secret", slog.New(slog.NewJSONHandler(&logs, nil)))
	rr := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/webhooks/gowa", strings.NewReader(strings.Repeat("private-payload", 100_000)))
	h.ServeHTTP(rr, r)
	if rr.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("response=%d", rr.Code)
	}
	if strings.Contains(logs.String(), "private-payload") || strings.Contains(logs.String(), "do-not-log-secret") {
		t.Fatalf("sensitive log: %s", logs.String())
	}
}

type mockInboundStore struct {
	mu       sync.Mutex
	messages map[string]*InboundMessage
	failNext error
}

func newMockInboundStore() *mockInboundStore {
	return &mockInboundStore{messages: make(map[string]*InboundMessage)}
}

func (m *mockInboundStore) StoreInbound(ctx context.Context, msg *InboundMessage) (*InboundMessage, bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.failNext != nil {
		err := m.failNext
		m.failNext = nil
		return nil, false, err
	}

	if existing, ok := m.messages[msg.ProviderMessageID]; ok {
		return existing, true, nil
	}

	m.messages[msg.ProviderMessageID] = msg
	return msg, false, nil
}

func (m *mockInboundStore) GetByProviderMessageID(ctx context.Context, providerID string) (*InboundMessage, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if msg, ok := m.messages[providerID]; ok {
		return msg, nil
	}
	return nil, errors.New("not found")
}

func (m *mockInboundStore) GetByID(ctx context.Context, id string) (*InboundMessage, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, msg := range m.messages {
		if msg.ID == id {
			return msg, nil
		}
	}
	return nil, errors.New("not found")
}

func TestWebhookInboundMessageProcessing(t *testing.T) {
	now := time.UnixMilli(1_800_000_000_000)
	store := newMockInboundStore()
	var processed *InboundMessage

	h := NewWebhookHandler("my-secret-key", nil,
		WithStore(store),
		WithOnMessage(func(ctx context.Context, msg *InboundMessage) {
			processed = msg
		}),
	)
	h.now = func() time.Time { return now }

	body := `{
		"event": "message",
		"device_id": "pesenhub-dev", "session_id": "default",
		"payload": {
			"id": "wamid_123456",
			"timestamp": "2026-09-04T12:00:00Z",
			"from": "628123456789@s.whatsapp.net",
			"is_from_me": false,
			"to": "628999999999@s.whatsapp.net",
			"body": "Pesan nasi goreng spesial",
			"_data": {"notifyName": "Andi"}
		}
	}`

	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, signedWebhook(t, h, body, "req-inbound-1", now))

	if rr.Code != http.StatusNoContent {
		t.Fatalf("expected HTTP 204, got %d", rr.Code)
	}
	if processed == nil {
		t.Fatal("expected onMessage to be invoked")
	}
	if processed.ProviderMessageID != "wamid_123456" {
		t.Fatalf("unexpected provider ID: %s", processed.ProviderMessageID)
	}
	if processed.PhoneE164 == nil || *processed.PhoneE164 != "+628123456789" {
		t.Fatalf("unexpected phone: %v", processed.PhoneE164)
	}
	if processed.Status != StatusReceived {
		t.Fatalf("unexpected status: %s", processed.Status)
	}
}

func TestWebhookInboundMessageDeduplication(t *testing.T) {
	now := time.UnixMilli(1_800_000_000_000)
	store := newMockInboundStore()
	var processCount int

	h := NewWebhookHandler("my-secret-key", nil,
		WithStore(store),
		WithOnMessage(func(ctx context.Context, msg *InboundMessage) {
			processCount++
		}),
	)
	h.now = func() time.Time { return now }

	body := `{
		"event": "message",
		"device_id": "pesenhub-dev", "session_id": "default",
		"payload": {
			"id": "wamid_duplicate_test",
			"timestamp": "2026-09-04T12:00:00Z",
			"from": "628123456789@s.whatsapp.net",
			"is_from_me": false,
			"body": "Pesan pertama"
		}
	}`

	// First delivery: should be stored and processed
	rr1 := httptest.NewRecorder()
	h.ServeHTTP(rr1, signedWebhook(t, h, body, "req-first", now))
	if rr1.Code != http.StatusNoContent {
		t.Fatalf("first request failed: %d", rr1.Code)
	}
	if processCount != 1 {
		t.Fatalf("expected processCount 1, got %d", processCount)
	}

	// Second delivery with different webhook request ID (simulating GOWA retry with new request ID)
	rr2 := httptest.NewRecorder()
	h.ServeHTTP(rr2, signedWebhook(t, h, body, "req-second-retry", now.Add(time.Second)))
	if rr2.Code != http.StatusNoContent {
		t.Fatalf("second request failed: %d", rr2.Code)
	}
	if rr2.Header().Get("X-PesenHub-Deduplicated") != "true" {
		t.Fatal("expected X-PesenHub-Deduplicated header on duplicate")
	}
	if processCount != 1 {
		t.Fatalf("expected processCount to remain 1 on duplicate, got %d", processCount)
	}
	if h.Metrics().Duplicate < 1 {
		t.Fatalf("expected duplicate metric to increment, got %+v", h.Metrics())
	}
}

func TestWebhookInboundMessageQuarantine(t *testing.T) {
	now := time.UnixMilli(1_800_000_000_000)
	store := newMockInboundStore()
	var processed *InboundMessage

	h := NewWebhookHandler("my-secret-key", nil,
		WithStore(store),
		WithOnMessage(func(ctx context.Context, msg *InboundMessage) {
			processed = msg
		}),
	)
	h.now = func() time.Time { return now }

	// Group message
	body := `{
		"event": "message",
		"device_id": "pesenhub-dev", "session_id": "default",
		"payload": {
			"id": "wamid_group_msg",
			"timestamp": "2026-09-04T12:00:00Z",
			"from": "120363025412345678@g.us",
			"is_from_me": false,
			"body": "pesan grup"
		}
	}`

	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, signedWebhook(t, h, body, "req-group", now))

	if rr.Code != http.StatusNoContent {
		t.Fatalf("expected HTTP 204, got %d", rr.Code)
	}
	if processed != nil {
		t.Fatal("onMessage must not be called for quarantined message")
	}

	stored, err := store.GetByProviderMessageID(context.Background(), "wamid_group_msg")
	if err != nil {
		t.Fatalf("expected message to be stored: %v", err)
	}
	if stored.Status != StatusQuarantined {
		t.Fatalf("expected status QUARANTINED, got %s", stored.Status)
	}
	if stored.QuarantineReason != "group_message_not_supported" {
		t.Fatalf("unexpected quarantine reason: %s", stored.QuarantineReason)
	}
}

func TestWebhookInboundMessageInternalError(t *testing.T) {
	now := time.UnixMilli(1_800_000_000_000)
	store := newMockInboundStore()
	store.failNext = errors.New("database connection lost")

	h := NewWebhookHandler("my-secret-key", nil, WithStore(store))
	h.now = func() time.Time { return now }

	body := `{
		"event": "message",
		"device_id": "pesenhub-dev", "session_id": "default",
		"payload": {
			"id": "wamid_fail_test",
			"timestamp": "2026-09-04T12:00:00Z",
			"from": "628123456789@s.whatsapp.net",
			"is_from_me": false,
			"body": "test error"
		}
	}`

	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, signedWebhook(t, h, body, "req-fail", now))

	if rr.Code != http.StatusInternalServerError {
		t.Fatalf("expected HTTP 500 on store error, got %d", rr.Code)
	}
	if !strings.Contains(rr.Body.String(), "INTERNAL_SERVER_ERROR") {
		t.Fatalf("unexpected error response body: %s", rr.Body.String())
	}
}

func TestWebhookInboundMessageFromMeIgnored(t *testing.T) {
	now := time.UnixMilli(1_800_000_000_000)
	store := newMockInboundStore()

	h := NewWebhookHandler("my-secret-key", nil, WithStore(store))
	h.now = func() time.Time { return now }

	body := `{
		"event": "message",
		"device_id": "pesenhub-dev", "session_id": "default",
		"payload": {
			"id": "wamid_from_me",
			"timestamp": "2026-09-04T12:00:00Z",
			"from": "628999999999@s.whatsapp.net",
			"is_from_me": true,
			"body": "pesan dari bot"
		}
	}`

	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, signedWebhook(t, h, body, "req-from-me", now))

	if rr.Code != http.StatusNoContent {
		t.Fatalf("expected HTTP 204 for fromMe, got %d", rr.Code)
	}
	if _, err := store.GetByProviderMessageID(context.Background(), "wamid_from_me"); err == nil {
		t.Fatal("fromMe message should not be stored in inbound store")
	}
}
