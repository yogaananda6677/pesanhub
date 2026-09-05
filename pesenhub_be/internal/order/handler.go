package order

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
	"pesenhub/backend/internal/ws"
)

type ipRateLimiter struct {
	mu     sync.Mutex
	limits map[string][]time.Time
	limit  int
	window time.Duration
}

func newIPRateLimiter(limit int, window time.Duration) *ipRateLimiter {
	return &ipRateLimiter{
		limits: make(map[string][]time.Time),
		limit:  limit,
		window: window,
	}
}

func (l *ipRateLimiter) Allow(ip string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := time.Now()
	cutoff := now.Add(-l.window)

	timestamps := l.limits[ip]
	valid := timestamps[:0]
	for _, t := range timestamps {
		if t.After(cutoff) {
			valid = append(valid, t)
		}
	}

	if len(valid) >= l.limit {
		l.limits[ip] = valid
		return false
	}

	l.limits[ip] = append(valid, now)
	return true
}

type Handler struct {
	service *Service
	hub     *ws.Hub
	limiter *ipRateLimiter
}

func NewHandler(s *Service, hub ...*ws.Hub) *Handler {
	h := &Handler{
		service: s,
		limiter: newIPRateLimiter(60, time.Minute),
	}
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

func (h *Handler) PreviewWeb(w http.ResponseWriter, r *http.Request) {
	var in PreviewInput
	dec := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&in); err != nil {
		h.writeError(w, r, ErrMalformedInput)
		return
	}
	res, err := h.service.PreviewWeb(r.Context(), in.Items)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": res})
}

func (h *Handler) CreateWeb(w http.ResponseWriter, r *http.Request) {
	clientIP := r.RemoteAddr
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		clientIP = strings.Split(fwd, ",")[0]
	}
	if h.limiter != nil && !h.limiter.Allow(strings.TrimSpace(clientIP)) {
		httpapi.WriteError(w, http.StatusTooManyRequests, "RATE_LIMITED", "Too many requests, please slow down.", httpserver.RequestID(r.Context()), nil)
		return
	}

	var in PublicOrderCreateInput
	dec := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&in); err != nil {
		h.writeError(w, r, ErrMalformedInput)
		return
	}

	idempotencyKey := r.Header.Get("Idempotency-Key")
	if idempotencyKey == "" {
		idempotencyKey = r.Header.Get("X-Idempotency-Key")
	}

	res, isNew, err := h.service.CreateWeb(r.Context(), in, idempotencyKey, httpserver.RequestID(r.Context()))
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	status := http.StatusCreated
	if !isNew {
		status = http.StatusOK
	}
	httpapi.WriteJSON(w, status, map[string]any{"data": res})
}

func (h *Handler) GetByPublicToken(w http.ResponseWriter, r *http.Request) {
	token := r.PathValue("token")
	if token == "" {
		h.writeError(w, r, ErrNotFound)
		return
	}

	res, err := h.service.GetByPublicToken(r.Context(), token)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": res})
}

func (h *Handler) GetAuditLogs(w http.ResponseWriter, r *http.Request) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" || p.Role != "STAFF" {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	orderID := r.PathValue("id")
	if orderID == "" {
		h.writeError(w, r, ErrNotFound)
		return
	}

	entries, err := h.service.GetAuditLogs(r.Context(), orderID, p, httpserver.RequestID(r.Context()))
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": entries})
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
		reason := validation.Reason
		if reason == "" {
			reason = "invalid"
		}
		details = []httpapi.FieldError{{Field: validation.Field, Reason: reason}}
	}
	var cv *catalog.ValidationError
	if errors.As(err, &cv) {
		details = []httpapi.FieldError{{Field: cv.Field, Reason: "invalid_selection"}}
	}
	httpapi.WriteError(w, status, code, message, httpserver.RequestID(r.Context()), details)
}
