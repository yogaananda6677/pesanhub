package catalog

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/branch"
	"pesenhub/backend/internal/customer"
	dbx "pesenhub/backend/internal/database"
	"pesenhub/backend/internal/httpserver"
)

func TestAdminWithoutBranchScopeCannotToggleAvailability(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo, func() string { return "id" })
	h := NewHandler(svc)

	// Admin with AllBranches mode (no X-Branch-ID)
	req := httptest.NewRequest(http.MethodPatch, "/api/v1/admin/menus/m1/availability", strings.NewReader(`{"is_available":false,"version":1}`))
	req.SetPathValue("id", "m1")
	req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{Subject: "admin-1", Role: "ADMIN"}))
	req = req.WithContext(branch.WithScope(req.Context(), branch.Scope{All: true, BranchID: ""}))

	rr := httptest.NewRecorder()
	httpserver.Middleware(slog.New(slog.NewTextHandler(io.Discard, nil)), http.HandlerFunc(h.Availability)).ServeHTTP(rr, req)

	if rr.Code != http.StatusBadRequest || !strings.Contains(rr.Body.String(), `"code":"BRANCH_SCOPE_REQUIRED"`) {
		t.Fatalf("expected 400 BRANCH_SCOPE_REQUIRED, got %d %s", rr.Code, rr.Body.String())
	}

	// Also for modifier option availability
	reqOpt := httptest.NewRequest(http.MethodPatch, "/api/v1/admin/modifier-options/o1/availability", strings.NewReader(`{"is_available":false,"version":1}`))
	reqOpt.SetPathValue("id", "o1")
	reqOpt = reqOpt.WithContext(customer.WithPrincipal(reqOpt.Context(), customer.Principal{Subject: "admin-1", Role: "ADMIN"}))
	reqOpt = reqOpt.WithContext(branch.WithScope(reqOpt.Context(), branch.Scope{All: true, BranchID: ""}))

	rrOpt := httptest.NewRecorder()
	httpserver.Middleware(slog.New(slog.NewTextHandler(io.Discard, nil)), http.HandlerFunc(h.OptionAvailability)).ServeHTTP(rrOpt, reqOpt)

	if rrOpt.Code != http.StatusBadRequest || !strings.Contains(rrOpt.Body.String(), `"code":"BRANCH_SCOPE_REQUIRED"`) {
		t.Fatalf("expected 400 BRANCH_SCOPE_REQUIRED for option, got %d %s", rrOpt.Code, rrOpt.Body.String())
	}
}

func TestAuthorizedStaffWithBranchScopeCanToggleAvailability(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo, func() string { return "id" })
	h := NewHandler(svc)

	// Admin with scoped branch
	req := httptest.NewRequest(http.MethodPatch, "/api/v1/admin/menus/m1/availability", strings.NewReader(`{"is_available":false,"version":1}`))
	req.SetPathValue("id", "m1")
	req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{Subject: "admin-1", Role: "ADMIN"}))
	req = req.WithContext(branch.WithScope(req.Context(), branch.Scope{All: false, BranchID: "branch-a"}))

	rr := httptest.NewRecorder()
	httpserver.Middleware(slog.New(slog.NewTextHandler(io.Discard, nil)), http.HandlerFunc(h.Availability)).ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d %s", rr.Code, rr.Body.String())
	}
	if repo.lastBranchID != "branch-a" {
		t.Fatalf("expected repo to receive branch-a, got %q", repo.lastBranchID)
	}

	// Cashier automatically bound to their branch
	reqCashier := httptest.NewRequest(http.MethodPatch, "/api/v1/admin/menus/m1/availability", strings.NewReader(`{"is_available":true,"version":2}`))
	reqCashier.SetPathValue("id", "m1")
	reqCashier = reqCashier.WithContext(customer.WithPrincipal(reqCashier.Context(), customer.Principal{Subject: "cashier-1", Role: "CASHIER", BranchID: "branch-b"}))
	reqCashier = reqCashier.WithContext(branch.WithScope(reqCashier.Context(), branch.Scope{All: false, BranchID: "branch-b"}))

	rrCashier := httptest.NewRecorder()
	httpserver.Middleware(slog.New(slog.NewTextHandler(io.Discard, nil)), http.HandlerFunc(h.Availability)).ServeHTTP(rrCashier, reqCashier)

	if rrCashier.Code != http.StatusOK {
		t.Fatalf("cashier expected 200 OK, got %d %s", rrCashier.Code, rrCashier.Body.String())
	}
	if repo.lastBranchID != "branch-b" {
		t.Fatalf("expected repo to receive branch-b, got %q", repo.lastBranchID)
	}
}

