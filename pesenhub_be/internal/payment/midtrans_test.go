package payment

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestMidtransClientCreatesQRISWithServerSideAmount(t *testing.T) {
	const secret = "SB-Mid-server-test-secret"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, password, ok := r.BasicAuth()
		if !ok || user != secret || password != "" {
			t.Fatal("invalid Midtrans Basic authentication")
		}
		var body struct {
			PaymentType string `json:"payment_type"`
			Details     struct {
				OrderID     string `json:"order_id"`
				GrossAmount int64  `json:"gross_amount"`
			} `json:"transaction_details"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if body.PaymentType != "qris" || body.Details.OrderID != "PH-payment-1" || body.Details.GrossAmount != 27500 {
			t.Fatalf("unexpected request: %#v", body)
		}
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"transaction_id":"tx-1","order_id":"PH-payment-1","payment_type":"qris","gross_amount":"27500.00","transaction_status":"pending","expiry_time":"2026-09-05 15:30:00","signature_key":"must-not-be-stored","actions":[{"name":"generate-qr-code","method":"GET","url":"https://api.sandbox.midtrans.com/v2/qris/tx-1/qr-code"}]}`))
	}))
	defer server.Close()

	charge, err := NewMidtransClient(server.URL, secret, time.Second).CreateQRIS(context.Background(), "PH-payment-1", 27500)
	if err != nil {
		t.Fatal(err)
	}
	if charge.ProviderReference != "tx-1" || charge.Status != "pending" || charge.QRCodeURL == "" || charge.ExpiresAt == nil {
		t.Fatalf("unexpected charge: %#v", charge)
	}
	if strings.Contains(charge.QRCodeURL, secret) {
		t.Fatal("server key leaked into result")
	}
}

func TestMidtransClientMapsSafeErrors(t *testing.T) {
	tests := []struct {
		name string
		code int
		body string
		want string
	}{
		{"4xx", 401, `{"status_message":"contains secret provider detail"}`, "rejected"},
		{"duplicate", 406, `{"status_message":"order_id already used"}`, "duplicate"},
		{"rate limited", 429, `{}`, "rate_limited"},
		{"5xx", 500, `{"status_message":"internal provider detail"}`, "server"},
		{"invalid success", 201, `{"transaction_id":"tx-1"}`, "invalid_response"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(tt.code); _, _ = w.Write([]byte(tt.body)) }))
			defer server.Close()
			_, err := NewMidtransClient(server.URL, "dummy-secret", time.Second).CreateQRIS(context.Background(), "PH-1", 1000)
			providerErr, ok := err.(*ProviderError)
			if !ok || providerErr.Kind != tt.want || strings.Contains(err.Error(), "provider detail") || strings.Contains(err.Error(), "dummy-secret") {
				t.Fatalf("unexpected safe error: %#v", err)
			}
		})
	}
}

func TestMidtransClientTimeoutIsSanitized(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { time.Sleep(50 * time.Millisecond) }))
	defer server.Close()
	_, err := NewMidtransClient(server.URL, "dummy-secret", 5*time.Millisecond).CreateQRIS(context.Background(), "PH-1", 1000)
	providerErr, ok := err.(*ProviderError)
	if !ok || providerErr.Kind != "timeout" || strings.Contains(err.Error(), "dummy-secret") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestMidtransClientGetsValidatedStatus(t *testing.T) {
	const secret = "SB-Mid-server-status-secret"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, password, ok := r.BasicAuth()
		if !ok || user != secret || password != "" || r.Method != http.MethodGet || r.URL.Path != "/v2/PH-payment-1/status" {
			t.Fatalf("unexpected status request: %s %s auth=%v/%q/%q", r.Method, r.URL.Path, ok, user, password)
		}
		_, _ = w.Write([]byte(`{"status_code":"200","transaction_id":"tx-1","order_id":"PH-payment-1","payment_type":"qris","gross_amount":"27500.00","currency":"IDR","transaction_status":"settlement","fraud_status":"accept","settlement_time":"2026-09-05 17:00:00","signature_key":"not-persisted"}`))
	}))
	defer server.Close()

	status, err := NewMidtransClient(server.URL, secret, time.Second).GetStatus(context.Background(), "PH-payment-1")
	if err != nil || status.TransactionStatus != "settlement" || status.TransactionID != "tx-1" {
		t.Fatalf("status=%#v err=%v", status, err)
	}
}

func TestMidtransClientStatusErrorsAreSanitized(t *testing.T) {
	tests := []struct {
		name string
		code int
		body string
		want string
	}{
		{"not found", 404, `{"status_message":"private detail"}`, "not_found"},
		{"authentication", 401, `{}`, "authentication"},
		{"rate limit", 429, `{}`, "rate_limited"},
		{"timeout", 504, `{}`, "timeout"},
		{"invalid success", 200, `{"transaction_id":"tx-only"}`, "invalid_response"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(tt.code)
				_, _ = w.Write([]byte(tt.body))
			}))
			defer server.Close()
			_, err := NewMidtransClient(server.URL, "dummy-status-secret", time.Second).GetStatus(context.Background(), "PH-1")
			providerErr, ok := err.(*ProviderError)
			if !ok || providerErr.Kind != tt.want || strings.Contains(err.Error(), "private detail") || strings.Contains(err.Error(), "dummy-status-secret") {
				t.Fatalf("unexpected safe error: %#v", err)
			}
		})
	}
}
