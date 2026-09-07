package superadmin

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"

	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) requireSuperadmin(w http.ResponseWriter, r *http.Request) (customer.Principal, bool) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" || p.Role != "SUPERADMIN" {
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Superadmin authorization required.", httpserver.RequestID(r.Context()), nil)
		return customer.Principal{}, false
	}
	return p, true
}

func (h *Handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	reqID := httpserver.RequestID(r.Context())
	status, code, message := http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred."

	switch {
	case errors.Is(err, ErrUserNotFound):
		status, code, message = http.StatusNotFound, "USER_NOT_FOUND", "User not found."
	case errors.Is(err, ErrInvitationNotFound):
		status, code, message = http.StatusNotFound, "INVITATION_NOT_FOUND", "Invitation not found."
	case errors.Is(err, ErrUserAlreadyExists):
		status, code, message = http.StatusConflict, "USER_ALREADY_EXISTS", "A user with this email address already exists."
	case errors.Is(err, ErrInvitationExists):
		status, code, message = http.StatusConflict, "INVITATION_ALREADY_EXISTS", "An active invitation for this email already exists."
	case errors.Is(err, ErrInvalidStatusAction):
		status, code, message = http.StatusConflict, "INVALID_STATUS_ACTION", "Invalid status transition for current user state."
	}

	httpapi.WriteError(w, status, code, message, reqID, nil)
}

func decode(r *http.Request, v any) error {
	if r.Body == nil {
		return nil
	}
	d := json.NewDecoder(io.LimitReader(r.Body, (1<<20)+1))
	if err := d.Decode(v); err != nil && !errors.Is(err, io.EOF) {
		return err
	}
	return nil
}

func parsePagination(r *http.Request) (limit, offset int) {
	limit = 50
	offset = 0
	if l := r.URL.Query().Get("limit"); l != "" {
		if val, err := strconv.Atoi(l); err == nil && val > 0 && val <= 100 {
			limit = val
		}
	}
	if o := r.URL.Query().Get("offset"); o != "" {
		if val, err := strconv.Atoi(o); err == nil && val >= 0 {
			offset = val
		}
	}
	return limit, offset
}

// GET /api/v1/superadmin/health/snapshot
func (h *Handler) HealthSnapshot(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.requireSuperadmin(w, r); !ok {
		return
	}
	snapshot, err := h.service.GetSystemHealth(r.Context())
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, snapshot)
}

// GET /api/v1/superadmin/telemetry/traffic
func (h *Handler) TrafficTelemetry(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.requireSuperadmin(w, r); !ok {
		return
	}
	timeRange := r.URL.Query().Get("range")
	metrics, err := h.service.GetTraffic(r.Context(), timeRange)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, metrics)
}

// GET /api/v1/superadmin/users
func (h *Handler) ListUsers(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.requireSuperadmin(w, r); !ok {
		return
	}
	status := Status(r.URL.Query().Get("status"))
	search := r.URL.Query().Get("q")
	limit, offset := parsePagination(r)

	users, err := h.service.ListUsers(r.Context(), status, search, limit, offset)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	if users == nil {
		users = []UserSummary{}
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"data":   users,
		"limit":  limit,
		"offset": offset,
	})
}

// GET /api/v1/superadmin/users/invitations
func (h *Handler) ListInvitations(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.requireSuperadmin(w, r); !ok {
		return
	}
	limit, offset := parsePagination(r)
	invitations, err := h.service.ListInvitations(r.Context(), limit, offset)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	if invitations == nil {
		invitations = []Invitation{}
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"data":   invitations,
		"limit":  limit,
		"offset": offset,
	})
}