// MultiBranchRepo simulates branch-isolated availability storage for unit tests
type multiBranchRepo struct {
	categories       []Category
	menu             Menu
	menuAvailability map[string]map[string]bool // branchID -> menuID -> is_available
	menuVersions     map[string]map[string]int64
	optAvailability  map[string]map[string]bool
	optVersions      map[string]map[string]int64
}

func newMultiBranchRepo(menu Menu, initialAvailable bool) *multiBranchRepo {
	return &multiBranchRepo{
		menu:             menu,
		categories:       []Category{{ID: "c1", Name: "Makanan", Active: true, Menus: []Menu{menu}}},
		menuAvailability: make(map[string]map[string]bool),
		menuVersions:     make(map[string]map[string]int64),
		optAvailability:  make(map[string]map[string]bool),
		optVersions:      make(map[string]map[string]int64),
	}
}

func (m *multiBranchRepo) CreateCategory(_ context.Context, c Category, _ MutationMeta) (Category, error) {
	m.categories = append(m.categories, c)
	return c, nil
}
func (m *multiBranchRepo) UpdateCategory(_ context.Context, c Category, version int64, _ MutationMeta) (Category, error) {
	c.Version = version + 1
	return c, nil
}
func (m *multiBranchRepo) CreateMenu(_ context.Context, menu Menu, _ MutationMeta) (Menu, error) {
	m.menu = menu
	return menu, nil
}
func (m *multiBranchRepo) UpdateMenu(_ context.Context, menu Menu, version int64, _ MutationMeta) (Menu, error) {
	menu.Version = version + 1
	m.menu = menu
	return menu, nil
}
func (m *multiBranchRepo) SetMenuAvailability(_ context.Context, branchID, id string, available bool, version int64, _ MutationMeta) (Menu, error) {
	if m.menuAvailability[branchID] == nil {
		m.menuAvailability[branchID] = make(map[string]bool)
		m.menuVersions[branchID] = make(map[string]int64)
	}
	curVersion := m.menuVersions[branchID][id]
	if curVersion == 0 {
		curVersion = 1
	}
	if version != curVersion {
		return Menu{}, ErrVersionConflict
	}
	m.menuAvailability[branchID][id] = available
	m.menuVersions[branchID][id] = curVersion + 1
	res := m.menu
	res.Available = available
	res.Version = curVersion + 1
	return res, nil
}
func (m *multiBranchRepo) SetModifierOptionAvailability(_ context.Context, branchID, id string, available bool, version int64, _ MutationMeta) (Option, error) {
	if m.optAvailability[branchID] == nil {
		m.optAvailability[branchID] = make(map[string]bool)
		m.optVersions[branchID] = make(map[string]int64)
	}
	curVersion := m.optVersions[branchID][id]
	if curVersion == 0 {
		curVersion = 1
	}
	if version != curVersion {
		return Option{}, ErrVersionConflict
	}
	m.optAvailability[branchID][id] = available
	m.optVersions[branchID][id] = curVersion + 1
	return Option{ID: id, Available: available}, nil
}
func (m *multiBranchRepo) ListPublic(_ context.Context, categoryID string, branchID ...string) ([]Category, error) {
	bID := ""
	if len(branchID) > 0 {
		bID = branchID[0]
	}
	avail := true
	if m.menuAvailability[bID] != nil {
		if val, exists := m.menuAvailability[bID][m.menu.ID]; exists {
			avail = val
		}
	}
	var resCategories []Category
	for _, c := range m.categories {
		if categoryID != "" && c.ID != categoryID {
			continue
		}
		cat := c
		cat.Menus = []Menu{}
		if avail {
			item := m.menu
			item.Available = true
			cat.Menus = append(cat.Menus, item)
		}
		resCategories = append(resCategories, cat)
	}
	return resCategories, nil
}
func (m *multiBranchRepo) ListAdmin(_ context.Context, branchID ...string) ([]Category, error) {
	bID := ""
	if len(branchID) > 0 {
		bID = branchID[0]
	}
	avail := m.menu.Available
	version := m.menu.Version
	if m.menuAvailability[bID] != nil {
		if val, exists := m.menuAvailability[bID][m.menu.ID]; exists {
			avail = val
		}
		if v, exists := m.menuVersions[bID][m.menu.ID]; exists {
			version = v
		}
	}
	var resCategories []Category
	for _, c := range m.categories {
		cat := c
		cat.Menus = []Menu{}
		item := m.menu
		item.Available = avail
		item.Version = version
		cat.Menus = append(cat.Menus, item)
		resCategories = append(resCategories, cat)
	}
	return resCategories, nil
}

