package catalog

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"pesenhub/backend/internal/branch"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

type Handler struct {
	service   *Service
	uploadDir string
}

func NewHandler(s *Service) *Handler {
	return &Handler{service: s, uploadDir: "web/uploads"}
}

func NewHandlerWithUploadDir(s *Service, uploadDir string) *Handler {
	return &Handler{service: s, uploadDir: uploadDir}
}
func (h *Handler) Public(w http.ResponseWriter, r *http.Request) {
	scope := branch.ScopeFromContext(r.Context())
	branchID := scope.BranchID
	if branchID == "" {
		branchID = strings.TrimSpace(r.URL.Query().Get("branch_id"))
	}
	items, err := h.service.ListPublic(r.Context(), r.URL.Query().Get("filter[category_id]"), branchID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	absolutizeImageURLs(items, r)
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": items})
}
func (h *Handler) Admin(w http.ResponseWriter, r *http.Request) {
	if !operator(r) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	principal := customer.PrincipalFromRequest(r)
	scope := branch.ScopeFromContext(r.Context())
	branchID := scope.BranchID
	if branchID == "" && principal.Role == "ADMIN" {
		branchID = strings.TrimSpace(r.URL.Query().Get("branch_id"))
	}
	var items []Category
	var err error
	if customer.CanManageOutlet(principal) {
		items, err = h.service.ListAdmin(r.Context(), branchID)
	} else {
		// Cashiers can operate the POS, but cost price and inactive catalog
		// records remain an administrator-only concern.
		items, err = h.service.ListPublic(r.Context(), "", branchID)
	}
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	absolutizeImageURLs(items, r)
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": items})
}

func (h *Handler) UploadImage(w http.ResponseWriter, r *http.Request) {
	if !staff(r) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 6<<20)
	file, _, err := r.FormFile("image")
	if err != nil {
		h.writeError(w, r, ErrInvalidCatalog)
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, (5<<20)+1))
	if err != nil || len(data) == 0 || len(data) > 5<<20 {
		h.writeError(w, r, ErrInvalidCatalog)
		return
	}
	extensions := map[string]string{
		"image/jpeg": ".jpg",
		"image/png":  ".png",
		"image/webp": ".webp",
	}
	ext, allowed := extensions[http.DetectContentType(data)]
	if !allowed {
		h.writeError(w, r, ErrInvalidCatalog)
		return
	}
	if err = os.MkdirAll(h.uploadDir, 0o755); err != nil {
		h.writeError(w, r, err)
		return
	}
	name := strings.ReplaceAll(h.service.newID(), "-", "") + ext
	if err = os.WriteFile(filepath.Join(h.uploadDir, name), data, 0o644); err != nil {
		h.writeError(w, r, err)
		return
	}
	path := "/uploads/" + name
	httpapi.WriteJSON(w, http.StatusCreated, map[string]string{
		"image_url": absoluteImageURL(path, r),
	})
}

func absolutizeImageURLs(categories []Category, r *http.Request) {
	for ci := range categories {
		for mi := range categories[ci].Menus {
			categories[ci].Menus[mi].ImageURL = absoluteImageURL(categories[ci].Menus[mi].ImageURL, r)
		}
	}
}

