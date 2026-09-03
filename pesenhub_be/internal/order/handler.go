package order

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
	"pesenhub/backend/internal/ws"
)

type Handler struct {
	service *Service
	hub     *ws.Hub
}

func NewHandler(s *Service, hub ...*ws.Hub) *Handler {
	h := &Handler{service: s}
	if len(hub) > 0 {
		h.hub = hub[0]
	}
	return h
}

func (h *Handler) SetHub(hub *ws.Hub) {
	h.hub = hub
}
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

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" || (p.Role != "STAFF" && p.Role != "KDS") {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	pagination, err := httpapi.ParsePagination(r.URL.Query(), map[string]struct{}{"created_at": {}}, "created_at")
	if err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_QUERY", "Query parameter validation failed.", httpserver.RequestID(r.Context()), nil)
		return
	}

	filter := OrderFilter{
		Pagination: pagination,
	}

	for _, raw := range r.URL.Query()["status"] {
		for _, s := range strings.Split(raw, ",") {
			s = strings.TrimSpace(s)
			if s != "" {
				filter.Statuses = append(filter.Statuses, s)
			}
		}
	}

	for _, raw := range r.URL.Query()["source"] {
		for _, s := range strings.Split(raw, ",") {
			s = strings.TrimSpace(s)
			if s != "" {
				filter.Sources = append(filter.Sources, s)
			}
		}
	}

	if raw := r.URL.Query().Get("created_from"); raw != "" {
		t, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			h.writeError(w, r, &ValidationError{Field: "created_from"})
			return
		}
		filter.CreatedFrom = &t
	}

	if raw := r.URL.Query().Get("created_to"); raw != "" {
		t, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			h.writeError(w, r, &ValidationError{Field: "created_to"})
			return
		}
		filter.CreatedTo = &t
	}

	res, err := h.service.List(r.Context(), p, filter)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, res)
}

func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" || (p.Role != "STAFF" && p.Role != "KDS") {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	res, err := h.service.GetByID(r.Context(), p, r.PathValue("id"))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, res)
}

func (h *Handler) Queue(w http.ResponseWriter, r *http.Request) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" || (p.Role != "STAFF" && p.Role != "KDS") {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	res, err := h.service.QueueSnapshot(r.Context(), p)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": res})
}

func (h *Handler) WS(w http.ResponseWriter, r *http.Request) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" {
		if token := r.URL.Query().Get("token"); token != "" {
			if strings.HasPrefix(token, "kds") {
				p = customer.Principal{Subject: token, Role: "KDS"}
			} else if strings.HasPrefix(token, "staff") {
				p = customer.Principal{Subject: token, Role: "STAFF"}
			}
		}
	}

	if p.Subject == "" || (p.Role != "STAFF" && p.Role != "KDS") {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	if h.hub == nil {
		http.Error(w, "websocket hub unavailable", http.StatusServiceUnavailable)
		return
	}

	conn, err := ws.Upgrade(w, r)
	if err != nil {
		h.writeError(w, r, ErrMalformedInput)
		return
	}

	client := ws.NewClient(h.hub, conn, p.Role, p.Subject)
	h.hub.Register(client)

	go client.WritePump(15 * time.Second)
	client.ReadPump()
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
