package shift_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"pesenhub/backend/internal/branch"
	"pesenhub/backend/internal/customer"
	dbx "pesenhub/backend/internal/database"
	"pesenhub/backend/internal/shift"
)

type mockBranchFinder struct {
	branches map[string]branch.Branch
}

func (m *mockBranchFinder) GetByID(ctx context.Context, id string) (branch.Branch, error) {
	b, ok := m.branches[id]
	if !ok {
		return branch.Branch{}, branch.ErrNotFound
	}
	return b, nil
}

func getTestDB(t *testing.T) *dbx.Pool {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = "pesenhub:pesenhub123@tcp(127.0.0.1:3306)/pesenhub?parseTime=true&multiStatements=true"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	db, err := dbx.Open(ctx, dsn)
	if err != nil {
		t.Skipf("skipping live database test: unable to connect to DB: %v", err)
		return nil
	}
	if err := db.Ping(ctx); err != nil {
		t.Skipf("skipping live database test: DB ping failed: %v", err)
		return nil
	}
	return db
}

func TestShiftAuthorizationAndValidation(t *testing.T) {
	branchA := "b0000000-0000-0000-0000-000000000001"
	finder := &mockBranchFinder{
		branches: map[string]branch.Branch{
			branchA: {ID: branchA, Code: "BWA", Name: "Cabang A", IsActive: true},
		},
	}

	svc := shift.NewService(nil, finder)
	handler := shift.NewHandler(svc)

	t.Run("Unauthorized user cannot open shift", func(t *testing.T) {
		body := bytes.NewBufferString(`{"starting_cash": 100000}`)
		req := httptest.NewRequest(http.MethodPost, "/api/v1/shifts/open", body)
		w := httptest.NewRecorder()
		handler.Open(w, req)

		if w.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized, got %d", w.Code)
		}
	})

	t.Run("Cashier with negative amount is rejected", func(t *testing.T) {
		cashierA := customer.Principal{
			Subject:  "cashier-1",
			Role:     "CASHIER",
			BranchID: branchA,
		}
		body := bytes.NewBufferString(`{"starting_cash": -50000}`)
		req := httptest.NewRequest(http.MethodPost, "/api/v1/shifts/open", body)
		ctx := customer.WithPrincipal(req.Context(), cashierA)
		ctx = branch.WithScope(ctx, branch.Scope{BranchID: branchA})
		req = req.WithContext(ctx)

		w := httptest.NewRecorder()
		handler.Open(w, req)

		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 Bad Request, got %d: %s", w.Code, w.Body.String())
		}
	})
}

