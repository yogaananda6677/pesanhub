package order

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestNormalizePhone(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    string
		wantErr bool
	}{
		{"Valid 08 format", "08123456789", "+628123456789", false},
		{"Valid +628 format", "+6281234567890", "+6281234567890", false},
		{"Valid 628 format", "6281234567890", "+6281234567890", false},
		{"Empty string", "", "", true},
		{"Whitespace only", "   ", "", true},
		{"Not 08 or +628", "0217654321", "", true},
		{"Too short", "0812", "", true},
		{"Too long", "081234567890123456", "", true},
		{"Contains letters", "0812abcd5678", "", true},
		{"Contains special symbols", "0812-3456-789", "", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := NormalizePhone(tt.input)
			if (err != nil) != tt.wantErr {
				t.Fatalf("NormalizePhone(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
			}
			if !tt.wantErr && got != tt.want {
				t.Fatalf("NormalizePhone(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

func TestValidateCustomerName(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    string
		wantErr bool
	}{
		{"Valid name", "Budi Santoso", "Budi Santoso", false},
		{"Trimmed name", "  Siti Rahma  ", "Siti Rahma", false},
		{"Empty name", "", "", true},
		{"Whitespace only", "    ", "", true},
		{"Name too long", strings.Repeat("A", 121), "", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ValidateCustomerName(tt.input)
			if (err != nil) != tt.wantErr {
				t.Fatalf("ValidateCustomerName(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
			}
			if !tt.wantErr && got != tt.want {
				t.Fatalf("ValidateCustomerName(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

func TestIPRateLimiter(t *testing.T) {
	limiter := newIPRateLimiter(3, 100*time.Millisecond)

	ip := "192.168.1.1"

	if !limiter.Allow(ip) {
		t.Fatal("request 1 should be allowed")
	}
	if !limiter.Allow(ip) {
		t.Fatal("request 2 should be allowed")
	}
	if !limiter.Allow(ip) {
		t.Fatal("request 3 should be allowed")
	}
	if limiter.Allow(ip) {
		t.Fatal("request 4 should be blocked by rate limiter")
	}

	// Another IP should still be allowed
	if !limiter.Allow("192.168.1.2") {
		t.Fatal("request from different IP should be allowed")
	}

	// Wait for window to expire
	time.Sleep(120 * time.Millisecond)
	if !limiter.Allow(ip) {
		t.Fatal("request after window expiry should be allowed")
	}
}

type mockWebStore struct {
	createWebFunc  func(ctx context.Context, in PublicOrderCreateInput, key, hash, requestID string) (PublicOrderResponse, bool, error)
	previewWebFunc func(ctx context.Context, items []ItemInput) (PreviewResponse, error)
	getByTokenFunc func(ctx context.Context, token string) (PublicTrackingDetail, error)
}

func (m *mockWebStore) Create(ctx context.Context, in CreateInput, key, hash, actorID string) (Order, bool, error) {
	return Order{}, false, nil
}

func (m *mockWebStore) CreateWeb(ctx context.Context, in PublicOrderCreateInput, key, hash, requestID string) (PublicOrderResponse, bool, error) {
	if m.createWebFunc != nil {
		return m.createWebFunc(ctx, in, key, hash, requestID)
	}
	return PublicOrderResponse{}, false, nil
}

func (m *mockWebStore) PreviewWeb(ctx context.Context, items []ItemInput) (PreviewResponse, error) {
	if m.previewWebFunc != nil {
		return m.previewWebFunc(ctx, items)
	}
	return PreviewResponse{}, nil
}

func (m *mockWebStore) GetByPublicToken(ctx context.Context, token string) (PublicTrackingDetail, error) {
	if m.getByTokenFunc != nil {
		return m.getByTokenFunc(ctx, token)
	}
	return PublicTrackingDetail{}, nil
}

func TestHandlerWebOrderPreview(t *testing.T) {
	store := &mockWebStore{
		previewWebFunc: func(ctx context.Context, items []ItemInput) (PreviewResponse, error) {
			return PreviewResponse{
				SubtotalAmount: 25000,
				TotalAmount:    25000,
				Items: []PreviewItem{
					{
						MenuID:          items[0].MenuID,
						Name:            "Nasi Goreng Spesial",
						Quantity:        1,
						UnitPriceAmount: 25000,
						LineTotalAmount: 25000,
					},
				},
			}, nil
		},
	}

	svc := NewService(store)
	h := NewHandler(svc)

	body, _ := json.Marshal(PreviewInput{
		Items: []ItemInput{{MenuID: "m-1", Quantity: 1}},
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/public/orders/preview", bytes.NewReader(body))
	w := httptest.NewRecorder()

	h.PreviewWeb(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", w.Code, w.Body.String())
	}

	var res map[string]PreviewResponse
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("json unmarshal error: %v", err)
	}
	if res["data"].TotalAmount != 25000 {
		t.Fatalf("expected total 25000, got %d", res["data"].TotalAmount)
	}
}

func TestHandlerWebOrderValidation(t *testing.T) {
	store := &mockWebStore{}
	svc := NewService(store)
	h := NewHandler(svc)

	// Test empty customer name
	body, _ := json.Marshal(PublicOrderCreateInput{
		CustomerName:  "",
		CustomerPhone: "08123456789",
		Items:         []ItemInput{{MenuID: "m-1", Quantity: 1}},
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/public/orders", bytes.NewReader(body))
	w := httptest.NewRecorder()

	h.CreateWeb(w, req)
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422 for empty name, got %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "customer_name") {
		t.Fatalf("expected error details to contain customer_name, got %s", w.Body.String())
	}

	// Test invalid phone number
	body, _ = json.Marshal(PublicOrderCreateInput{
		CustomerName:  "Budi",
		CustomerPhone: "12345",
		Items:         []ItemInput{{MenuID: "m-1", Quantity: 1}},
	})
	req = httptest.NewRequest(http.MethodPost, "/api/v1/public/orders", bytes.NewReader(body))
	w = httptest.NewRecorder()

	h.CreateWeb(w, req)
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422 for invalid phone, got %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "customer_phone") {
		t.Fatalf("expected error details to contain customer_phone, got %s", w.Body.String())
	}
}

func TestHandlerGetByPublicTokenNotFound(t *testing.T) {
	store := &mockWebStore{
		getByTokenFunc: func(ctx context.Context, token string) (PublicTrackingDetail, error) {
			return PublicTrackingDetail{}, ErrNotFound
		},
	}
	svc := NewService(store)
	h := NewHandler(svc)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/public/orders/trk_unknown", nil)
	req.SetPathValue("token", "trk_unknown")
	w := httptest.NewRecorder()

	h.GetByPublicToken(w, req)
	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for unknown token, got %d: %s", w.Code, w.Body.String())
	}
}