func TestMultiBranchMenuAvailabilityIsolation(t *testing.T) {
	menu := Menu{
		ID:          "menu-x",
		CategoryID:  "c1",
		SKU:         "MENU-X",
		Name:        "Menu X Spesial",
		PriceAmount: 25000,
		Available:   true,
		Version:     1,
	}
	repo := newMultiBranchRepo(menu, true)
	svc := NewService(repo, func() string { return "id" })

	ctx := context.Background()
	branchA := "branch-aaa-001"
	branchB := "branch-bbb-002"

	// Initial check: both branches see menu X available
	catA, err := svc.ListPublic(ctx, "", branchA)
	if err != nil || len(catA) == 0 || len(catA[0].Menus) == 0 {
		t.Fatalf("expected menu X to be available in branch A, got %v", catA)
	}

	catB, err := svc.ListPublic(ctx, "", branchB)
	if err != nil || len(catB) == 0 || len(catB[0].Menus) == 0 {
		t.Fatalf("expected menu X to be available in branch B, got %v", catB)
	}

	// Change availability of Menu X in Branch A to false
	updatedA, err := svc.SetMenuAvailability(ctx, branchA, menu.ID, false, 1, "cashier-a", "req-1")
	if err != nil || updatedA.Available {
		t.Fatalf("expected updatedA to be unavailable, got %#v, err=%v", updatedA, err)
	}

	// Verification 1: Branch B is NOT affected
	// Branch B public/cashier still sees Menu X
	catBAfter, err := svc.ListPublic(ctx, "", branchB)
	if err != nil || len(catBAfter) == 0 || len(catBAfter[0].Menus) == 0 {
		t.Fatalf("Branch B should NOT be affected, but Menu X disappeared from Branch B!")
	}
	if catBAfter[0].Menus[0].ID != menu.ID {
		t.Fatalf("expected menu X in branch B, got %v", catBAfter[0].Menus[0])
	}

	// Verification 2: Cashier Branch A sees Menu X as out of stock (not in public list)
	catAAfter, err := svc.ListPublic(ctx, "", branchA)
	if err != nil {
		t.Fatal(err)
	}
	if len(catAAfter) > 0 && len(catAAfter[0].Menus) > 0 {
		t.Fatalf("Branch A public catalog should filter out unavailable Menu X, but found %v", catAAfter[0].Menus)
	}

	// Admin scoped to Branch A sees Menu X with Available=false
	adminA, err := svc.ListAdmin(ctx, branchA)
	if err != nil || len(adminA[0].Menus) == 0 {
		t.Fatalf("Admin Branch A should see Menu X, got %v", adminA)
	}
	if adminA[0].Menus[0].Available != false {
		t.Fatalf("Admin Branch A should see Menu X as unavailable, got %v", adminA[0].Menus[0].Available)
	}

	// Admin scoped to Branch B sees Menu X with Available=true
	adminB, err := svc.ListAdmin(ctx, branchB)
	if err != nil || len(adminB[0].Menus) == 0 {
		t.Fatalf("Admin Branch B should see Menu X, got %v", adminB)
	}
	if adminB[0].Menus[0].Available != true {
		t.Fatalf("Admin Branch B should see Menu X as available, got %v", adminB[0].Menus[0].Available)
	}
}