func TestShiftLifecycleIntegration(t *testing.T) {
	db := getTestDB(t)
	if db == nil {
		return
	}

	ctx := context.Background()
	branchID := "b2000000-0000-4000-8000-000000000001"

	_, _ = db.Exec(ctx, `DELETE FROM cash_shifts WHERE branch_id = $1::uuid`, branchID)
	_, _ = db.Exec(ctx, `DELETE FROM branches WHERE id = $1::uuid`, branchID)

	_, err := db.Exec(ctx, `
		INSERT INTO branches (id, code, name, address, phone, is_default, is_active)
		VALUES ($1::uuid, 'SHIFT-1', 'Cabang Shift', 'Alamat Shift', '08122222222', false, true)
	`, branchID)
	if err != nil {
		t.Fatalf("failed to insert test branch: %v", err)
	}
	defer func() {
		_, _ = db.Exec(ctx, `DELETE FROM cash_shifts WHERE branch_id = $1::uuid`, branchID)
		_, _ = db.Exec(ctx, `DELETE FROM branches WHERE id = $1::uuid`, branchID)
	}()

	store := shift.NewStore(db)
	finder := &mockBranchFinder{
		branches: map[string]branch.Branch{
			branchID: {ID: branchID, Code: "SHIFT-1", Name: "Cabang Shift", IsActive: true},
		},
	}
	svc := shift.NewService(store, finder)
	handler := shift.NewHandler(svc)

	cashier := customer.Principal{
		Subject:  "cashier-user-1",
		Role:     "CASHIER",
		BranchID: branchID,
	}

	// 1. Initially no current shift
	t.Run("Get current shift when none is open returns null", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/shifts/current", nil)
		ctx := customer.WithPrincipal(req.Context(), cashier)
		ctx = branch.WithScope(ctx, branch.Scope{BranchID: branchID})
		req = req.WithContext(ctx)

		w := httptest.NewRecorder()
		handler.Current(w, req)

		if w.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d", w.Code)
		}
		var resp map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to parse json: %v", err)
		}
		if resp["shift"] != nil {
			t.Fatalf("expected nil shift, got %v", resp["shift"])
		}
	})

	// 2. Open shift with starting cash 100.000
	var openedShiftID string
	t.Run("Open shift creates active shift", func(t *testing.T) {
		body := bytes.NewBufferString(`{"starting_cash": 100000, "notes": "Modal awal kasir pagi"}`)
		req := httptest.NewRequest(http.MethodPost, "/api/v1/shifts/open", body)
		ctx := customer.WithPrincipal(req.Context(), cashier)
		ctx = branch.WithScope(ctx, branch.Scope{BranchID: branchID})
		req = req.WithContext(ctx)

		w := httptest.NewRecorder()
		handler.Open(w, req)

		if w.Code != http.StatusCreated {
			t.Fatalf("expected 201 Created, got %d: %s", w.Code, w.Body.String())
		}
		var resp shift.ShiftResponse
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to parse shift response: %v", err)
		}
		if resp.Shift.Status != "OPEN" {
			t.Fatalf("expected status OPEN, got %s", resp.Shift.Status)
		}
		if resp.Shift.StartingCash != 100000 {
			t.Fatalf("expected starting cash 100000, got %d", resp.Shift.StartingCash)
		}
		if resp.Shift.ExpectedCash != 100000 {
			t.Fatalf("expected expected cash 100000, got %d", resp.Shift.ExpectedCash)
		}
		openedShiftID = resp.Shift.ID
	})

	// 3. Opening another shift while one is active returns 409 Conflict
	t.Run("Cannot open another shift while one is already open", func(t *testing.T) {
		body := bytes.NewBufferString(`{"starting_cash": 50000}`)
		req := httptest.NewRequest(http.MethodPost, "/api/v1/shifts/open", body)
		ctx := customer.WithPrincipal(req.Context(), cashier)
		ctx = branch.WithScope(ctx, branch.Scope{BranchID: branchID})
		req = req.WithContext(ctx)

		w := httptest.NewRecorder()
		handler.Open(w, req)

		if w.Code != http.StatusConflict {
			t.Fatalf("expected 409 Conflict, got %d: %s", w.Code, w.Body.String())
		}
	})

	// 4. Query current shift
	t.Run("Current shift returns active shift", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/shifts/current", nil)
		ctx := customer.WithPrincipal(req.Context(), cashier)
		ctx = branch.WithScope(ctx, branch.Scope{BranchID: branchID})
		req = req.WithContext(ctx)

		w := httptest.NewRecorder()
		handler.Current(w, req)

		if w.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d", w.Code)
		}
		var resp shift.ShiftResponse
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to parse json: %v", err)
		}
		if resp.Shift.ID != openedShiftID {
			t.Fatalf("expected shift ID %s, got %s", openedShiftID, resp.Shift.ID)
		}
	})

	// 5. Close shift with physical cash 105.000 (discrepancy +5.000)
	t.Run("Close shift calculates discrepancy accurately", func(t *testing.T) {
		body := bytes.NewBufferString(`{"actual_cash": 105000, "notes": "Ada kelebihan tip 5000"}`)
		req := httptest.NewRequest(http.MethodPost, "/api/v1/shifts/close", body)
		ctx := customer.WithPrincipal(req.Context(), cashier)
		ctx = branch.WithScope(ctx, branch.Scope{BranchID: branchID})
		req = req.WithContext(ctx)

		w := httptest.NewRecorder()
		handler.Close(w, req)

		if w.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", w.Code, w.Body.String())
		}
		var resp shift.ShiftResponse
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to parse shift response: %v", err)
		}
		if resp.Shift.Status != "CLOSED" {
			t.Fatalf("expected status CLOSED, got %s", resp.Shift.Status)
		}
		if resp.Shift.ActualCash == nil || *resp.Shift.ActualCash != 105000 {
			t.Fatalf("expected actual cash 105000, got %v", resp.Shift.ActualCash)
		}
		if resp.Shift.Discrepancy == nil || *resp.Shift.Discrepancy != 5000 {
			t.Fatalf("expected discrepancy +5000, got %v", resp.Shift.Discrepancy)
		}
	})

	// 6. List shifts returns the closed shift
	t.Run("List shifts contains the recorded shift", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/shifts", nil)
		ctx := customer.WithPrincipal(req.Context(), cashier)
		ctx = branch.WithScope(ctx, branch.Scope{BranchID: branchID})
		req = req.WithContext(ctx)

		w := httptest.NewRecorder()
		handler.List(w, req)

		if w.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", w.Code, w.Body.String())
		}
		var resp shift.ShiftListResponse
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to parse json: %v", err)
		}
		if len(resp.Shifts) == 0 {
			t.Fatalf("expected at least 1 shift in history")
		}
		if resp.Shifts[0].ID != openedShiftID {
			t.Fatalf("expected shift ID %s, got %s", openedShiftID, resp.Shifts[0].ID)
		}
	})
}
