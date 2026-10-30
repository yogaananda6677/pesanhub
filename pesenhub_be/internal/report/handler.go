package report

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"pesenhub/backend/internal/branch"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/domain"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) parseFilter(r *http.Request) (Filter, error) {
	scope := branch.ScopeFromContext(r.Context())
	filter := Filter{}

	rawBranch := strings.TrimSpace(r.URL.Query().Get("branch_id"))
	if rawBranch != "" {
		if !domain.ValidUUID(rawBranch) {
			return filter, errors.New("INVALID_BRANCH")
		}
		filter.BranchID = rawBranch
	} else if !scope.All && scope.BranchID != "" {
		filter.BranchID = scope.BranchID
	}

	if rawFrom := strings.TrimSpace(r.URL.Query().Get("from")); rawFrom != "" {
		t, err := parseDate(rawFrom, false)
		if err != nil {
			return filter, errors.New("INVALID_DATE_FROM")
		}
		filter.From = &t
	}

	if rawTo := strings.TrimSpace(r.URL.Query().Get("to")); rawTo != "" {
		t, err := parseDate(rawTo, true)
		if err != nil {
			return filter, errors.New("INVALID_DATE_TO")
		}
		filter.To = &t
	}

	if rawInc := strings.TrimSpace(r.URL.Query().Get("include_branches")); rawInc == "true" || rawInc == "1" {
		filter.IncludeBranches = true
	}

	return filter, nil
}

func (h *Handler) Summary(w http.ResponseWriter, r *http.Request) {
	p := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(p) {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Akses ditolak.", httpserver.RequestID(r.Context()), nil)
		return
	}

	filter, err := h.parseFilter(r)
	if err != nil {
		reqID := httpserver.RequestID(r.Context())
		if err.Error() == "INVALID_BRANCH" {
			httpapi.WriteError(w, http.StatusBadRequest, "INVALID_BRANCH", "Format branch_id tidak valid.", reqID, nil)
		} else {
			httpapi.WriteError(w, http.StatusBadRequest, "INVALID_DATE", "Parameter tanggal harus berformat YYYY-MM-DD atau RFC3339.", reqID, nil)
		}
		return
	}

	summary, err := h.service.GetSummary(r.Context(), p, filter)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, SummaryResponse{Summary: summary})
}

func (h *Handler) TopProducts(w http.ResponseWriter, r *http.Request) {
	p := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(p) {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Akses ditolak.", httpserver.RequestID(r.Context()), nil)
		return
	}

	filter, err := h.parseFilter(r)
	if err != nil {
		reqID := httpserver.RequestID(r.Context())
		if err.Error() == "INVALID_BRANCH" {
			httpapi.WriteError(w, http.StatusBadRequest, "INVALID_BRANCH", "Format branch_id tidak valid.", reqID, nil)
		} else {
			httpapi.WriteError(w, http.StatusBadRequest, "INVALID_DATE", "Parameter tanggal harus berformat YYYY-MM-DD atau RFC3339.", reqID, nil)
		}
		return
	}

	limit := 5
	if rawLimit := strings.TrimSpace(r.URL.Query().Get("limit")); rawLimit != "" {
		if parsed, err := strconv.Atoi(rawLimit); err == nil && parsed > 0 && parsed <= 50 {
			limit = parsed
		}
	}

	resp, err := h.service.GetTopProducts(r.Context(), p, filter, limit)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, resp)
}

func (h *Handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	requestID := httpserver.RequestID(r.Context())
	switch {
	case errors.Is(err, ErrUnauthorized):
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Akses ditolak.", requestID, nil)
	case errors.Is(err, ErrCrossBranchForbidden):
		httpapi.WriteError(w, http.StatusForbidden, "CROSS_BRANCH_FORBIDDEN", "Kasir tidak memiliki akses ke cabang lain.", requestID, nil)
	case errors.Is(err, ErrBranchNotFound):
		httpapi.WriteError(w, http.StatusNotFound, "BRANCH_NOT_FOUND", "Cabang tidak ditemukan.", requestID, nil)
	case errors.Is(err, ErrInvalidDateRange):
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_DATE_RANGE", "Rentang tanggal 'from' tidak boleh melebihi 'to'.", requestID, nil)
	default:
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Terjadi kesalahan internal pada server.", requestID, nil)
	}
}

func parseDate(val string, endOfDay bool) (time.Time, error) {
	if t, err := time.Parse(time.RFC3339, val); err == nil {
		return t, nil
	}
	if t, err := time.Parse("2006-01-02", val); err == nil {
		if endOfDay {
			return time.Date(t.Year(), t.Month(), t.Day(), 23, 59, 59, 999999999, time.UTC), nil
		}
		return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC), nil
	}
	return time.Time{}, errors.New("invalid date format")
}