func TestDatabaseMultiBranchMenuAvailabilityIsolationIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	db, err := dbx.Open(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	codeA := "TA" + suffix[len(suffix)-6:]
	codeB := "TB" + suffix[len(suffix)-6:]
	catName := "Kat " + suffix[len(suffix)-6:]
	menuSKU := "SKU-" + suffix[len(suffix)-6:]
	branchA := fmt.Sprintf("b1000000-0000-4000-8000-%012d", time.Now().UnixNano()%1000000000000)
	branchB := fmt.Sprintf("b2000000-0000-4000-8000-%012d", time.Now().UnixNano()%1000000000000)
	catID := fmt.Sprintf("c1000000-0000-4000-8000-%012d", time.Now().UnixNano()%1000000000000)
	menuID := fmt.Sprintf("m1000000-0000-4000-8000-%012d", time.Now().UnixNano()%1000000000000)

	// Cleanup test entities
	cleanup := func() {
		_, _ = db.Exec(context.Background(), `DELETE FROM branch_menu_availability WHERE branch_id IN ($1, $2)`, branchA, branchB)
		_, _ = db.Exec(context.Background(), `DELETE FROM menus WHERE id = $1`, menuID)
		_, _ = db.Exec(context.Background(), `DELETE FROM menu_categories WHERE id = $1`, catID)
		_, _ = db.Exec(context.Background(), `DELETE FROM branches WHERE id IN ($1, $2)`, branchA, branchB)
	}
	cleanup()
	defer cleanup()

	// Insert branches
	_, err = db.Exec(ctx, `INSERT INTO branches(id, code, name, is_default, is_active) VALUES ($1, $3, 'Cabang Test A', false, true), ($2, $4, 'Cabang Test B', false, true)`, branchA, branchB, codeA, codeB)
	if err != nil {
		t.Fatal(err)
	}

	// Insert category and menu
	_, err = db.Exec(ctx, `INSERT INTO menu_categories(id, name, sort_order, is_active, version) VALUES ($1, $2, 1, true, 1)`, catID, catName)
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(ctx, `INSERT INTO menus(id, category_id, sku, name, product_type, price_amount, is_available, version, sort_order) VALUES ($1, $2, $3, 'Menu Multi Branch Test', 'MARTABAK_TELUR', 20000, true, 1, 1)`, menuID, catID, menuSKU)
	if err != nil {
		t.Fatal(err)
	}

	// Seed branch_menu_availability
	_, err = db.Exec(ctx, `INSERT INTO branch_menu_availability(branch_id, menu_id, is_available, version) VALUES ($1, $3, true, 1), ($2, $3, true, 1)`, branchA, branchB, menuID)
	if err != nil {
		t.Fatal(err)
	}

	store := NewStore(db)
	meta := MutationMeta{ActorID: "tester", RequestID: "req-test", AuditID: fmt.Sprintf("a%d", time.Now().UnixNano())}

	// Toggle menu in branch A to false (version 1 -> 2)
	updatedA, err := store.SetMenuAvailability(ctx, branchA, menuID, false, 1, meta)
	if err != nil {
		t.Fatalf("SetMenuAvailability branch A failed: %v", err)
	}
	if updatedA.Available != false || updatedA.Version != 2 {
		t.Fatalf("expected branch A to be unavailable with version 2, got %#v", updatedA)
	}

	// Query Branch B catalog (public/cashier): menu MUST be available!
	publicB, err := store.ListPublic(ctx, catID, branchB)
	if err != nil {
		t.Fatal(err)
	}
	foundInB := false
	for _, c := range publicB {
		for _, m := range c.Menus {
			if m.ID == menuID && m.Available {
				foundInB = true
			}
		}
	}
	if !foundInB {
		t.Fatalf("Menu should be available in Branch B, but was not found!")
	}

	// Query Branch A catalog (public/cashier): menu MUST NOT appear!
	publicA, err := store.ListPublic(ctx, catID, branchA)
	if err != nil {
		t.Fatal(err)
	}
	foundInA := false
	for _, c := range publicA {
		for _, m := range c.Menus {
			if m.ID == menuID {
				foundInA = true
			}
		}
	}
	if foundInA {
		t.Fatalf("Menu should NOT appear in Branch A public catalog since it was marked unavailable!")
	}

	// Query Branch A catalog (admin): menu MUST appear with is_available = false
	adminA, err := store.ListAdmin(ctx, branchA)
	if err != nil {
		t.Fatal(err)
	}
	foundAdminA := false
	for _, c := range adminA {
		for _, m := range c.Menus {
			if m.ID == menuID {
				foundAdminA = true
				if m.Available {
					t.Fatalf("Admin for Branch A should see is_available = false, got true")
				}
			}
		}
	}
	if !foundAdminA {
		t.Fatalf("Menu was not found in Admin Branch A catalog!")
	}
}

