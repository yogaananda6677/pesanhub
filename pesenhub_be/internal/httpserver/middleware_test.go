package httpserver

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"pesenhub/backend/internal/httpapi"
)

func testLogger() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

func TestMiddlewarePreservesValidRequestID(t *testing.T) {
	handler := Middleware(testLogger(), http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := RequestID(r.Context()); got != "client-request-1" {
			t.Fatalf("context request id = %q", got)
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	req := httptest.NewRequest(http.MethodGet, "/api/v1/example", nil)
	req.Header.Set("X-Request-ID", "client-request-1")
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)
	if got := rr.Header().Get("X-Request-ID"); got != "client-request-1" {
		t.Fatalf("response request id = %q", got)
	}
}

func TestMiddlewareReplacesUnsafeRequestID(t *testing.T) {
	handler := Middleware(testLogger(), http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) }))
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("X-Request-ID", "unsafe request id")
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)
	if got := rr.Header().Get("X-Request-ID"); !validRequestID.MatchString(got) || got == req.Header.Get("X-Request-ID") {
		t.Fatalf("generated request id = %q", got)
	}
}

func TestMiddlewarePanicUsesErrorContract(t *testing.T) {
	handler := Middleware(testLogger(), http.HandlerFunc(func(http.ResponseWriter, *http.Request) { panic("sensitive detail") }))
	req := httptest.NewRequest(http.MethodGet, "/api/v1/example", nil)
	req.Header.Set("X-Request-ID", "req-panic")
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)
	var body httpapi.ErrorEnvelope
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if rr.Code != http.StatusInternalServerError || body.Error.Code != "INTERNAL_ERROR" || body.Error.RequestID != "req-panic" || body.Error.Message == "sensitive detail" {
		t.Fatalf("status/envelope = %d/%#v", rr.Code, body)
	}
}
