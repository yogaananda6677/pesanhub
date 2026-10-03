package branch

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"pesenhub/backend/internal/customer"
)

type mockBranchRepo struct {
	branches map[string]Branch
}

func (m *mockBranchRepo) List(ctx context.Context, activeOnly bool) ([]Branch, error) {
	var res []Branch
	for _, b := range m.branches {
		if !activeOnly || b.IsActive {
			res = append(res, b)
		}
	}
	return res, nil
}

func (m *mockBranchRepo) GetByID(ctx context.Context, id string) (Branch, error) {
	b, ok := m.branches[id]
	if !ok {
		return Branch{}, ErrNotFound
	}
	return b, nil
}

func (m *mockBranchRepo) GetByCode(ctx context.Context, code string) (Branch, error) {
	for _, b := range m.branches {
		if b.Code == code {
			return b, nil
		}
	}
	return Branch{}, ErrNotFound
}

func (m *mockBranchRepo) GetDefault(ctx context.Context) (Branch, error) {
	for _, b := range m.branches {
		if b.IsDefault {
			return b, nil
		}
	}
	return Branch{}, ErrNotFound
}

func (m *mockBranchRepo) Create(ctx context.Context, b Branch) (Branch, error) {
	m.branches[b.ID] = b
	return b, nil
}

func (m *mockBranchRepo) Update(ctx context.Context, b Branch) (Branch, error) {
	m.branches[b.ID] = b
	return b, nil
}

func (m *mockBranchRepo) AssignUserBranch(ctx context.Context, userID, branchID string) error {
	return nil
}

func setupTestService() *Service {
	b1 := Branch{
		ID:        "b0000000-0000-0000-0000-000000000001",
		Code:      "BWX",
		Name:      "Cabang Utama Banyuwangi",
		IsDefault: true,
		IsActive:  true,
	}
	b2 := Branch{
		ID:        "b0000000-0000-0000-0000-000000000002",
		Code:      "JBR",
		Name:      "Cabang Jember",
		IsDefault: false,
		IsActive:  true,
	}
	bInactive := Branch{
		ID:        "b0000000-0000-0000-0000-000000000003",
		Code:      "MLG",
		Name:      "Cabang Malang",
		IsDefault: false,
		IsActive:  false,
	}
	repo := &mockBranchRepo{
		branches: map[string]Branch{
			b1.ID:        b1,
			b2.ID:        b2,
			bInactive.ID: bInactive,
		},
	}
	return NewService(repo)
}

func TestMiddleware_CashierScoping(t *testing.T) {
	svc := setupTestService()
	mw := Middleware(svc)

	cashierBranch := "b0000000-0000-0000-0000-000000000001"

	t.Run("Cashier automatically gets their assigned branch", func(t *testing.T) {
		var capturedScope Scope
		handler := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			capturedScope = ScopeFromContext(r.Context())
			w.WriteHeader(http.StatusOK)
		}))

		req := httptest.NewRequest(http.MethodGet, "/api/v1/orders", nil)
		req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{
			Subject:  "u-cashier-1",
			Role:     "CASHIER",
			BranchID: cashierBranch,
		}))

		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
		if capturedScope.BranchID != cashierBranch || capturedScope.All {
			t.Fatalf("expected branch %s, got %#v", cashierBranch, capturedScope)
		}
	})

	t.Run("Cashier with matching X-Branch-ID succeeds", func(t *testing.T) {
		handler := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		}))

		req := httptest.NewRequest(http.MethodGet, "/api/v1/orders", nil)
		req.Header.Set("X-Branch-ID", cashierBranch)
		req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{
			Subject:  "u-cashier-1",
			Role:     "CASHIER",
			BranchID: cashierBranch,
		}))

		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
	})

	t.Run("Cashier with mismatching X-Branch-ID gets 403 Forbidden", func(t *testing.T) {
		handler := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		}))

		req := httptest.NewRequest(http.MethodGet, "/api/v1/orders", nil)
		req.Header.Set("X-Branch-ID", "b0000000-0000-0000-0000-000000000002")
		req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{
			Subject:  "u-cashier-1",
			Role:     "CASHIER",
			BranchID: cashierBranch,
		}))

		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403 Forbidden, got %d", rec.Code)
		}
	})

	t.Run("Cashier without assigned branch gets 403 Forbidden", func(t *testing.T) {
		handler := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		}))

		req := httptest.NewRequest(http.MethodGet, "/api/v1/orders", nil)
		req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{
			Subject:  "u-cashier-no-branch",
			Role:     "CASHIER",
			BranchID: "",
		}))

		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403 Forbidden, got %d", rec.Code)
		}
	})

	t.Run("Cashier belonging to inactive branch gets 403 Forbidden", func(t *testing.T) {
		handler := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		}))

		req := httptest.NewRequest(http.MethodGet, "/api/v1/orders", nil)
		req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{
			Subject:  "u-cashier-inactive",
			Role:     "CASHIER",
			BranchID: "b0000000-0000-0000-0000-000000000003", // MLG is_active: false
		}))

		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403 Forbidden, got %d", rec.Code)
		}
	})
}

func TestMiddleware_AdminScoping(t *testing.T) {
	svc := setupTestService()
	mw := Middleware(svc)

	t.Run("Admin without X-Branch-ID enters All Branches mode", func(t *testing.T) {
		var capturedScope Scope
		handler := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			capturedScope = ScopeFromContext(r.Context())
			w.WriteHeader(http.StatusOK)
		}))

		req := httptest.NewRequest(http.MethodGet, "/api/v1/orders", nil)
		req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{
			Subject: "u-admin-1",
			Role:    "ADMIN",
		}))

		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
		if !capturedScope.All || capturedScope.BranchID != "" {
			t.Fatalf("expected all branches mode, got %#v", capturedScope)
		}
	})

	t.Run("Admin with valid X-Branch-ID scopes to that branch", func(t *testing.T) {
		targetBranch := "b0000000-0000-0000-0000-000000000002"
		var capturedScope Scope
		handler := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			capturedScope = ScopeFromContext(r.Context())
			w.WriteHeader(http.StatusOK)
		}))

		req := httptest.NewRequest(http.MethodGet, "/api/v1/orders", nil)
		req.Header.Set("X-Branch-ID", targetBranch)
		req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{
			Subject: "u-admin-1",
			Role:    "ADMIN",
		}))

		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
		if capturedScope.All || capturedScope.BranchID != targetBranch {
			t.Fatalf("expected scoped branch %s, got %#v", targetBranch, capturedScope)
		}
	})

	t.Run("Admin with inactive X-Branch-ID gets 400 Bad Request", func(t *testing.T) {
		inactiveBranch := "b0000000-0000-0000-0000-000000000003"
		handler := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		}))

		req := httptest.NewRequest(http.MethodGet, "/api/v1/orders", nil)
		req.Header.Set("X-Branch-ID", inactiveBranch)
		req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{
			Subject: "u-admin-1",
			Role:    "ADMIN",
		}))

		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 Bad Request, got %d", rec.Code)
		}
	})
}
