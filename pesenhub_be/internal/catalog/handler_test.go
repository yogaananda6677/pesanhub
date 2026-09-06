package catalog

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"pesenhub/backend/internal/customer"
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

func TestAuthorizedAdminCanReadAndMutateCatalog(t *testing.T) {
	repo := &fakeRepo{categories: []Category{{ID: "c1", Name: "Makanan", Active: true, Version: 1, Menus: []Menu{}}}}
	h := NewHandler(NewService(repo, func() string { return "generated-id" }))
	staffRequest := func(method, path, body string) *http.Request {
		req := httptest.NewRequest(method, path, strings.NewReader(body))
		return req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{Subject: "outlet-user", Role: "STAFF"}))
	}

	admin := httptest.NewRecorder()
	httpserver.Middleware(slog.New(slog.NewTextHandler(io.Discard, nil)), http.HandlerFunc(h.Admin)).
		ServeHTTP(admin, staffRequest(http.MethodGet, "/api/v1/admin/catalog", ""))
	if admin.Code != http.StatusOK || !strings.Contains(admin.Body.String(), `"version":1`) {
		t.Fatalf("admin response=%d %s", admin.Code, admin.Body.String())
	}

	create := httptest.NewRecorder()
	httpserver.Middleware(slog.New(slog.NewTextHandler(io.Discard, nil)), http.HandlerFunc(h.CreateCategory)).
		ServeHTTP(create, staffRequest(http.MethodPost, "/api/v1/admin/categories", `{"name":"Minuman","sort_order":1}`))
	if create.Code != http.StatusCreated || repo.lastMeta.ActorID != "outlet-user" || repo.lastMeta.RequestID == "" {
		t.Fatalf("create response=%d %s meta=%#v", create.Code, create.Body.String(), repo.lastMeta)
	}

	updateReq := staffRequest(http.MethodPatch, "/api/v1/admin/categories/c1", `{"name":"Makanan Utama","sort_order":0,"is_active":true,"version":1}`)
	updateReq.SetPathValue("id", "c1")
	update := httptest.NewRecorder()
	httpserver.Middleware(slog.New(slog.NewTextHandler(io.Discard, nil)), http.HandlerFunc(h.UpdateCategory)).
		ServeHTTP(update, updateReq)
	if update.Code != http.StatusOK || !strings.Contains(update.Body.String(), `"version":2`) {
		t.Fatalf("update response=%d %s", update.Code, update.Body.String())
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
