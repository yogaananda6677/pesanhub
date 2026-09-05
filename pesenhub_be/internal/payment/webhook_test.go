package payment

import (
	"bytes"
	"context"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const webhookTestKey = "SB-Mid-server-webhook-test"

type fakeWebhookStore struct {
	calls        int
	notification MidtransNotification
	eventID      string
	result       WebhookResult
	err          error
}

func (f *fakeWebhookStore) ApplyMidtransWebhook(_ context.Context, notification MidtransNotification, eventID, _ string, _ *time.Time) (WebhookResult, error) {
	f.calls++
	f.notification, f.eventID = notification, eventID
	return f.result, f.err
}

func signedMidtransNotification(t *testing.T, mutate func(*MidtransNotification)) string {
	t.Helper()
	n := MidtransNotification{
		OrderID: "PH-b1000000-0000-4000-8000-000000000001", TransactionID: "tx-dummy-1", TransactionStatus: "settlement",
		StatusCode: "200", GrossAmount: "27500.00", PaymentType: "qris", MerchantID: "G123456789", FraudStatus: "accept", Currency: "IDR",
		TransactionTime: "2026-09-05 12:00:00", SettlementTime: "2026-09-05 12:01:00",
	}
	if mutate != nil {
		mutate(&n)
	}
	sum := sha512.Sum512([]byte(n.OrderID + n.StatusCode + n.GrossAmount + webhookTestKey))
	n.SignatureKey = hex.EncodeToString(sum[:])
	body, err := json.Marshal(n)
	if err != nil {
		t.Fatal(err)
	}
	return string(body)
}

func TestMidtransWebhookAcceptsVerifiedSettlement(t *testing.T) {
	store := &fakeWebhookStore{result: WebhookResult{Payment: Payment{ID: "pay-1", Status: "PAID"}, Applied: true}}
	handler := NewMidtransWebhookHandler(webhookTestKey, "G123456789", store, nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/webhooks/midtrans", strings.NewReader(signedMidtransNotification(t, nil))))
	if response.Code != http.StatusOK || store.calls != 1 || store.eventID == "" || !strings.Contains(response.Body.String(), `"payment_status":"PAID"`) {
		t.Fatalf("status=%d calls=%d event=%q body=%s", response.Code, store.calls, store.eventID, response.Body.String())
	}
	if metrics := handler.Metrics(); metrics.Accepted != 1 || metrics.Applied != 1 {
		t.Fatalf("metrics=%+v", metrics)
	}
}

func TestMidtransWebhookRejectsInvalidSignatureBeforeStore(t *testing.T) {
	store := &fakeWebhookStore{}
	handler := NewMidtransWebhookHandler(webhookTestKey, "G123456789", store, nil)
	body := signedMidtransNotification(t, nil)
	body = strings.Replace(body, "27500.00", "1.00", 1)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/webhooks/midtrans", strings.NewReader(body)))
	if response.Code != http.StatusUnauthorized || store.calls != 0 || !strings.Contains(response.Body.String(), "INVALID_WEBHOOK_SIGNATURE") {
		t.Fatalf("status=%d calls=%d body=%s", response.Code, store.calls, response.Body.String())
	}
}

func TestMidtransWebhookRejectsSignedWrongMerchantAndAmountMismatch(t *testing.T) {
	t.Run("merchant", func(t *testing.T) {
		store := &fakeWebhookStore{}
		handler := NewMidtransWebhookHandler(webhookTestKey, "G123456789", store, nil)
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/webhooks/midtrans", strings.NewReader(signedMidtransNotification(t, func(n *MidtransNotification) { n.MerchantID = "G000000000" }))))
		if response.Code != http.StatusBadRequest || store.calls != 0 {
			t.Fatalf("status=%d calls=%d", response.Code, store.calls)
		}
	})
	t.Run("amount", func(t *testing.T) {
		store := &fakeWebhookStore{err: ErrWebhookAmount}
		handler := NewMidtransWebhookHandler(webhookTestKey, "G123456789", store, nil)
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/webhooks/midtrans", strings.NewReader(signedMidtransNotification(t, nil))))
		if response.Code != http.StatusUnprocessableEntity || !strings.Contains(response.Body.String(), "WEBHOOK_MISMATCH") {
			t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
		}
	})
}

func TestMapMidtransStatus(t *testing.T) {
	tests := []struct {
		provider, fraud, code, want string
		invalid                     bool
	}{
		{"pending", "", "201", "PENDING_PAYMENT", false}, {"settlement", "accept", "200", "PAID", false},
		{"capture", "challenge", "200", "PENDING_PAYMENT", false}, {"settlement", "deny", "200", "FAILED", false},
		{"deny", "", "202", "FAILED", false}, {"cancel", "", "202", "FAILED", false}, {"failure", "", "500", "FAILED", false},
		{"expire", "", "407", "EXPIRED", false}, {"refund", "", "200", "REFUNDED", false}, {"partial_refund", "", "200", "REFUNDED", false},
		{"settlement", "accept", "201", "", true}, {"unknown", "", "200", "", true},
	}
	for _, tt := range tests {
		t.Run(tt.provider+tt.fraud+tt.code, func(t *testing.T) {
			got, err := mapMidtransStatus(MidtransNotification{TransactionStatus: tt.provider, FraudStatus: tt.fraud, StatusCode: tt.code})
			if got != tt.want || (err != nil) != tt.invalid {
				t.Fatalf("got=%q err=%v", got, err)
			}
		})
	}
}

func TestMidtransWebhookAcknowledgesDuplicateAndRetriesStoreFailure(t *testing.T) {
	t.Run("duplicate", func(t *testing.T) {
		store := &fakeWebhookStore{result: WebhookResult{Payment: Payment{ID: "pay-1", Status: "PAID"}, Duplicate: true}}
		handler := NewMidtransWebhookHandler(webhookTestKey, "G123456789", store, nil)
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/webhooks/midtrans", strings.NewReader(signedMidtransNotification(t, nil))))
		if response.Code != http.StatusOK || response.Header().Get("X-PesenHub-Deduplicated") != "true" || handler.Metrics().Duplicate != 1 {
			t.Fatalf("status=%d headers=%v metrics=%+v", response.Code, response.Header(), handler.Metrics())
		}
	})
	t.Run("store failure", func(t *testing.T) {
		store := &fakeWebhookStore{err: context.DeadlineExceeded}
		handler := NewMidtransWebhookHandler(webhookTestKey, "G123456789", store, nil)
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/webhooks/midtrans", strings.NewReader(signedMidtransNotification(t, nil))))
		if response.Code != http.StatusServiceUnavailable || strings.Contains(response.Body.String(), "deadline") || handler.Metrics().StoreFailed != 1 {
			t.Fatalf("status=%d body=%s metrics=%+v", response.Code, response.Body.String(), handler.Metrics())
		}
	})
}

func TestMidtransWebhookLimitsBodyAndDoesNotLogPayloadOrSecret(t *testing.T) {
	var logs bytes.Buffer
	handler := NewMidtransWebhookHandler("do-not-log-secret", "G123456789", &fakeWebhookStore{}, slog.New(slog.NewJSONHandler(&logs, nil)))
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/webhooks/midtrans", strings.NewReader(strings.Repeat("private-payload", 100_000))))
	if response.Code != http.StatusRequestEntityTooLarge || strings.Contains(logs.String(), "private-payload") || strings.Contains(logs.String(), "do-not-log-secret") {
		t.Fatalf("status=%d logs=%s", response.Code, logs.String())
	}
}

func TestMidtransEventIDIsStableWithoutContainingSignature(t *testing.T) {
	var n MidtransNotification
	if err := json.Unmarshal([]byte(signedMidtransNotification(t, nil)), &n); err != nil {
		t.Fatal(err)
	}
	first, second := midtransEventID(n), midtransEventID(n)
	if first != second || strings.Contains(first, n.SignatureKey) || len(first) != len("notification:")+64 {
		t.Fatalf("event id=%q", first)
	}
}
