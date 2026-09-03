package order

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/customer"
)

func TestMaskPhone(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"empty", "", ""},
		{"short", "1234567", "****"},
		{"8 digits", "08123456", "0812****3456"},
		{"indonesian +628", "+6281234567890", "+62812****7890"},
		{"indonesian 08", "081234567890", "081234****7890"},
		{"whitespace padded", "  +6281234567890  ", "+62812****7890"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := MaskPhone(tc.input)
			if got != tc.expected {
				t.Fatalf("MaskPhone(%q) = %q; want %q", tc.input, got, tc.expected)
			}
		})
	}
}

func TestSanitizeAuditMetadata(t *testing.T) {
	raw := map[string]any{
		"order_id":              "ord-123",
		"customer_phone":        "+6281234567890",
		"token":                 "secret-token-value",
		"public_tracking_token": "trk_xyz12345",
		"user_password":         "p@ssw0rd",
		"total_amount":          50000,
		"status":                "PENDING",
	}

	sanitizedBytes := SanitizeAuditMetadata(raw)
	var result map[string]any
	if err := json.Unmarshal(sanitizedBytes, &result); err != nil {
		t.Fatalf("failed to unmarshal sanitized JSON: %v", err)
	}

	// Verify phone is masked
	phoneVal, ok := result["customer_phone"].(string)
	if !ok || phoneVal != "+62812****7890" {
		t.Fatalf("expected masked phone +62812****7890, got %v", result["customer_phone"])
	}

	// Verify secrets and tokens are redacted
	if result["token"] != "[REDACTED]" {
		t.Fatalf("expected token redacted, got %v", result["token"])
	}
	if result["public_tracking_token"] != "[REDACTED]" {
		t.Fatalf("expected public_tracking_token redacted, got %v", result["public_tracking_token"])
	}
	if result["user_password"] != "[REDACTED]" {
		t.Fatalf("expected user_password redacted, got %v", result["user_password"])
	}

	// Verify normal fields are preserved
	if result["order_id"] != "ord-123" {
		t.Fatalf("expected order_id preserved, got %v", result["order_id"])
	}
	if result["status"] != "PENDING" {
		t.Fatalf("expected status preserved, got %v", result["status"])
	}
}

type mockAuditStore struct {
	entries []AuditLogEntry
	err     error
}

func (m *mockAuditStore) GetAuditLogs(ctx context.Context, orderID, actorID, requestID string) ([]AuditLogEntry, error) {
	if m.err != nil {
		return nil, m.err
	}
	return m.entries, nil
}

func TestHandlerGetAuditLogsRBAC(t *testing.T) {
	mockStore := &mockAuditStore{
		entries: []AuditLogEntry{
			{
				ID:            "audit-1",
				AggregateType: "ORDER",
				AggregateID:   "c1000000-0000-4000-8000-000000000001",
				Action:        "ORDER_CREATED",
				ActorType:     "STAFF",
				ActorID:       "staff-1",
				RequestID:     "req-1",
				Metadata:      json.RawMessage(`{"status":"PENDING"}`),
				CreatedAt:     time.Now().UTC(),
			},
		},
	}

	svc := &Service{auditStore: mockStore}
	h := NewHandler(svc)

	// 1. Unauthenticated request -> 403 Forbidden
	req := httptest.NewRequest(http.MethodGet, "/api/v1/orders/c1000000-0000-4000-8000-000000000001/audit-logs", nil)
	req.SetPathValue("id", "c1000000-0000-4000-8000-000000000001")
	w := httptest.NewRecorder()
	h.GetAuditLogs(w, req)
	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden for unauthenticated request, got %d", w.Code)
	}

	// 2. Non-STAFF role request (e.g. CUSTOMER) -> 403 Forbidden
	req = httptest.NewRequest(http.MethodGet, "/api/v1/orders/c1000000-0000-4000-8000-000000000001/audit-logs", nil)
	req.SetPathValue("id", "c1000000-0000-4000-8000-000000000001")
	req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{Subject: "cust-1", Role: "CUSTOMER"}))
	w = httptest.NewRecorder()
	h.GetAuditLogs(w, req)
	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden for non-STAFF, got %d", w.Code)
	}

	// 3. STAFF role request -> 200 OK with audit log entries
	req = httptest.NewRequest(http.MethodGet, "/api/v1/orders/c1000000-0000-4000-8000-000000000001/audit-logs", nil)
	req.SetPathValue("id", "c1000000-0000-4000-8000-000000000001")
	req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{Subject: "staff-1", Role: "STAFF"}))
	w = httptest.NewRecorder()
	h.GetAuditLogs(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for STAFF, got %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "ORDER_CREATED") {
		t.Fatalf("expected audit log entry in response, got %s", w.Body.String())
	}
}
