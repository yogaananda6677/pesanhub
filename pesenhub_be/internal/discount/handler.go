package discount

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

type Handler struct {
	store *Store
}

func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	filter := DiscountFilter{
		Channel:  r.URL.Query().Get("channel"),
		BranchID: r.URL.Query().Get("branch_id"),
		Scope:    r.URL.Query().Get("scope"),
		Query:    r.URL.Query().Get("q"),
	}

	if r.URL.Query().Get("active_only") == "true" {
		filter.ActiveOnly = true
	}

	if principal.Role == "CASHIER" && filter.BranchID == "" && principal.BranchID != "" {
		filter.BranchID = principal.BranchID
	}

	discounts, err := h.store.List(r.Context(), filter)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	if discounts == nil {
		discounts = []Discount{}
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": discounts})
}

func (h *Handler) Applicable(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	branchID := r.URL.Query().Get("branch_id")
	if branchID == "" && principal.Role == "CASHIER" && principal.BranchID != "" {
		branchID = principal.BranchID
	}

	channel := r.URL.Query().Get("channel")
	if channel == "" {
		channel = ChannelOffline
	}

	var subtotal int64
	if subStr := r.URL.Query().Get("subtotal"); subStr != "" {
		if val, err := strconv.ParseInt(subStr, 10, 64); err == nil {
			subtotal = val
		}
	}

	discounts, err := h.store.GetApplicableDiscounts(r.Context(), branchID, channel, subtotal)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	if discounts == nil {
		discounts = []Discount{}
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": discounts})
}

func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	id := r.PathValue("id")
	d, err := h.store.GetByID(r.Context(), id)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": d})
}

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanManageOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	var in CreateDiscountInput
	if err := decodeJSON(r, &in); err != nil {
		h.writeError(w, r, ErrInvalidInput)
		return
	}

	d, err := h.store.Create(r.Context(), in)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusCreated, map[string]any{"data": d})
}

func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanManageOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	id := r.PathValue("id")
	var in UpdateDiscountInput
	if err := decodeJSON(r, &in); err != nil {
		h.writeError(w, r, ErrInvalidInput)
		return
	}

	d, err := h.store.Update(r.Context(), id, in)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": d})
}

func (h *Handler) ToggleActive(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanManageOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	id := r.PathValue("id")
	d, err := h.store.ToggleActive(r.Context(), id)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": d})
}

func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanManageOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	id := r.PathValue("id")
	if err := h.store.Delete(r.Context(), id); err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"status": "deleted", "id": id})
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
	case errors.Is(err, ErrDiscountNotFound):
		status, code, message = http.StatusNotFound, "NOT_FOUND", "Discount not found."
	case errors.Is(err, ErrVersionConflict):
		status, code, message = http.StatusConflict, "VERSION_CONFLICT", "Discount was modified by another request."
	case errors.Is(err, ErrInvalidInput):
		status, code, message = http.StatusBadRequest, "INVALID_INPUT", err.Error()
	default:
		if strings.Contains(err.Error(), "Duplicate entry") {
			status, code, message = http.StatusConflict, "DUPLICATE_CODE", "Kode promo sudah digunakan."
		} else {
			message = err.Error()
		}
	}
	httpapi.WriteError(w, status, code, message, requestID, nil)
}
