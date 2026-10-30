package shift

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"pesenhub/backend/internal/branch"
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

func (h *Handler) Open(w http.ResponseWriter, r *http.Request) {
	reqID := httpserver.RequestID(r.Context())
	p := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(p) {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Akses ditolak.", reqID, nil)
		return
	}

	var req OpenShiftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && err.Error() != "EOF" {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_REQUEST", "Format payload JSON tidak valid.", reqID, nil)
		return
	}

	scope := branch.ScopeFromContext(r.Context())
	if req.BranchID == "" && !scope.All && scope.BranchID != "" {
		req.BranchID = scope.BranchID
	}

	res, err := h.service.OpenShift(r.Context(), p, req)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusCreated, ShiftResponse{Shift: res})
}

func (h *Handler) Close(w http.ResponseWriter, r *http.Request) {
	reqID := httpserver.RequestID(r.Context())
	p := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(p) {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Akses ditolak.", reqID, nil)
		return
	}

	var req CloseShiftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_REQUEST", "Format payload JSON tidak valid.", reqID, nil)
		return
	}

	res, err := h.service.CloseShift(r.Context(), p, req)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, ShiftResponse{Shift: res})
}

func (h *Handler) Current(w http.ResponseWriter, r *http.Request) {
	reqID := httpserver.RequestID(r.Context())
	p := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(p) {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Akses ditolak.", reqID, nil)
		return
	}

	scope := branch.ScopeFromContext(r.Context())
	requestedBranch := strings.TrimSpace(r.URL.Query().Get("branch_id"))
	if requestedBranch == "" && !scope.All && scope.BranchID != "" {
		requestedBranch = scope.BranchID
	}

	res, err := h.service.GetCurrentShift(r.Context(), p, requestedBranch)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	if res == nil {
		httpapi.WriteJSON(w, http.StatusOK, map[string]any{"shift": nil})
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, ShiftResponse{Shift: *res})
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	reqID := httpserver.RequestID(r.Context())
	p := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(p) {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Akses ditolak.", reqID, nil)
		return
	}

	scope := branch.ScopeFromContext(r.Context())
	requestedBranch := strings.TrimSpace(r.URL.Query().Get("branch_id"))
	if requestedBranch == "" && !scope.All && scope.BranchID != "" {
		requestedBranch = scope.BranchID
	}

	limit := 20
	if rawLimit := strings.TrimSpace(r.URL.Query().Get("limit")); rawLimit != "" {
		if parsed, err := strconv.Atoi(rawLimit); err == nil && parsed > 0 && parsed <= 100 {
			limit = parsed
		}
	}

	list, err := h.service.ListShifts(r.Context(), p, requestedBranch, limit)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, ShiftListResponse{Shifts: list})
}

func (h *Handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	reqID := httpserver.RequestID(r.Context())
	switch {
	case errors.Is(err, ErrUnauthorized):
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Akses ditolak.", reqID, nil)
	case errors.Is(err, ErrInvalidAmount):
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_AMOUNT", err.Error(), reqID, nil)
	case errors.Is(err, ErrInvalidBranch):
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_BRANCH", "Cabang tidak valid atau tidak ditemukan.", reqID, nil)
	case errors.Is(err, ErrShiftAlreadyOpen):
		httpapi.WriteError(w, http.StatusConflict, "SHIFT_ALREADY_OPEN", "Shift kasir sedang aktif pada cabang ini.", reqID, nil)
	case errors.Is(err, ErrShiftNotFound), errors.Is(err, ErrNoActiveShift):
		httpapi.WriteError(w, http.StatusNotFound, "SHIFT_NOT_FOUND", "Shift kasir aktif tidak ditemukan.", reqID, nil)
	case errors.Is(err, ErrShiftAlreadyClosed):
		httpapi.WriteError(w, http.StatusBadRequest, "SHIFT_ALREADY_CLOSED", "Shift kasir telah ditutup sebelumnya.", reqID, nil)
	default:
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Terjadi kesalahan internal pada server.", reqID, nil)
	}
}
