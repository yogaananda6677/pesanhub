package hermes

import (
	"crypto/subtle"
	"net/http"
	"strings"

	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

// ToolHandler exposes a deliberately narrow, read-only surface for Hermes
// Agent. Business validation and order creation remain owned by the backend.
type ToolHandler struct {
	catalog CatalogProvider
	apiKey  string
}

func NewToolHandler(catalog CatalogProvider, apiKey string) *ToolHandler {
	return &ToolHandler{catalog: catalog, apiKey: apiKey}
}

func (h *ToolHandler) Catalog(w http.ResponseWriter, r *http.Request) {
	if !secureBearerEqual(r.Header.Get("Authorization"), h.apiKey) {
		httpapi.WriteError(w, http.StatusUnauthorized, "HERMES_TOOL_UNAUTHORIZED", "Hermes tool authorization required.", httpserver.RequestID(r.Context()), nil)
		return
	}

	branchID := strings.TrimSpace(r.URL.Query().Get("branch_id"))
	items, err := h.catalog.ListPublic(r.Context(), r.URL.Query().Get("category_id"), branchID)
	if err != nil {
		httpapi.WriteError(w, http.StatusServiceUnavailable, "CATALOG_UNAVAILABLE", "Catalog is temporarily unavailable.", httpserver.RequestID(r.Context()), nil)
		return
	}
	if items == nil {
		items = []catalog.Category{}
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": items})
}

func secureBearerEqual(header, expected string) bool {
	scheme, provided, ok := strings.Cut(strings.TrimSpace(header), " ")
	if !ok || !strings.EqualFold(scheme, "Bearer") || provided == "" || expected == "" || len(provided) != len(expected) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(provided), []byte(expected)) == 1
}
