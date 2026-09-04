package waha

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha512"
	"encoding/hex"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func signedWebhook(t *testing.T, h *WebhookHandler, body, id string, at time.Time) *http.Request {
	t.Helper()
	mac := hmac.New(sha512.New, h.secret)
	_, _ = mac.Write([]byte(body))
	r := httptest.NewRequest(http.MethodPost, "/webhooks/waha", strings.NewReader(body))
	r.Header.Set("X-Webhook-Request-Id", id)
	r.Header.Set("X-Webhook-Timestamp", strconv.FormatInt(at.UnixMilli(), 10))
	r.Header.Set("X-Webhook-Hmac-Algorithm", "sha512")
	r.Header.Set("X-Webhook-Hmac", hex.EncodeToString(mac.Sum(nil)))
	return r
}

func TestWebhookAcceptsOfficialWAHAHMACShape(t *testing.T) {
	now := time.UnixMilli(1_800_000_000_000)
	h := NewWebhookHandler("my-secret-key", nil)
	h.now = func() time.Time { return now }
	body := `{"event":"message","session":"default","engine":"WEBJS"}`
	mac := hmac.New(sha512.New, []byte("my-secret-key"))
	_, _ = mac.Write([]byte(body))
	const documentedSignature = "208f8a55dde9e05519e898b10b89bf0d0b3b0fdf11fdbf09b6b90476301b98d8097c462b2b17a6ce93b6b47a136cf2e78a33a63f6752c2c1631777076153fa89"
	if hex.EncodeToString(mac.Sum(nil)) != documentedSignature {
		t.Fatal("fixture no longer matches the official WAHA HMAC example")
	}
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, signedWebhook(t, h, body, "evt-1", now))
	if rr.Code != http.StatusNoContent || h.Metrics().Accepted != 1 {
		t.Fatalf("response=%d metrics=%+v", rr.Code, h.Metrics())
	}
}

func TestWebhookRejectsInvalidProofAndStaleTimestamp(t *testing.T) {
	now := time.UnixMilli(1_800_000_000_000)
	h := NewWebhookHandler("my-secret-key", nil)
	h.now = func() time.Time { return now }

	badProof := signedWebhook(t, h, `{}`, "evt-bad", now)
	badProof.Header.Set("X-Webhook-Hmac", strings.Repeat("0", sha512.Size*2))
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, badProof)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("invalid proof response=%d", rr.Code)
	}

	rr = httptest.NewRecorder()
	h.ServeHTTP(rr, signedWebhook(t, h, `{}`, "evt-stale", now.Add(-6*time.Minute)))
	if rr.Code != http.StatusUnauthorized || h.Metrics().AuthenticationFailed != 2 {
		t.Fatalf("stale response=%d metrics=%+v", rr.Code, h.Metrics())
	}
}

func TestWebhookDuplicateIsAcknowledgedWithoutSecondAcceptance(t *testing.T) {
	now := time.UnixMilli(1_800_000_000_000)
	h := NewWebhookHandler("my-secret-key", nil)
	h.now = func() time.Time { return now }
	for range 2 {
		rr := httptest.NewRecorder()
		h.ServeHTTP(rr, signedWebhook(t, h, `{"event":"message","session":"default"}`, "evt-retry", now))
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
		request := signedWebhook(t, h, `{"event":"message","session":"default"}`, "evt-concurrent", now)
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
	r := httptest.NewRequest(http.MethodPost, "/webhooks/waha", strings.NewReader(strings.Repeat("private-payload", 100_000)))
	h.ServeHTTP(rr, r)
	if rr.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("response=%d", rr.Code)
	}
	if strings.Contains(logs.String(), "private-payload") || strings.Contains(logs.String(), "do-not-log-secret") {
		t.Fatalf("sensitive log: %s", logs.String())
	}
}
