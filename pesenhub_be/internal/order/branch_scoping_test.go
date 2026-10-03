package order

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/branch"
	"pesenhub/backend/internal/customer"
)

func TestService_BranchScopingAndIDOR(t *testing.T) {
	branchA := "b0000000-0000-0000-0000-000000000001"
	branchB := "b0000000-0000-0000-0000-000000000002"

	orderInA := OrderDetail{
		ID:          "11111111-1111-4111-8111-111111111111",
		OrderNumber: "BWX-ORDER-001",
		BranchID:    branchA,
		TotalAmount: 25000,
		Status:      "PENDING",
		CreatedAt:   time.Now(),
	}

	orderInB := OrderDetail{
		ID:          "22222222-2222-4222-8222-222222222222",
		OrderNumber: "JBR-ORDER-002",
		BranchID:    branchB,
		TotalAmount: 30000,
		Status:      "PENDING",
		CreatedAt:   time.Now(),
	}

	mock := &mockReader{
		getByIDFunc: func(ctx context.Context, id string) (OrderDetail, error) {
			if id == orderInA.ID {
				return orderInA, nil
			}
			if id == orderInB.ID {
				return orderInB, nil
			}
			return OrderDetail{}, ErrNotFound
		},
		listFunc: func(ctx context.Context, filter OrderFilter) ([]OrderDetail, string, error) {
			var res []OrderDetail
			for _, o := range []OrderDetail{orderInA, orderInB} {
				if filter.BranchID == "" || o.BranchID == filter.BranchID {
					res = append(res, o)
				}
			}
			return res, "", nil
		},
	}

	svc := &Service{reader: mock}

	t.Run("Cashier of Branch A cannot view order of Branch B (IDOR returns 404)", func(t *testing.T) {
		ctx := branch.WithScope(context.Background(), branch.Scope{BranchID: branchA, All: false})
		cashierA := customer.Principal{Subject: "u-cashier-a", Role: "CASHIER", BranchID: branchA}

		// Can view own branch order
		oA, err := svc.GetByID(ctx, cashierA, orderInA.ID)
		if err != nil {
			t.Fatalf("expected cashier to view own branch order, got: %v", err)
		}
		if oA.ID != orderInA.ID {
			t.Fatalf("unexpected order: %s", oA.ID)
		}

		// Cannot view other branch order
		_, err = svc.GetByID(ctx, cashierA, orderInB.ID)
		if err != ErrNotFound {
			t.Fatalf("expected ErrNotFound for cross-branch access, got: %v", err)
		}
	})

	t.Run("Cashier of Branch A only lists orders of Branch A", func(t *testing.T) {
		ctx := branch.WithScope(context.Background(), branch.Scope{BranchID: branchA, All: false})
		cashierA := customer.Principal{Subject: "u-cashier-a", Role: "CASHIER", BranchID: branchA}

		col, err := svc.List(ctx, cashierA, OrderFilter{})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(col.Data) != 1 || col.Data[0].BranchID != branchA {
			t.Fatalf("expected 1 order from branch A, got %d orders", len(col.Data))
		}
	})

	t.Run("Admin in All Branches mode can view and list all branches", func(t *testing.T) {
		ctx := branch.WithScope(context.Background(), branch.Scope{BranchID: "", All: true})
		admin := customer.Principal{Subject: "u-admin", Role: "ADMIN"}

		// Can view order in A
		oA, err := svc.GetByID(ctx, admin, orderInA.ID)
		if err != nil || oA.ID != orderInA.ID {
			t.Fatalf("expected admin to view order in A, err: %v", err)
		}

		// Can view order in B
		oB, err := svc.GetByID(ctx, admin, orderInB.ID)
		if err != nil || oB.ID != orderInB.ID {
			t.Fatalf("expected admin to view order in B, err: %v", err)
		}

		// List returns both
		col, err := svc.List(ctx, admin, OrderFilter{})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(col.Data) != 2 {
			t.Fatalf("expected 2 orders from all branches, got %d", len(col.Data))
		}
	})

	t.Run("Admin scoped to Branch B only sees Branch B orders", func(t *testing.T) {
		ctx := branch.WithScope(context.Background(), branch.Scope{BranchID: branchB, All: false})
		admin := customer.Principal{Subject: "u-admin", Role: "ADMIN"}

		col, err := svc.List(ctx, admin, OrderFilter{})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(col.Data) != 1 || col.Data[0].BranchID != branchB {
			t.Fatalf("expected 1 order from branch B, got %d orders", len(col.Data))
		}

		// Cannot view order from Branch A
		_, err = svc.GetByID(ctx, admin, orderInA.ID)
		if err != ErrNotFound {
			t.Fatalf("expected ErrNotFound for order in Branch A when scoped to Branch B, got: %v", err)
		}
	})
}

func TestHandler_CreateManual_BranchScoping(t *testing.T) {
	branchA := "b0000000-0000-0000-0000-000000000001"

	t.Run("Admin without active branch is rejected with 400 BRANCH_SCOPE_REQUIRED", func(t *testing.T) {
		h := NewHandler(&Service{})
		req := httptest.NewRequest(http.MethodPost, "/api/v1/orders", strings.NewReader(`{
			"client_order_id": "11111111-1111-4111-8111-111111111111",
			"customer_name": "Test Customer",
			"items": [{"menu_id": "22222222-2222-4222-8222-222222222222", "quantity": 1}]
		}`))
		req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{
			Subject: "u-admin",
			Role:    "ADMIN",
		}))
		// Admin without X-Branch-ID has scope.All = true
		req = req.WithContext(branch.WithScope(req.Context(), branch.Scope{All: true}))

		rec := httptest.NewRecorder()
		h.CreateManual(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 Bad Request, got %d", rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "BRANCH_SCOPE_REQUIRED") {
			t.Fatalf("expected BRANCH_SCOPE_REQUIRED error code, got %s", rec.Body.String())
		}
	})

	t.Run("Cashier with assigned branch passes branch check", func(t *testing.T) {
		mockStore := &mockOrderCreator{}
		svc := &Service{store: mockStore}
		h := NewHandler(svc)

		req := httptest.NewRequest(http.MethodPost, "/api/v1/orders", strings.NewReader(`{
			"client_order_id": "11111111-1111-4111-8111-111111111111",
			"customer_name": "Test Customer",
			"items": [{"menu_id": "22222222-2222-4222-8222-222222222222", "quantity": 1}]
		}`))
		req.Header.Set("Idempotency-Key", "test-key-123")
		req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{
			Subject:  "u-cashier-1",
			Role:     "CASHIER",
			BranchID: branchA,
		}))
		req = req.WithContext(branch.WithScope(req.Context(), branch.Scope{BranchID: branchA, All: false}))

		rec := httptest.NewRecorder()
		h.CreateManual(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("expected 201 Created, got %d: %s", rec.Code, rec.Body.String())
		}
		if mockStore.lastInput.BranchID != branchA {
			t.Fatalf("expected branch %s in created order, got %s", branchA, mockStore.lastInput.BranchID)
		}
	})
}

type mockOrderCreator struct {
	lastInput CreateInput
}

func (m *mockOrderCreator) Create(ctx context.Context, in CreateInput, key, hash, actorReq string) (Order, bool, error) {
	m.lastInput = in
	return Order{
		ID:          "order-new-123",
		OrderNumber: "BWX-ORDER-NEW",
		BranchID:    in.BranchID,
		TotalAmount: 15000,
		Status:      "PENDING",
		Version:     1,
		CreatedAt:   time.Now(),
	}, true, nil
}
