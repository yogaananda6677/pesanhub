package order

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"pesenhub/backend/internal/customer"
)

type mockReader struct {
	listFunc    func(context.Context, OrderFilter) ([]OrderDetail, string, error)
	getByIDFunc func(context.Context, string) (OrderDetail, error)
}

func (m *mockReader) List(ctx context.Context, filter OrderFilter) ([]OrderDetail, string, error) {
	if m.listFunc != nil {
		return m.listFunc(ctx, filter)
	}
	return nil, "", nil
}

func (m *mockReader) GetByID(ctx context.Context, id string) (OrderDetail, error) {
	if m.getByIDFunc != nil {
		return m.getByIDFunc(ctx, id)
	}
	return OrderDetail{}, ErrNotFound
}

func TestOrderCursorEncodingDecoding(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Microsecond)
	id := "11111111-1111-4111-8111-111111111111"
	cursor := EncodeCursor(now, id)
	if cursor == "" {
		t.Fatal("expected non-empty cursor")
	}
	gotTime, gotID, err := DecodeCursor(cursor)
	if err != nil {
		t.Fatalf("unexpected decode error: %v", err)
	}
	if !gotTime.Equal(now) || gotID != id {
		t.Fatalf("got (%v, %s), want (%v, %s)", gotTime, gotID, now, id)
	}

	// Empty cursor
	curTime, curID, err := DecodeCursor("")
	if err != nil || !curTime.IsZero() || curID != "" {
		t.Fatalf("empty cursor decode: (%v, %s, %v)", curTime, curID, err)
	}

	// Invalid cursors
	for _, bad := range []string{"not-base64!", "invalid", "MjAyNi0wOS0wM1QxMDowMDowMFosbm90LXV1aWQ="} {
		if _, _, err = DecodeCursor(bad); !errors.Is(err, ErrInvalidInput) {
			t.Errorf("cursor %s expected ErrInvalidInput, got %v", bad, err)
		}
	}
}

func TestOrderListAuthorizationAndRedaction(t *testing.T) {
	phone := "+628123456789"
	orders := []OrderDetail{{
		ID:            "11111111-1111-4111-8111-111111111111",
		OrderNumber:   "ORD-001",
		CustomerID:    "cust-1",
		CustomerName:  "Test Customer",
		CustomerPhone: &phone,
		Status:        "ACCEPTED",
	}}

	r := &mockReader{
		listFunc: func(ctx context.Context, filter OrderFilter) ([]OrderDetail, string, error) {
			// Return a copy so redaction in service doesn't mutate test data directly
			res := make([]OrderDetail, len(orders))
			copy(res, orders)
			return res, "next-token", nil
		},
		getByIDFunc: func(ctx context.Context, id string) (OrderDetail, error) {
			return orders[0], nil
		},
	}
	s := &Service{reader: r}

	// Unauthenticated
	if _, err := s.List(context.Background(), customer.Principal{}, OrderFilter{}); !errors.Is(err, customer.ErrUnauthorized) {
		t.Fatalf("expected unauthorized, got %v", err)
	}

	// Unauthorized role
	if _, err := s.List(context.Background(), customer.Principal{Subject: "cust", Role: "CUSTOMER"}, OrderFilter{}); !errors.Is(err, customer.ErrUnauthorized) {
		t.Fatalf("expected unauthorized for CUSTOMER role, got %v", err)
	}

	// STAFF: should retain customer phone and ID
	staffRes, err := s.List(context.Background(), customer.Principal{Subject: "staff-1", Role: "STAFF"}, OrderFilter{})
	if err != nil {
		t.Fatalf("staff list error: %v", err)
	}
	if len(staffRes.Data) != 1 || staffRes.Data[0].CustomerPhone == nil || *staffRes.Data[0].CustomerPhone != phone || staffRes.Data[0].CustomerID != "cust-1" {
		t.Fatalf("staff received unexpected payload: %#v", staffRes.Data[0])
	}
	if staffRes.Page.NextCursor == nil || *staffRes.Page.NextCursor != "next-token" {
		t.Fatalf("unexpected next cursor: %#v", staffRes.Page.NextCursor)
	}

	// KDS: should redact customer phone and ID
	kdsRes, err := s.List(context.Background(), customer.Principal{Subject: "kds-1", Role: "KDS"}, OrderFilter{})
	if err != nil {
		t.Fatalf("kds list error: %v", err)
	}
	if len(kdsRes.Data) != 1 || kdsRes.Data[0].CustomerPhone != nil || kdsRes.Data[0].CustomerID != "" {
		t.Fatalf("kds should have redacted PII, got %#v", kdsRes.Data[0])
	}
	if kdsRes.Data[0].CustomerName != "Test Customer" {
		t.Fatalf("kds should keep customer name, got %s", kdsRes.Data[0].CustomerName)
	}

	// GetByID KDS redaction
	kdsDetail, err := s.GetByID(context.Background(), customer.Principal{Subject: "kds-1", Role: "KDS"}, "11111111-1111-4111-8111-111111111111")
	if err != nil {
		t.Fatalf("kds get error: %v", err)
	}
	if kdsDetail.CustomerPhone != nil || kdsDetail.CustomerID != "" {
		t.Fatalf("kds detail should have redacted PII, got %#v", kdsDetail)
	}
}

