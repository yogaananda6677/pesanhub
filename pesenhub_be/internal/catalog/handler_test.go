package catalog

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"pesenhub/backend/internal/httpserver"
	"strings"
	"testing"
)

func TestPublicCatalogSuccess(t *testing.T) {
	repo := &fakeRepo{categories: []Category{{ID: "c1", Name: "Makanan", Active: true, Menus: []Menu{{ID: "m1", Name: "Nasi Goreng", PriceAmount: 15000, Available: true}}}}}
	h := NewHandler(NewService(repo, func() string { return "id" }))
	req := httptest.NewRequest(http.MethodGet, "/api/v1/public/menu?filter[category_id]=c1", nil)
	rr := httptest.NewRecorder()
	httpserver.Middleware(slog.New(slog.NewTextHandler(io.Discard, nil)), http.HandlerFunc(h.Public)).ServeHTTP(rr, req)
	if rr.Code != http.StatusOK || !strings.Contains(rr.Body.String(), `"price_amount":15000`) {
		t.Fatalf("response=%d %s", rr.Code, rr.Body.String())
	}
}
func TestAdminCatalogDefaultsDenied(t *testing.T) {
	h := NewHandler(NewService(&fakeRepo{}, func() string { return "id" }))
	req := httptest.NewRequest(http.MethodPost, "/api/v1/admin/categories", strings.NewReader(`{"name":"Makanan"}`))
	rr := httptest.NewRecorder()
	httpserver.Middleware(slog.New(slog.NewTextHandler(io.Discard, nil)), http.HandlerFunc(h.CreateCategory)).ServeHTTP(rr, req)
	if rr.Code != http.StatusForbidden || !strings.Contains(rr.Body.String(), `"code":"FORBIDDEN"`) {
		t.Fatalf("response=%d %s", rr.Code, rr.Body.String())
	}
}
func TestModifierErrorCarriesSafeFieldPath(t *testing.T) {
	menu := Menu{Available: true, Groups: []Group{{ID: "spice", Active: true, MinSelect: 1, MaxSelect: 1}}}
	_, err := Price(menu, nil)
	h := NewHandler(NewService(&fakeRepo{}, func() string { return "id" }))
	req := httptest.NewRequest(http.MethodPost, "/", nil)
	rr := httptest.NewRecorder()
	httpserver.Middleware(slog.New(slog.NewTextHandler(io.Discard, nil)), http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { h.writeError(w, r, err) })).ServeHTTP(rr, req)
	if rr.Code != http.StatusUnprocessableEntity || !strings.Contains(rr.Body.String(), `"field":"modifier_groups.spice"`) {
		t.Fatalf("response=%d %s", rr.Code, rr.Body.String())
	}
}
