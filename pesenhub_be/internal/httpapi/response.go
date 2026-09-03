package httpapi

import (
	"encoding/json"
	"net/http"
)

const jsonContentType = "application/json; charset=utf-8"

// FieldError is a safe, machine-readable validation detail. Values and rejected
// input are intentionally excluded to prevent accidental PII disclosure.
type FieldError struct {
	Field  string `json:"field"`
	Reason string `json:"reason"`
}

type Error struct {
	Code      string       `json:"code"`
	Message   string       `json:"message"`
	Details   []FieldError `json:"details,omitempty"`
	RequestID string       `json:"request_id"`
}

type ErrorEnvelope struct {
	Error Error `json:"error"`
}

func WriteJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", jsonContentType)
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func WriteError(w http.ResponseWriter, status int, code, message, requestID string, details []FieldError) {
	WriteJSON(w, status, ErrorEnvelope{Error: Error{Code: code, Message: message, Details: details, RequestID: requestID}})
}
