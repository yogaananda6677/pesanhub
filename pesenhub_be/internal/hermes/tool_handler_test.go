package hermes

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestToolHandlerCatalogRequiresDedicatedKey(t *testing.T) {
	handler := NewToolHandler(&mockCatalogProvider{categories: sampleCatalog()}, "tool-secret")

	unauthorized := httptest.NewRecorder()
	handler.Catalog(unauthorized, httptest.NewRequest(http.MethodGet, "/api/v1/hermes/tools/catalog", nil))
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized status = %d", unauthorized.Code)
	}

	authorized := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/hermes/tools/catalog", nil)
	req.Header.Set("Authorization", "Bearer tool-secret")
	handler.Catalog(authorized, req)
	if authorized.Code != http.StatusOK || !strings.Contains(authorized.Body.String(), "Nasi Goreng") {
		t.Fatalf("authorized response = %d %s", authorized.Code, authorized.Body.String())
	}
}