func TestDatabaseMenuAvailabilityVersionDesyncTolerance(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	db, err := dbx.Open(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	branchID := "b0000000-0000-0000-0000-000000000001"
	catID := fmt.Sprintf("c%d", time.Now().UnixNano())
	menuID := fmt.Sprintf("m%d", time.Now().UnixNano())
	menuSKU := fmt.Sprintf("sku-%d", time.Now().UnixNano())

	_, err = db.Exec(ctx, `INSERT INTO menu_categories(id, name, sort_order, is_active, version) VALUES ($1, 'Desync Cat', 1, true, 1)`, catID)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = db.Exec(context.Background(), `DELETE FROM menus WHERE id=$1`, menuID)
		_, _ = db.Exec(context.Background(), `DELETE FROM menu_categories WHERE id=$1`, catID)
	})

	// Seed menu with version = 4 and is_available = false
	_, err = db.Exec(ctx, `INSERT INTO menus(id, category_id, sku, name, product_type, price_amount, is_available, version, sort_order) VALUES ($1, $2, $3, 'Desync Menu', 'MARTABAK_TELUR', 20000, false, 4, 1)`, menuID, catID, menuSKU)
	if err != nil {
		t.Fatal(err)
	}

	// Seed branch_menu_availability with version = 1 and is_available = false
	_, err = db.Exec(ctx, `INSERT INTO branch_menu_availability(branch_id, menu_id, is_available, version) VALUES ($1, $2, false, 1)`, branchID, menuID)
	if err != nil {
		t.Fatal(err)
	}

	store := NewStore(db)
	meta := MutationMeta{ActorID: "tester", RequestID: "req-desync-test", AuditID: fmt.Sprintf("a%d", time.Now().UnixNano())}

	// Client passes version = 4 (from menus.version). Must succeed!
	updated, err := store.SetMenuAvailability(ctx, branchID, menuID, true, 4, meta)
	if err != nil {
		t.Fatalf("SetMenuAvailability with version=4 failed: %v", err)
	}
	if !updated.Available {
		t.Fatalf("expected menu to be available")
	}
	if updated.Version < 5 {
		t.Fatalf("expected updated version >= 5, got %d", updated.Version)
	}

	// Verify menus table was also synchronized to is_available = true
	var menuAvailInBase bool
	err = db.QueryRow(ctx, `SELECT is_available FROM menus WHERE id=$1`, menuID).Scan(&menuAvailInBase)
	if err != nil {
		t.Fatal(err)
	}
	if !menuAvailInBase {
		t.Fatalf("expected menus.is_available to be true after default branch update")
	}
}