func absoluteImageURL(value string, r *http.Request) string {
	if value == "" || strings.HasPrefix(value, "http://") || strings.HasPrefix(value, "https://") {
		return value
	}
	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}
	return scheme + "://" + r.Host + value
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
	result, err := h.service.CreateCategory(r.Context(), body, actorID(r), httpserver.RequestID(r.Context()))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	w.Header().Set("Location", "/api/v1/admin/categories/"+result.ID)
	httpapi.WriteJSON(w, http.StatusCreated, result)
}
func (h *Handler) UpdateCategory(w http.ResponseWriter, r *http.Request) {
	if !staff(r) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	var body Category
	if decode(r, &body) != nil {
		h.writeError(w, r, ErrInvalidCatalog)
		return
	}
	result, err := h.service.UpdateCategory(r.Context(), r.PathValue("id"), body, body.Version, actorID(r), httpserver.RequestID(r.Context()))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, result)
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
	result, err := h.service.CreateMenu(r.Context(), body, actorID(r), httpserver.RequestID(r.Context()))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	w.Header().Set("Location", "/api/v1/admin/menus/"+result.ID)
	httpapi.WriteJSON(w, http.StatusCreated, result)
}
func (h *Handler) UpdateMenu(w http.ResponseWriter, r *http.Request) {
	if !staff(r) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	var body Menu
	if decode(r, &body) != nil {
		h.writeError(w, r, ErrInvalidCatalog)
		return
	}
	result, err := h.service.UpdateMenu(r.Context(), r.PathValue("id"), body, body.Version, actorID(r), httpserver.RequestID(r.Context()))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, result)
}
func (h *Handler) Availability(w http.ResponseWriter, r *http.Request) {
	if !operator(r) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	principal := customer.PrincipalFromRequest(r)
	scope := branch.ScopeFromContext(r.Context())
	branchID := scope.BranchID
	if branchID == "" && principal.Role == "ADMIN" {
		branchID = strings.TrimSpace(r.URL.Query().Get("branch_id"))
	}
	if principal.Role == "ADMIN" && branchID == "" {
		httpapi.WriteError(w, http.StatusBadRequest, "BRANCH_SCOPE_REQUIRED", "Admin harus memilih cabang aktif (header X-Branch-ID) untuk mengubah ketersediaan menu.", httpserver.RequestID(r.Context()), nil)
		return
	}
	if branchID == "" {
		httpapi.WriteError(w, http.StatusBadRequest, "BRANCH_SCOPE_REQUIRED", "Cabang aktif harus ditentukan untuk mengubah ketersediaan menu.", httpserver.RequestID(r.Context()), nil)
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
	result, err := h.service.SetMenuAvailability(r.Context(), branchID, r.PathValue("id"), body.Available, body.Version, actorID(r), httpserver.RequestID(r.Context()))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, result)
}

func (h *Handler) OptionAvailability(w http.ResponseWriter, r *http.Request) {
	if !operator(r) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}
	principal := customer.PrincipalFromRequest(r)
	scope := branch.ScopeFromContext(r.Context())
	branchID := scope.BranchID
	if branchID == "" && principal.Role == "ADMIN" {
		branchID = strings.TrimSpace(r.URL.Query().Get("branch_id"))
	}
	if principal.Role == "ADMIN" && branchID == "" {
		httpapi.WriteError(w, http.StatusBadRequest, "BRANCH_SCOPE_REQUIRED", "Admin harus memilih cabang aktif (header X-Branch-ID) untuk mengubah ketersediaan opsi menu.", httpserver.RequestID(r.Context()), nil)
		return
	}
	if branchID == "" {
		httpapi.WriteError(w, http.StatusBadRequest, "BRANCH_SCOPE_REQUIRED", "Cabang aktif harus ditentukan untuk mengubah ketersediaan opsi menu.", httpserver.RequestID(r.Context()), nil)
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
	result, err := h.service.SetModifierOptionAvailability(r.Context(), branchID, r.PathValue("id"), body.Available, body.Version, actorID(r), httpserver.RequestID(r.Context()))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, result)
}

func actorID(r *http.Request) string { return customer.PrincipalFromRequest(r).Subject }
func staff(r *http.Request) bool {
	p := customer.PrincipalFromRequest(r)
	return customer.CanManageOutlet(p)
}
func operator(r *http.Request) bool {
	return customer.CanOperateOutlet(customer.PrincipalFromRequest(r))
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
	case errors.Is(err, ErrBranchScopeRequired):
		status, code, message = http.StatusBadRequest, "BRANCH_SCOPE_REQUIRED", "Cabang aktif harus ditentukan untuk operasi ini."
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
