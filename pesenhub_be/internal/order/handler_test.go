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

func TestHandlerTransitionStatus(t *testing.T) {
	s := &Service{transitions: transitionerFunc(func(_ context.Context, id string, _ TransitionInput, _ string, _ string, _ string, _ string) (StatusResult, bool, error) {
		return StatusResult{ID: id, Status: "READY_FOR_PICKUP", Version: 4}, true, nil
	})}
	h := NewHandler(s)
	r := httptest.NewRequest(http.MethodPost, "/api/v1/orders/11111111-1111-4111-8111-111111111111/status-transitions", strings.NewReader(`{"target_status":"READY_FOR_PICKUP","expected_version":3}`))
	r.SetPathValue("id", "11111111-1111-4111-8111-111111111111")
	r.Header.Set("Idempotency-Key", "status-key")
	r = r.WithContext(customer.WithPrincipal(r.Context(), customer.Principal{Subject: "staff", Role: "STAFF"}))
	w := httptest.NewRecorder()
	h.TransitionStatus(w, r)
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"version":4`) {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestHandlerMapsLifecycleConflicts(t *testing.T) {
	for _, tc := range []struct {
		err  error
		code string
	}{{ErrVersionConflict, "VERSION_CONFLICT"}, {ErrInvalidTransition, "INVALID_STATUS_TRANSITION"}, {ErrNotFound, "ORDER_NOT_FOUND"}} {
		s := &Service{transitions: transitionerFunc(func(context.Context, string, TransitionInput, string, string, string, string) (StatusResult, bool, error) {
			return StatusResult{}, false, tc.err
		})}
		h := NewHandler(s)
		r := httptest.NewRequest(http.MethodPost, "/api/v1/orders/11111111-1111-4111-8111-111111111111/status-transitions", strings.NewReader(`{"target_status":"ACCEPTED","expected_version":1}`))
		r.SetPathValue("id", "11111111-1111-4111-8111-111111111111")
		r.Header.Set("Idempotency-Key", "key")
		r = r.WithContext(customer.WithPrincipal(r.Context(), customer.Principal{Subject: "staff", Role: "STAFF"}))
		w := httptest.NewRecorder()
		h.TransitionStatus(w, r)
		if !strings.Contains(w.Body.String(), tc.code) {
			t.Errorf("error=%v status=%d body=%s", tc.err, w.Code, w.Body.String())
		}
	}
}
