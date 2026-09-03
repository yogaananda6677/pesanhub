package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestWriteJSONSuccessContract(t *testing.T) {
	rr := httptest.NewRecorder()
	WriteJSON(rr, http.StatusOK, map[string]string{"status": "ok"})
	if rr.Code != http.StatusOK || rr.Header().Get("Content-Type") != jsonContentType || rr.Body.String() != "{\"status\":\"ok\"}\n" {
		t.Fatalf("unexpected success response: %d %q %s", rr.Code, rr.Header().Get("Content-Type"), rr.Body.String())
	}
}

func TestWriteErrorContract(t *testing.T) {
	rr := httptest.NewRecorder()
	WriteError(rr, http.StatusUnprocessableEntity, "VALIDATION_FAILED", "Request validation failed.", "req-123", []FieldError{{Field: "name", Reason: "required"}})
	if rr.Code != http.StatusUnprocessableEntity || rr.Header().Get("Content-Type") != jsonContentType {
		t.Fatalf("status/content-type = %d/%q", rr.Code, rr.Header().Get("Content-Type"))
	}
	var body ErrorEnvelope
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Error.Code != "VALIDATION_FAILED" || body.Error.RequestID != "req-123" || len(body.Error.Details) != 1 {
		t.Fatalf("unexpected envelope: %#v", body)
	}
}

func TestWriteErrorOmitsEmptyDetails(t *testing.T) {
	rr := httptest.NewRecorder()
	WriteError(rr, http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred.", "req-456", nil)
	if string(rr.Body.Bytes()) != "{\"error\":{\"code\":\"INTERNAL_ERROR\",\"message\":\"An unexpected error occurred.\",\"request_id\":\"req-456\"}}\n" {
		t.Fatalf("unexpected body: %s", rr.Body.String())
	}
}
