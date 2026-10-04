package branch

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

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

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	if principal.Role == "CASHIER" {
		if principal.BranchID == "" {
			h.writeError(w, r, ErrBranchRequired)
			return
		}
		b, err := h.service.GetByID(r.Context(), principal.BranchID)
		if err != nil {
			h.writeError(w, r, err)
			return
		}
		httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": []Branch{b}})
		return
	}

	branches, err := h.service.List(r.Context(), false)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": branches})
}

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanManageOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	var in CreateBranchInput
	if err := decodeJSON(r, &in); err != nil {
		h.writeError(w, r, ErrInvalidInput)
		return
	}

	b, err := h.service.Create(r.Context(), in)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusCreated, b)
}

func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanManageOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	id := r.PathValue("id")
	var in UpdateBranchInput
	if err := decodeJSON(r, &in); err != nil {
		h.writeError(w, r, ErrInvalidInput)
		return
	}

	b, err := h.service.Update(r.Context(), id, in)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, b)
}

func (h *Handler) AssignUser(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanManageOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	userID := r.PathValue("id")
	var in AssignUserBranchInput
	if err := decodeJSON(r, &in); err != nil || in.BranchID == "" {
		h.writeError(w, r, ErrInvalidInput)
		return
	}

	if err := h.service.AssignUserBranch(r.Context(), userID, in.BranchID); err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"status": "ok", "user_id": userID, "branch_id": in.BranchID})
}

func decodeJSON(r *http.Request, v any) error {
	d := json.NewDecoder(io.LimitReader(r.Body, (1<<20)+1))
	d.DisallowUnknownFields()
	if err := d.Decode(v); err != nil {
		return err
	}
	if err := d.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("multiple JSON values")
	}
	return nil
}

func (h *Handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	requestID := httpserver.RequestID(r.Context())
	status, code, message := http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred."
	switch {
	case errors.Is(err, customer.ErrUnauthorized):
		status, code, message = http.StatusForbidden, "FORBIDDEN", "Staff authorization required."
	case errors.Is(err, ErrNotFound):
		status, code, message = http.StatusNotFound, "NOT_FOUND", "Branch not found."
	case errors.Is(err, ErrDuplicateCode):
		status, code, message = http.StatusConflict, "DUPLICATE_CODE", "Branch code already exists."
	case errors.Is(err, ErrInvalidInput):
		status, code, message = http.StatusBadRequest, "INVALID_INPUT", "Invalid branch input."
	case errors.Is(err, ErrBranchRequired):
		status, code, message = http.StatusBadRequest, "BRANCH_REQUIRED", "Cabang aktif wajib dipilih."
	case errors.Is(err, ErrCrossBranch):
		status, code, message = http.StatusForbidden, "CROSS_BRANCH_FORBIDDEN", "Akses lintas cabang tidak diizinkan."
	}
	httpapi.WriteError(w, status, code, message, requestID, nil)
}
