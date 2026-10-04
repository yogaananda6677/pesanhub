package evaluation

import (
	"encoding/json"
	"errors"
	"fmt"
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

	var isReviewed *bool
	if reviewedStr := r.URL.Query().Get("is_reviewed"); reviewedStr != "" {
		val := reviewedStr == "true"
		isReviewed = &val
	}

	filter := ListFilter{
		BranchID:   r.URL.Query().Get("branch_id"),
		Rating:     r.URL.Query().Get("rating"),
		IsReviewed: isReviewed,
		Search:     r.URL.Query().Get("q"),
		Limit:      limit,
	}

	if principal.Role == "CASHIER" && filter.BranchID == "" && principal.BranchID != "" {
		filter.BranchID = principal.BranchID
	}

	evals, err := h.store.List(r.Context(), filter)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	if evals == nil {
		evals = []Evaluation{}
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": evals})
}

func (h *Handler) SubmitReview(w http.ResponseWriter, r *http.Request) {
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

	var in SubmitReviewInput
	if err := decodeJSON(r, &in); err != nil {
		h.writeError(w, r, ErrInvalidInput)
		return
	}

	reviewer := principal.Subject
	if reviewer == "" {
		reviewer = principal.Role
	}

	eval, err := h.store.SubmitReview(r.Context(), id, reviewer, in)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, eval)
}

func (h *Handler) Export(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	branchID := r.URL.Query().Get("branch_id")
	if principal.Role == "CASHIER" && branchID == "" && principal.BranchID != "" {
		branchID = principal.BranchID
	}

	reviewedOnly := r.URL.Query().Get("reviewed_only") == "true"
	format := r.URL.Query().Get("format")

	items, err := h.store.ExportDataset(r.Context(), branchID, reviewedOnly)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	if format == "jsonl" {
		w.Header().Set("Content-Type", "application/x-ndjson; charset=utf-8")
		w.Header().Set("Content-Disposition", "attachment; filename=\"jenggirat_training_dataset.jsonl\"")
		w.WriteHeader(http.StatusOK)

		for _, item := range items {
			line, _ := json.Marshal(item)
			_, _ = fmt.Fprintln(w, string(line))
		}
		return
	}

	if items == nil {
		items = []TrainingDatasetItem{}
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"count": len(items),
		"data":  items,
	})
}

func (h *Handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	requestID := httpserver.RequestID(r.Context())
	status, code, message := http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred."

	switch {
	case errors.Is(err, customer.ErrUnauthorized):
		status, code, message = http.StatusForbidden, "FORBIDDEN", "Staff authorization required."
	case errors.Is(err, customer.ErrUnauthenticated):
		status, code, message = http.StatusUnauthorized, "UNAUTHENTICATED", "Authentication required."
	case errors.Is(err, ErrEvaluationNotFound):
		status, code, message = http.StatusNotFound, "NOT_FOUND", "Evaluation not found."
	case errors.Is(err, ErrInvalidInput):
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
