package hermes

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

var (
	ErrUnauthorized = errors.New("unauthorized staff access")
	ErrBadRequest   = errors.New("bad request body")
)

// Handler manages staff HTTP endpoints for agent handoffs and automation pauses.
type Handler struct {
	service *Service
}

// NewHandler creates a new Hermes HTTP handler.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func staffPrincipal(r *http.Request) customer.Principal {
	p := customer.PrincipalFromRequest(r)
	if p.Subject != "" && (p.Role == "STAFF" || p.Role == "ADMIN") {
		return p
	}
	staffID := strings.TrimSpace(r.Header.Get("X-Staff-ID"))
	staffRole := strings.ToUpper(strings.TrimSpace(r.Header.Get("X-Staff-Role")))
	if staffID != "" && (staffRole == "STAFF" || staffRole == "ADMIN") {
		return customer.Principal{Subject: staffID, Role: staffRole}
	}
	return p
}

// ListHandoffs lists conversations currently needing staff intervention.
func (h *Handler) ListHandoffs(w http.ResponseWriter, r *http.Request) {
	p := staffPrincipal(r)
	if p.Subject == "" || (p.Role != "STAFF" && p.Role != "ADMIN") {
		h.writeError(w, r, ErrUnauthorized)
		return
	}

	q := r.URL.Query()
	limit, _ := strconv.Atoi(q.Get("limit"))
	offset, _ := strconv.Atoi(q.Get("offset"))

	filter := HandoffQueueFilter{
		Status:   q.Get("status"),
		Priority: q.Get("priority"),
		Limit:    limit,
		Offset:   offset,
	}

	items, total, err := h.service.ListHandoffQueue(r.Context(), filter)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	if items == nil {
		items = []HandoffQueueItem{}
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"data": items,
		"meta": map[string]any{
			"total":  total,
			"limit":  filter.Limit,
			"offset": filter.Offset,
		},
	})
}

