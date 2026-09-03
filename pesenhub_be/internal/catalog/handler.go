package catalog

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

type Handler struct{ service *Service }

func NewHandler(s *Service) *Handler { return &Handler{service: s} }
func (h *Handler) Public(w http.ResponseWriter, r *http.Request) {
	items, err := h.service.ListPublic(r.Context(), r.URL.Query().Get("filter[category_id]"))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": items})
}
func (h *Handler) CreateCategory(w http.ResponseWriter, r *http.Request) {
	if !staff(r) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	var body Category
	if decode(r, &body) != nil {
		h.writeError(w, r, ErrInvalidCatalog)
		return
	}
	result, err := h.service.CreateCategory(r.Context(), body)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	w.Header().Set("Location", "/api/v1/admin/categories/"+result.ID)
	httpapi.WriteJSON(w, http.StatusCreated, result)
}
func (h *Handler) CreateMenu(w http.ResponseWriter, r *http.Request) {
	if !staff(r) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	var body Menu
	if decode(r, &body) != nil {
		h.writeError(w, r, ErrInvalidCatalog)
		return
	}
	result, err := h.service.CreateMenu(r.Context(), body)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	w.Header().Set("Location", "/api/v1/admin/menus/"+result.ID)
	httpapi.WriteJSON(w, http.StatusCreated, result)
}
func (h *Handler) Availability(w http.ResponseWriter, r *http.Request) {
	if !staff(r) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	var body struct {
		Available bool  `json:"is_available"`
		Version   int64 `json:"version"`
	}
	if decode(r, &body) != nil {
		h.writeError(w, r, ErrInvalidCatalog)
		return
	}
	result, err := h.service.SetMenuAvailability(r.Context(), r.PathValue("id"), body.Available, body.Version)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, result)
}
func staff(r *http.Request) bool {
	p := customer.PrincipalFromRequest(r)
	return p.Subject != "" && p.Role == "STAFF"
}
func decode(r *http.Request, v any) error {
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
	status, code, message := http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred."
	details := []httpapi.FieldError(nil)
	switch {
	case errors.Is(err, customer.ErrUnauthorized):
		status, code, message = http.StatusForbidden, "FORBIDDEN", "Catalog administration requires staff authorization."
	case errors.Is(err, ErrInvalidCatalog), errors.Is(err, ErrInvalidModifier):
		status, code, message = http.StatusUnprocessableEntity, "VALIDATION_FAILED", "Catalog validation failed."
	case errors.Is(err, ErrUnavailable):
		status, code, message = http.StatusConflict, "CATALOG_UNAVAILABLE", "Menu or modifier is unavailable."
	case errors.Is(err, ErrVersionConflict):
		status, code, message = http.StatusConflict, "VERSION_CONFLICT", "Menu was modified by another request."
	}
	var validation *ValidationError
	if errors.As(err, &validation) {
		details = []httpapi.FieldError{{Field: validation.Field, Reason: "invalid_selection"}}
	}
	httpapi.WriteError(w, status, code, message, httpserver.RequestID(r.Context()), details)
}
