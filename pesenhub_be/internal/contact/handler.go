package contact

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

	limit := 100
	if limitStr := r.URL.Query().Get("limit"); limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 {
			limit = l
		}
	}

	filter := ListFilter{
		BranchID:    r.URL.Query().Get("branch_id"),
		ContactType: r.URL.Query().Get("type"),
		Search:      r.URL.Query().Get("q"),
		Limit:       limit,
	}

	if principal.Role == "CASHIER" && filter.BranchID == "" && principal.BranchID != "" {
		filter.BranchID = principal.BranchID
	}

	contacts, err := h.store.List(r.Context(), filter)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	if contacts == nil {
		contacts = []Contact{}
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": contacts})
}

func (h *Handler) Upsert(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	var in UpsertContactInput
	if err := decodeJSON(r, &in); err != nil {
		h.writeError(w, r, ErrInvalidInput)
		return
	}

	if in.BranchID == "" && principal.BranchID != "" {
		in.BranchID = principal.BranchID
	}

	contact, err := h.store.Upsert(r.Context(), in)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, contact)
}

func (h *Handler) ToggleReply(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	id := r.PathValue("id")
	if strings.TrimSpace(id) == "" {
		h.writeError(w, r, ErrInvalidInput)
		return
	}

	var in ToggleReplyInput
	if err := decodeJSON(r, &in); err != nil {
		h.writeError(w, r, ErrInvalidInput)
		return
	}

	contact, err := h.store.ToggleAutoReply(r.Context(), id, in.AutoReplyEnabled)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, contact)
}

func (h *Handler) MarkNonCustomer(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	id := r.PathValue("id")
	if strings.TrimSpace(id) == "" {
		h.writeError(w, r, ErrInvalidInput)
		return
	}

	var in MarkNonCustomerInput
	_ = decodeJSON(r, &in) // optional body

	contact, err := h.store.MarkAsNonCustomer(r.Context(), id, in.ContactType, in.Notes)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, contact)
}

func (h *Handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	requestID := httpserver.RequestID(r.Context())
	status, code, message := http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred."

	switch {
	case errors.Is(err, customer.ErrUnauthorized):
		status, code, message = http.StatusForbidden, "FORBIDDEN", "Staff authorization required."
	case errors.Is(err, customer.ErrUnauthenticated):
		status, code, message = http.StatusUnauthorized, "UNAUTHENTICATED", "Authentication required."
	case errors.Is(err, ErrContactNotFound):
		status, code, message = http.StatusNotFound, "NOT_FOUND", "Contact not found."
	case errors.Is(err, ErrInvalidInput), errors.Is(err, ErrInvalidPhone):
		status, code, message = http.StatusBadRequest, "INVALID_INPUT", err.Error()
	default:
		message = err.Error()
	}

	httpapi.WriteError(w, status, code, message, requestID, nil)
}

func decodeJSON(r *http.Request, dst any) error {
	defer r.Body.Close()
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil && !errors.Is(err, io.EOF) {
		return err
	}
	return nil
}
