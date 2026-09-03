package order

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"pesenhub/backend/internal/customer"
)

func TestHandlerCreateManual(t *testing.T) {
	s := NewService(creatorFunc(func(context.Context, CreateInput, string, string, string) (Order, bool, error) {
		return Order{ID: "order-1", Status: "PENDING", Source: "CASHIER_MANUAL"}, true, nil
	}))
	h := NewHandler(s)
	body := `{"client_order_id":"11111111-1111-4111-8111-111111111111","customer_name":"Budi","items":[{"menu_id":"22222222-2222-4222-8222-222222222222","quantity":1}]}`
	r := httptest.NewRequest(http.MethodPost, "/api/v1/orders", strings.NewReader(body))
	r.Header.Set("Idempotency-Key", "key")
	r = r.WithContext(customer.WithPrincipal(r.Context(), customer.Principal{Subject: "staff-1", Role: "STAFF"}))
	w := httptest.NewRecorder()
	h.CreateManual(w, r)
	if w.Code != http.StatusCreated || w.Header().Get("Location") != "/api/v1/orders/order-1" {
		t.Fatalf("status=%d location=%s body=%s", w.Code, w.Header().Get("Location"), w.Body.String())
	}
}
func TestHandlerRequiresStaff(t *testing.T) {
	h := NewHandler(NewService(nil))
	r := httptest.NewRequest(http.MethodPost, "/api/v1/orders", strings.NewReader(`{}`))
	w := httptest.NewRecorder()
	h.CreateManual(w, r)
	if w.Code != http.StatusForbidden {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}
func TestHandlerMapsIdempotencyConflict(t *testing.T) {
	s := NewService(creatorFunc(func(context.Context, CreateInput, string, string, string) (Order, bool, error) {
		return Order{}, false, ErrIdempotencyConflict
	}))
	h := NewHandler(s)
	r := httptest.NewRequest(http.MethodPost, "/api/v1/orders", strings.NewReader(`{"client_order_id":"11111111-1111-4111-8111-111111111111","customer_name":"Budi","items":[{"menu_id":"22222222-2222-4222-8222-222222222222","quantity":1}]}`))
	r.Header.Set("Idempotency-Key", "key")
	r = r.WithContext(customer.WithPrincipal(r.Context(), customer.Principal{Subject: "staff", Role: "STAFF"}))
	w := httptest.NewRecorder()
	h.CreateManual(w, r)
	if w.Code != http.StatusConflict {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}