func TestOrderListFilterValidation(t *testing.T) {
	s := &Service{reader: &mockReader{}}
	p := customer.Principal{Subject: "staff", Role: "STAFF"}

	// Invalid status
	if _, err := s.List(context.Background(), p, OrderFilter{Statuses: []string{"INVALID_STATUS"}}); !errors.Is(err, ErrInvalidInput) {
		t.Fatalf("expected ErrInvalidInput for status, got %v", err)
	}

	// Invalid source
	if _, err := s.List(context.Background(), p, OrderFilter{Sources: []string{"INVALID_SOURCE"}}); !errors.Is(err, ErrInvalidInput) {
		t.Fatalf("expected ErrInvalidInput for source, got %v", err)
	}

	// created_from after created_to
	t1 := time.Now()
	t2 := t1.Add(-1 * time.Hour)
	if _, err := s.List(context.Background(), p, OrderFilter{CreatedFrom: &t1, CreatedTo: &t2}); !errors.Is(err, ErrInvalidInput) {
		t.Fatalf("expected ErrInvalidInput for reversed time, got %v", err)
	}
}

func TestHandlerOrderQueries(t *testing.T) {
	phone := "+6281111111"
	r := &mockReader{
		listFunc: func(ctx context.Context, f OrderFilter) ([]OrderDetail, string, error) {
			if len(f.Statuses) > 0 && f.Statuses[0] == "ACCEPTED" {
				return []OrderDetail{{ID: "11111111-1111-4111-8111-111111111111", Status: "ACCEPTED", CustomerPhone: &phone}}, "", nil
			}
			return []OrderDetail{}, "", nil
		},
		getByIDFunc: func(ctx context.Context, id string) (OrderDetail, error) {
			if id == "11111111-1111-4111-8111-111111111111" {
				return OrderDetail{ID: id, Status: "ACCEPTED", CustomerPhone: &phone}, nil
			}
			return OrderDetail{}, ErrNotFound
		},
	}
	s := &Service{reader: r}
	h := NewHandler(s)

	// List without auth -> 403
	req := httptest.NewRequest(http.MethodGet, "/api/v1/orders", nil)
	w := httptest.NewRecorder()
	h.List(w, req)
	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", w.Code)
	}

	// List with invalid query pagination -> 400
	req = httptest.NewRequest(http.MethodGet, "/api/v1/orders?page[size]=0", nil)
	req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{Subject: "staff", Role: "STAFF"}))
	w = httptest.NewRecorder()
	h.List(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}

	// List with valid filters -> 200
	req = httptest.NewRequest(http.MethodGet, "/api/v1/orders?status=ACCEPTED&source=CASHIER_MANUAL&created_from=2026-09-01T00:00:00Z", nil)
	req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{Subject: "staff", Role: "STAFF"}))
	w = httptest.NewRecorder()
	h.List(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}
	var col OrderCollection
	if err := json.NewDecoder(w.Body).Decode(&col); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if len(col.Data) != 1 || col.Data[0].Status != "ACCEPTED" {
		t.Fatalf("unexpected collection: %#v", col)
	}

	// Queue snapshot -> 200
	req = httptest.NewRequest(http.MethodGet, "/api/v1/orders/queue", nil)
	req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{Subject: "kds-1", Role: "KDS"}))
	w = httptest.NewRecorder()
	h.Queue(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}

	// GetByID -> 200
	req = httptest.NewRequest(http.MethodGet, "/api/v1/orders/11111111-1111-4111-8111-111111111111", nil)
	req.SetPathValue("id", "11111111-1111-4111-8111-111111111111")
	req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{Subject: "staff", Role: "STAFF"}))
	w = httptest.NewRecorder()
	h.GetByID(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}

	// GetByID not found -> 404
	req = httptest.NewRequest(http.MethodGet, "/api/v1/orders/22222222-2222-4222-8222-222222222222", nil)
	req.SetPathValue("id", "22222222-2222-4222-8222-222222222222")
	req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{Subject: "staff", Role: "STAFF"}))
	w = httptest.NewRecorder()
	h.GetByID(w, req)
	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d body=%s", w.Code, w.Body.String())
	}
}
