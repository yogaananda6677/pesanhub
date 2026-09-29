package superadmin

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"strconv"
	"sync"
	"time"

	"pesenhub/backend/internal/appauth"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

type AuthStore interface {
	EnsureSuperadmin(ctx context.Context, defaultEmail, defaultName string) (appauth.User, error)
	CreateSession(ctx context.Context, sessionID, userID string, expiresAt time.Time) error
}

type SessionIssuer interface {
	IssuePersistent(subject, role string) (token, sessionID string, expiresAt time.Time, err error)
}

type AuthConfig struct {
	Username string
	Password string
}

type Handler struct {
	service    *Service
	authConfig AuthConfig
	authStore  AuthStore
	sessions   SessionIssuer
	limiter    *loginLimiter
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) SetAuth(cfg AuthConfig, store AuthStore, sessions SessionIssuer) {
	h.authConfig = cfg
	h.authStore = store
	h.sessions = sessions
	if h.limiter == nil {
		h.limiter = newLoginLimiter(5, time.Minute)
	}
}

type loginWindow struct {
	started time.Time
	count   int
}

type loginLimiter struct {
	mu     sync.Mutex
	items  map[string]loginWindow
	limit  int
	window time.Duration
	now    func() time.Time
}

func newLoginLimiter(limit int, window time.Duration) *loginLimiter {
	return &loginLimiter{items: make(map[string]loginWindow), limit: limit, window: window, now: time.Now}
}

func (l *loginLimiter) Allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	if len(l.items) >= 4096 {
		for candidate, window := range l.items {
			if now.Sub(window.started) >= l.window {
				delete(l.items, candidate)
			}
		}
		if _, known := l.items[key]; !known && len(l.items) >= 4096 {
			return false
		}
	}
	entry := l.items[key]
	if entry.started.IsZero() || now.Sub(entry.started) >= l.window {
		l.items[key] = loginWindow{started: now, count: 1}
		return true
	}
	entry.count++
	l.items[key] = entry
	return entry.count <= l.limit
}

func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil && host != "" {
		return host
	}
	return r.RemoteAddr
}

func (h *Handler) requireSuperadmin(w http.ResponseWriter, r *http.Request) (customer.Principal, bool) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" || p.Role != "SUPERADMIN" {
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Superadmin authorization required.", httpserver.RequestID(r.Context()), nil)
		return customer.Principal{}, false
	}
	return p, true
}

func (h *Handler) requireAdmin(w http.ResponseWriter, r *http.Request) (customer.Principal, bool) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" || p.Role != "ADMIN" {
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Admin authorization required.", httpserver.RequestID(r.Context()), nil)
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
	case errors.Is(err, ErrInvitationDelivery):
		status, code, message = http.StatusServiceUnavailable, "INVITATION_EMAIL_FAILED", "Invitation was saved, but its email could not be delivered. Retry after checking the Gmail configuration."
	}

	httpapi.WriteError(w, status, code, message, reqID, nil)
}

// POST /api/v1/admin/cashiers/invitations
func (h *Handler) InviteCashier(w http.ResponseWriter, r *http.Request) {
	actor, ok := h.requireAdmin(w, r)
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
		if errors.Is(err, ErrInvitationDelivery) || errors.Is(err, ErrUserAlreadyExists) || errors.Is(err, ErrInvitationExists) {
			h.writeError(w, r, err)
			return
		}
		httpapi.WriteError(w, http.StatusUnprocessableEntity, "VALIDATION_FAILED", err.Error(), httpserver.RequestID(r.Context()), nil)
		return
	}
	httpapi.WriteJSON(w, http.StatusCreated, invitation)
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

// POST /api/v1/superadmin/login
func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	reqID := httpserver.RequestID(r.Context())
	if h.limiter != nil && !h.limiter.Allow(clientIP(r)) {
		w.Header().Set("Retry-After", "60")
		httpapi.WriteError(w, http.StatusTooManyRequests, "RATE_LIMITED", "Too many login attempts. Try again shortly.", reqID, nil)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := decode(r, &body); err != nil || len(body.Username) > 128 || len(body.Password) > 1024 {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_REQUEST", "Login request is invalid.", reqID, nil)
		return
	}

	expectedUser := sha256.Sum256([]byte(h.authConfig.Username))
	givenUser := sha256.Sum256([]byte(body.Username))
	userOK := subtle.ConstantTimeCompare(expectedUser[:], givenUser[:]) == 1

	expectedPass := sha256.Sum256([]byte(h.authConfig.Password))
	givenPass := sha256.Sum256([]byte(body.Password))
	passOK := subtle.ConstantTimeCompare(expectedPass[:], givenPass[:]) == 1

	if !userOK || !passOK || h.authConfig.Username == "" || h.authConfig.Password == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Username or password is incorrect.", reqID, nil)
		return
	}

	if h.authStore == nil || h.sessions == nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Authentication configuration not initialized.", reqID, nil)
		return
	}

	user, err := h.authStore.EnsureSuperadmin(r.Context(), "superadmin@pesenhub.id", "Superadmin")
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to ensure superadmin account.", reqID, nil)
		return
	}

	token, sessionID, expiresAt, err := h.sessions.IssuePersistent(user.ID, string(appauth.RoleSuperadmin))
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to issue session.", reqID, nil)
		return
	}

	if err := h.authStore.CreateSession(r.Context(), sessionID, user.ID, expiresAt); err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to record session.", reqID, nil)
		return
	}

	w.Header().Set("Cache-Control", "no-store")
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"access_token": token,
		"token_type":   "Bearer",
		"expires_at":   expiresAt,
		"user": map[string]any{
			"id":           user.ID,
			"email":        user.EmailMasked,
			"display_name": user.DisplayName,
			"role":         user.Role,
			"status":       user.Status,
		},
	})
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

// GET /api/v1/superadmin/users/{id}/whatsapp
func (h *Handler) UserWhatsAppStatus(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.requireSuperadmin(w, r); !ok {
		return
	}
	userID := r.PathValue("id")
	status, err := h.service.GetUserWhatsAppStatus(r.Context(), userID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, status)
}

// GET /api/v1/superadmin/whatsapp/status
func (h *Handler) WhatsAppOverview(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.requireSuperadmin(w, r); !ok {
		return
	}
	statuses, err := h.service.ListWhatsAppAccountStatuses(r.Context())
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	if statuses == nil {
		statuses = []WhatsAppAccountStatus{}
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"accounts": statuses,
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