// Pause pauses automation for a conversation.
func (h *Handler) Pause(w http.ResponseWriter, r *http.Request) {
	p := staffPrincipal(r)
	if p.Subject == "" || (p.Role != "STAFF" && p.Role != "ADMIN") {
		h.writeError(w, r, ErrUnauthorized)
		return
	}

	var body struct {
		Session       string `json:"session"`
		CustomerPhone string `json:"customer_phone"`
		Reason        string `json:"reason"`
	}
	if err := decodeBody(r, &body); err != nil {
		h.writeError(w, r, ErrBadRequest)
		return
	}
	if strings.TrimSpace(body.CustomerPhone) == "" || strings.TrimSpace(body.Reason) == "" {
		h.writeError(w, r, ErrBadRequest)
		return
	}

	session := strings.TrimSpace(body.Session)
	if session == "" {
		session = "default"
	}

	reqID := httpserver.RequestID(r.Context())
	state, err := h.service.PauseConversation(r.Context(), session, body.CustomerPhone, p.Subject, p.Role, body.Reason, reqID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": state})
}

// Resume unpauses automation for a conversation.
func (h *Handler) Resume(w http.ResponseWriter, r *http.Request) {
	p := staffPrincipal(r)
	if p.Subject == "" || (p.Role != "STAFF" && p.Role != "ADMIN") {
		h.writeError(w, r, ErrUnauthorized)
		return
	}

	var body struct {
		Session       string `json:"session"`
		CustomerPhone string `json:"customer_phone"`
		Reason        string `json:"reason"`
	}
	if err := decodeBody(r, &body); err != nil {
		h.writeError(w, r, ErrBadRequest)
		return
	}
	if strings.TrimSpace(body.CustomerPhone) == "" {
		h.writeError(w, r, ErrBadRequest)
		return
	}

	session := strings.TrimSpace(body.Session)
	if session == "" {
		session = "default"
	}

	reqID := httpserver.RequestID(r.Context())
	state, err := h.service.ResumeConversation(r.Context(), session, body.CustomerPhone, p.Subject, p.Role, body.Reason, reqID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": state})
}

// Assign assigns a staff member to handle a handoff.
func (h *Handler) Assign(w http.ResponseWriter, r *http.Request) {
	p := staffPrincipal(r)
	if p.Subject == "" || (p.Role != "STAFF" && p.Role != "ADMIN") {
		h.writeError(w, r, ErrUnauthorized)
		return
	}

	var body struct {
		Session       string `json:"session"`
		CustomerPhone string `json:"customer_phone"`
		AssignedTo    string `json:"assigned_to"`
	}
	if err := decodeBody(r, &body); err != nil {
		h.writeError(w, r, ErrBadRequest)
		return
	}
	if strings.TrimSpace(body.CustomerPhone) == "" || strings.TrimSpace(body.AssignedTo) == "" {
		h.writeError(w, r, ErrBadRequest)
		return
	}

	session := strings.TrimSpace(body.Session)
	if session == "" {
		session = "default"
	}

	reqID := httpserver.RequestID(r.Context())
	state, err := h.service.AssignConversation(r.Context(), session, body.CustomerPhone, p.Subject, p.Role, body.AssignedTo, reqID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": state})
}

// Resolve marks handoff as resolved, optionally resuming automation.
func (h *Handler) Resolve(w http.ResponseWriter, r *http.Request) {
	p := staffPrincipal(r)
	if p.Subject == "" || (p.Role != "STAFF" && p.Role != "ADMIN") {
		h.writeError(w, r, ErrUnauthorized)
		return
	}

	var body struct {
		Session          string `json:"session"`
		CustomerPhone    string `json:"customer_phone"`
		Resolution       string `json:"resolution"`
		ResumeAutomation bool   `json:"resume_automation"`
	}
	if err := decodeBody(r, &body); err != nil {
		h.writeError(w, r, ErrBadRequest)
		return
	}
	if strings.TrimSpace(body.CustomerPhone) == "" || strings.TrimSpace(body.Resolution) == "" {
		h.writeError(w, r, ErrBadRequest)
		return
	}

	session := strings.TrimSpace(body.Session)
	if session == "" {
		session = "default"
	}

	reqID := httpserver.RequestID(r.Context())
	state, err := h.service.ResolveConversation(r.Context(), session, body.CustomerPhone, p.Subject, p.Role, body.Resolution, body.ResumeAutomation, reqID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": state})
}

// GetAuditLogs returns the audit trail for a conversation.
func (h *Handler) GetAuditLogs(w http.ResponseWriter, r *http.Request) {
	p := staffPrincipal(r)
	if p.Subject == "" || (p.Role != "STAFF" && p.Role != "ADMIN") {
		h.writeError(w, r, ErrUnauthorized)
		return
	}

	convID := r.PathValue("id")
	if strings.TrimSpace(convID) == "" {
		h.writeError(w, r, ErrBadRequest)
		return
	}

	logs, err := h.service.GetAuditLogs(r.Context(), convID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	if logs == nil {
		logs = []ConversationAuditEvent{}
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": logs})
}

func decodeBody(r *http.Request, dest any) error {
	d := json.NewDecoder(io.LimitReader(r.Body, (1<<20)+1))
	d.DisallowUnknownFields()
	if err := d.Decode(dest); err != nil {
		return err
	}
	return nil
}

func (h *Handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	status := http.StatusInternalServerError
	code := "INTERNAL_ERROR"
	message := "An unexpected error occurred."

	switch {
	case errors.Is(err, ErrUnauthorized):
		status = http.StatusForbidden
		code = "FORBIDDEN"
		message = "Staff authorization required."
	case errors.Is(err, ErrBadRequest):
		status = http.StatusBadRequest
		code = "INVALID_REQUEST"
		message = "Invalid request payload."
	case errors.Is(err, ErrConversationNotFound):
		status = http.StatusNotFound
		code = "CONVERSATION_NOT_FOUND"
		message = "Conversation not found."
	}

	httpapi.WriteError(w, status, code, message, httpserver.RequestID(r.Context()), nil)
}
