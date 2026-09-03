package order

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

type Handler struct{ service *Service }

func NewHandler(s *Service) *Handler { return &Handler{service: s} }
func (h *Handler) CreateManual(w http.ResponseWriter, r *http.Request) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" || p.Role != "STAFF" {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	var in CreateInput
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
	o, created, err := h.service.CreateManual(r.Context(), in, r.Header.Get("Idempotency-Key"), p.Subject, httpserver.RequestID(r.Context()))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	status := http.StatusOK
	if created {
		status = http.StatusCreated
		w.Header().Set("Location", "/api/v1/orders/"+o.ID)
	}
	httpapi.WriteJSON(w, status, o)
}
func (h *Handler) TransitionStatus(w http.ResponseWriter, r *http.Request) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" || p.Role != "STAFF" {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	var in TransitionInput
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
	result, _, err := h.service.Transition(r.Context(), r.PathValue("id"), in, r.Header.Get("Idempotency-Key"), p.Subject, p.Role, httpserver.RequestID(r.Context()))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, result)
}
func (h *Handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	status, code, message := http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred."
	details := []httpapi.FieldError(nil)
	switch {
	case errors.Is(err, ErrMalformedInput):
		status, code, message = http.StatusBadRequest, "INVALID_REQUEST", "Request body is malformed or contains unknown fields."
	case errors.Is(err, customer.ErrUnauthorized):
		status, code, message = http.StatusForbidden, "FORBIDDEN", "Manual order creation requires staff authorization."
	case errors.Is(err, ErrIdempotencyConflict):
		status, code, message = http.StatusConflict, "IDEMPOTENCY_CONFLICT", "Idempotency key was already used with a different request."
	case errors.Is(err, ErrVersionConflict):
		status, code, message = http.StatusConflict, "VERSION_CONFLICT", "Order was modified by another request."
	case errors.Is(err, ErrInvalidTransition):
		status, code, message = http.StatusConflict, "INVALID_STATUS_TRANSITION", "Order status transition is not allowed."
	case errors.Is(err, ErrNotFound):
		status, code, message = http.StatusNotFound, "ORDER_NOT_FOUND", "Order was not found."
	case errors.Is(err, ErrInvalidInput), errors.Is(err, catalog.ErrInvalidModifier):
		status, code, message = http.StatusUnprocessableEntity, "VALIDATION_FAILED", "Order validation failed."
	case errors.Is(err, catalog.ErrUnavailable):
		status, code, message = http.StatusConflict, "CATALOG_UNAVAILABLE", "Menu or modifier is unavailable."
	}
	var validation *ValidationError
	if errors.As(err, &validation) {
		details = []httpapi.FieldError{{Field: validation.Field, Reason: "invalid"}}
	}
	var cv *catalog.ValidationError
	if errors.As(err, &cv) {
		details = []httpapi.FieldError{{Field: cv.Field, Reason: "invalid_selection"}}
	}
	httpapi.WriteError(w, status, code, message, httpserver.RequestID(r.Context()), details)
}