// POST /api/v1/superadmin/users/invite
func (h *Handler) Invite(w http.ResponseWriter, r *http.Request) {
	actor, ok := h.requireSuperadmin(w, r)
	if !ok {
		return
	}

	var body InviteRequest
	if err := decode(r, &body); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "Invalid JSON request body.", httpserver.RequestID(r.Context()), nil)
		return
	}

	invitation, err := h.service.InviteUser(r.Context(), actor.Subject, body.Email, body.OutletName)
	if err != nil {
		if errors.Is(err, ErrUserAlreadyExists) || errors.Is(err, ErrInvitationExists) {
			h.writeError(w, r, err)
			return
		}
		httpapi.WriteError(w, http.StatusUnprocessableEntity, "VALIDATION_FAILED", err.Error(), httpserver.RequestID(r.Context()), nil)
		return
	}

	httpapi.WriteJSON(w, http.StatusCreated, invitation)
}

// DELETE /api/v1/superadmin/users/invitations/{id}
func (h *Handler) RevokeInvitation(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.requireSuperadmin(w, r); !ok {
		return
	}

	id := r.PathValue("id")
	if err := h.service.RevokeInvitation(r.Context(), id); err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"id":     id,
		"status": "REVOKED",
	})
}

// POST /api/v1/superadmin/users/{id}/approve
func (h *Handler) Approve(w http.ResponseWriter, r *http.Request) {
	actor, ok := h.requireSuperadmin(w, r)
	if !ok {
		return
	}

	id := r.PathValue("id")
	var body StatusChangeRequest
	_ = decode(r, &body)

	if err := h.service.ApproveUser(r.Context(), actor.Subject, id, body.Reason, httpserver.RequestID(r.Context())); err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"id":     id,
		"status": string(StatusApproved),
	})
}

// POST /api/v1/superadmin/users/{id}/reject
func (h *Handler) Reject(w http.ResponseWriter, r *http.Request) {
	actor, ok := h.requireSuperadmin(w, r)
	if !ok {
		return
	}

	id := r.PathValue("id")
	var body StatusChangeRequest
	_ = decode(r, &body)

	if err := h.service.RejectUser(r.Context(), actor.Subject, id, body.Reason, httpserver.RequestID(r.Context())); err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"id":     id,
		"status": string(StatusRejected),
	})
}

// POST /api/v1/superadmin/users/{id}/suspend
func (h *Handler) Suspend(w http.ResponseWriter, r *http.Request) {
	actor, ok := h.requireSuperadmin(w, r)
	if !ok {
		return
	}

	id := r.PathValue("id")
	var body StatusChangeRequest
	_ = decode(r, &body)

	if err := h.service.SuspendUser(r.Context(), actor.Subject, id, body.Reason, httpserver.RequestID(r.Context())); err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"id":     id,
		"status": string(StatusSuspended),
	})
}

// POST /api/v1/superadmin/users/{id}/reactivate
func (h *Handler) Reactivate(w http.ResponseWriter, r *http.Request) {
	actor, ok := h.requireSuperadmin(w, r)
	if !ok {
		return
	}

	id := r.PathValue("id")
	var body StatusChangeRequest
	_ = decode(r, &body)

	if err := h.service.ReactivateUser(r.Context(), actor.Subject, id, body.Reason, httpserver.RequestID(r.Context())); err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"id":     id,
		"status": string(StatusApproved),
	})
}

// POST /api/v1/superadmin/users/{id}/revoke-sessions
func (h *Handler) RevokeSessions(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.requireSuperadmin(w, r); !ok {
		return
	}

	id := r.PathValue("id")
	if err := h.service.RevokeSessions(r.Context(), id); err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"id":      id,
		"revoked": true,
	})
}

// GET /api/v1/superadmin/audits
func (h *Handler) ListAudits(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.requireSuperadmin(w, r); !ok {
		return
	}

	targetUserID := r.URL.Query().Get("target_user_id")
	limit, offset := parsePagination(r)

	audits, err := h.service.ListAudits(r.Context(), targetUserID, limit, offset)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	if audits == nil {
		audits = []AuditEntry{}
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"data":   audits,
		"limit":  limit,
		"offset": offset,
	})
}
