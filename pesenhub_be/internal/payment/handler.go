package payment

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

type Handler struct{ service *Service }

func NewHandler(service *Service) *Handler { return &Handler{service: service} }

func (h *Handler) RecordCash(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if principal.Subject == "" || principal.Role != "STAFF" {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	var in CashInput
	d := json.NewDecoder(io.LimitReader(r.Body, (1<<20)+1))
	d.DisallowUnknownFields()
	if d.Decode(&in) != nil {
		h.writeError(w, r, ErrMalformedInput)
		return
	}
	if err := d.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		h.writeError(w, r, ErrMalformedInput)
		return
	}
	p, created, err := h.service.RecordCash(r.Context(), principal, r.PathValue("id"), in, r.Header.Get("Idempotency-Key"), httpserver.RequestID(r.Context()))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	status := http.StatusOK
	if created {
		status = http.StatusCreated
		w.Header().Set("Location", "/api/v1/payments/"+p.ID)
	}
	httpapi.WriteJSON(w, status, p)
}

func (h *Handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	status, code, message := http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred."
	var details []httpapi.FieldError
	switch {
	case errors.Is(err, ErrMalformedInput):
		status, code, message = 400, "INVALID_REQUEST", "Request body is malformed or contains unknown fields."
	case errors.Is(err, customer.ErrUnauthorized):
		status, code, message = 403, "FORBIDDEN", "Cash payment recording requires staff authorization."
	case errors.Is(err, ErrOrderNotFound):
		status, code, message = 404, "ORDER_NOT_FOUND", "Order was not found."
	case errors.Is(err, ErrAmountMismatch):
		status, code, message = 422, "AMOUNT_MISMATCH", "Payment amount must equal the order total."
	case errors.Is(err, ErrOrderNotPayable):
		status, code, message = 409, "ORDER_NOT_PAYABLE", "Rejected or cancelled orders cannot be paid."
	case errors.Is(err, ErrIdempotencyConflict):
		status, code, message = 409, "IDEMPOTENCY_CONFLICT", "Idempotency key conflicts with an existing payment."
	case errors.Is(err, ErrInvalidInput):
		status, code, message = 422, "VALIDATION_FAILED", "Payment validation failed."
	}
	var validation *ValidationError
	if errors.As(err, &validation) {
		details = []httpapi.FieldError{{Field: validation.Field, Reason: validation.Reason}}
	}
	httpapi.WriteError(w, status, code, message, httpserver.RequestID(r.Context()), details)
}
