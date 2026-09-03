package customer

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"pesenhub/backend/internal/httpserver"
)

func TestCreateHandlerSuccessAndValidation(t *testing.T) {
	repo := &fakeRepo{created: true}
	h := NewHandler(NewService(repo, func() string { return "10000000-0000-4000-8000-000000000001" }))
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/customers", h.Create)
	server := httpserver.Middleware(slog.New(slog.NewTextHandler(io.Discard, nil)), mux)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/customers", strings.NewReader(`{"phone":"081234567890","display_name":"Ayu","preferences":{}}`))
	req.Header.Set("Idempotency-Key", "customer-create-1")
	rr := httptest.NewRecorder()
	server.ServeHTTP(rr, req)
	if rr.Code != http.StatusCreated || !strings.Contains(rr.Body.String(), `"phone_e164":"+6281234567890"`) || rr.Header().Get("Location") == "" {
		t.Fatalf("success: %d %s", rr.Code, rr.Body.String())
	}

	bad := httptest.NewRequest(http.MethodPost, "/api/v1/customers", strings.NewReader(`{"phone":"021","display_name":"Ayu"}`))
	bad.Header.Set("Idempotency-Key", "customer-create-2")
	badRR := httptest.NewRecorder()
	server.ServeHTTP(badRR, bad)
	if badRR.Code != http.StatusUnprocessableEntity || !strings.Contains(badRR.Body.String(), `"code":"VALIDATION_FAILED"`) || !strings.Contains(badRR.Body.String(), `"request_id"`) {
		t.Fatalf("invalid: %d %s", badRR.Code, badRR.Body.String())
	}
}

func TestHistoryHandlerDeniesGuessedCustomerID(t *testing.T) {
	h := NewHandler(NewService(&fakeRepo{}, func() string { return "unused" }))
	req := httptest.NewRequest(http.MethodGet, "/api/v1/customers/guessed/orders", nil)
	req.SetPathValue("id", "guessed")
	rr := httptest.NewRecorder()
	httpserver.Middleware(slog.New(slog.NewTextHandler(io.Discard, nil)), http.HandlerFunc(h.History)).ServeHTTP(rr, req)
	if rr.Code != http.StatusUnauthorized || !strings.Contains(rr.Body.String(), `"code":"UNAUTHENTICATED"`) {
		t.Fatalf("response: %d %s", rr.Code, rr.Body.String())
	}
}
