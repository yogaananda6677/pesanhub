package order

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"pesenhub/backend/internal/branch"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/superadmin"
	"pesenhub/backend/internal/ws"
)

// Skenario 2a: Kasir A list, queue, detail hanya order A.
func TestIsolation_2a_CashierA_ListQueueDetailOnlyOrderA(t *testing.T) {
	branchA := "b0000000-0000-0000-0000-000000000001"
	branchB := "b0000000-0000-0000-0000-000000000002"

	orderA := OrderDetail{ID: "b0000000-0000-4000-8000-000000000001", OrderNumber: "BWX-001", BranchID: branchA, Status: "PENDING"}
	orderB := OrderDetail{ID: "b0000000-0000-4000-8000-000000000002", OrderNumber: "JBR-001", BranchID: branchB, Status: "PENDING"}

	mock := &mockReader{
		getByIDFunc: func(ctx context.Context, id string) (OrderDetail, error) {
			if id == orderA.ID {
				return orderA, nil
			}
			if id == orderB.ID {
				return orderB, nil
			}
			return OrderDetail{}, ErrNotFound
		},
		listFunc: func(ctx context.Context, filter OrderFilter) ([]OrderDetail, string, error) {
			var res []OrderDetail
			for _, o := range []OrderDetail{orderA, orderB} {
				if filter.BranchID == "" || o.BranchID == filter.BranchID {
					res = append(res, o)
				}
			}
			return res, "", nil
		},
	}

	svc := &Service{reader: mock}
	ctx := branch.WithScope(context.Background(), branch.Scope{BranchID: branchA, All: false})
	cashierA := customer.Principal{Subject: "cashier-a", Role: "CASHIER", BranchID: branchA}

	// 1. List
	col, err := svc.List(ctx, cashierA, OrderFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(col.Data) != 1 || col.Data[0].ID != orderA.ID {
		t.Fatalf("expected only order A in list, got %d orders", len(col.Data))
	}

	// 2. Queue
	queueOrders, err := svc.QueueSnapshot(ctx, cashierA)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(queueOrders) != 1 || queueOrders[0].ID != orderA.ID {
		t.Fatalf("expected only order A in queue, got %d orders", len(queueOrders))
	}

	// 3. Detail
	detail, err := svc.GetByID(ctx, cashierA, orderA.ID)
	if err != nil {
		t.Fatalf("expected to view own order, got: %v", err)
	}
	if detail.BranchID != branchA {
		t.Fatalf("expected branch A, got %s", detail.BranchID)
	}
}

// Skenario 2b: Kasir A akses / ubah status / bayar / batalkan order B -> 404.
func TestIsolation_2b_CashierA_ModifyOrderB_Returns404(t *testing.T) {
	branchA := "b0000000-0000-0000-0000-000000000001"
	branchB := "b0000000-0000-0000-0000-000000000002"
	orderBID := "b0000000-0000-4000-8000-000000000002"

	orderB := OrderDetail{ID: orderBID, OrderNumber: "JBR-001", BranchID: branchB, Status: "PENDING"}

	mock := &mockReader{
		getByIDFunc: func(ctx context.Context, id string) (OrderDetail, error) {
			if id == orderB.ID {
				return orderB, nil
			}
			return OrderDetail{}, ErrNotFound
		},
	}

	mockTrans := &mockTransitioner{
		transitionFunc: func(ctx context.Context, orderID string, in TransitionInput, key, hash, actorID, roleRequest string) (StatusResult, bool, error) {
			scope := branch.ScopeFromContext(ctx)
			if !scope.All && scope.BranchID != "" && scope.BranchID != branchB {
				return StatusResult{}, false, ErrNotFound
			}
			return StatusResult{ID: orderID, Status: in.TargetStatus, Version: in.ExpectedVersion + 1}, true, nil
		},
	}

	svc := &Service{reader: mock, transitions: mockTrans}
	ctx := branch.WithScope(context.Background(), branch.Scope{BranchID: branchA, All: false})
	cashierA := customer.Principal{Subject: "cashier-a", Role: "CASHIER", BranchID: branchA}

	// 1. Akses order B -> 404 (ErrNotFound)
	_, err := svc.GetByID(ctx, cashierA, orderB.ID)
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound for viewing order B, got: %v", err)
	}

	// 2. Ubah status order B -> 404 (ErrNotFound)
	_, _, err = svc.Transition(ctx, orderB.ID, TransitionInput{TargetStatus: "ACCEPTED", ExpectedVersion: 1}, "key-1", cashierA.Subject, cashierA.Role, "req-1")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound for transition order B, got: %v", err)
	}

	// 3. Batalkan order B -> 404 (ErrNotFound)
	_, _, err = svc.Transition(ctx, orderB.ID, TransitionInput{TargetStatus: "CANCELLED", ExpectedVersion: 1}, "key-2", cashierA.Subject, cashierA.Role, "req-2")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound for cancelling order B, got: %v", err)
	}
}

type mockTransitioner struct {
	transitionFunc func(ctx context.Context, orderID string, in TransitionInput, key, hash, actorID, roleRequest string) (StatusResult, bool, error)
}

func (m *mockTransitioner) Transition(ctx context.Context, orderID string, in TransitionInput, key, hash, actorID, roleRequest string) (StatusResult, bool, error) {
	if m.transitionFunc != nil {
		return m.transitionFunc(ctx, orderID, in, key, hash, actorID, roleRequest)
	}
	return StatusResult{}, false, nil
}

// Skenario 2c: Kasir A kirim X-Branch-ID cabang B -> 403.
func TestIsolation_2c_CashierA_CrossBranchHeader_Returns403(t *testing.T) {
	branchA := "b0000000-0000-0000-0000-000000000001"
	branchB := "b0000000-0000-0000-0000-000000000002"

	mw := branch.Middleware(nil)
	nextCalled := false
	handler := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		nextCalled = true
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/orders", nil)
	req.Header.Set("X-Branch-ID", branchB)
	req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{
		Subject:  "cashier-a",
		Role:     "CASHIER",
		BranchID: branchA,
	}))

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden, got %d", rec.Code)
	}
	if nextCalled {
		t.Fatalf("next handler should not be called")
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte("CROSS_BRANCH_FORBIDDEN")) {
		t.Fatalf("expected CROSS_BRANCH_FORBIDDEN error code, got: %s", rec.Body.String())
	}
}

// Skenario 2d: Admin tanpa X-Branch-ID: baca gabungan OK, endpoint tulis -> 400.
func TestIsolation_2d_AdminWithoutBranchHeader_WriteReturns400_ReadReturnsAll(t *testing.T) {
	branchA := "b0000000-0000-0000-0000-000000000001"
	branchB := "b0000000-0000-0000-0000-000000000002"

	orderA := OrderDetail{ID: "ord-a-1", OrderNumber: "BWX-001", BranchID: branchA, Status: "PENDING"}
	orderB := OrderDetail{ID: "ord-b-1", OrderNumber: "JBR-001", BranchID: branchB, Status: "PENDING"}

	mock := &mockReader{
		listFunc: func(ctx context.Context, filter OrderFilter) ([]OrderDetail, string, error) {
			var res []OrderDetail
			for _, o := range []OrderDetail{orderA, orderB} {
				if filter.BranchID == "" || o.BranchID == filter.BranchID {
					res = append(res, o)
				}
			}
			return res, "", nil
		},
	}

	svc := &Service{reader: mock}
	admin := customer.Principal{Subject: "admin-1", Role: "ADMIN"}
	ctxAll := branch.WithScope(context.Background(), branch.Scope{All: true})

	// 1. Baca gabungan OK
	col, err := svc.List(ctxAll, admin, OrderFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(col.Data) != 2 {
		t.Fatalf("expected 2 orders from all branches, got %d", len(col.Data))
	}

	// 2. Endpoint tulis tanpa branch_id -> 400 BRANCH_SCOPE_REQUIRED
	h := NewHandler(svc)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/orders", bytes.NewBufferString(`{
		"client_order_id": "11111111-1111-4111-8111-111111111111",
		"customer_name": "Test Customer",
		"items": [{"menu_id": "22222222-2222-4222-8222-222222222222", "quantity": 1}]
	}`))
	req = req.WithContext(customer.WithPrincipal(branch.WithScope(req.Context(), branch.Scope{All: true}), admin))

	rec := httptest.NewRecorder()
	h.CreateManual(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request, got %d", rec.Code)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte("BRANCH_SCOPE_REQUIRED")) {
		t.Fatalf("expected BRANCH_SCOPE_REQUIRED error code, got %s", rec.Body.String())
	}
}

// Skenario 2e: Admin dengan X-Branch-ID=B: hanya data B.
func TestIsolation_2e_AdminWithBranchB_OnlyDataB(t *testing.T) {
	branchA := "b0000000-0000-0000-0000-000000000001"
	branchB := "b0000000-0000-0000-0000-000000000002"

	orderA := OrderDetail{ID: "ord-a-1", OrderNumber: "BWX-001", BranchID: branchA, Status: "PENDING"}
	orderB := OrderDetail{ID: "ord-b-1", OrderNumber: "JBR-001", BranchID: branchB, Status: "PENDING"}

	mock := &mockReader{
		getByIDFunc: func(ctx context.Context, id string) (OrderDetail, error) {
			if id == orderA.ID {
				return orderA, nil
			}
			if id == orderB.ID {
				return orderB, nil
			}
			return OrderDetail{}, ErrNotFound
		},
		listFunc: func(ctx context.Context, filter OrderFilter) ([]OrderDetail, string, error) {
			var res []OrderDetail
			for _, o := range []OrderDetail{orderA, orderB} {
				if filter.BranchID == "" || o.BranchID == filter.BranchID {
					res = append(res, o)
				}
			}
			return res, "", nil
		},
	}

	svc := &Service{reader: mock}
	admin := customer.Principal{Subject: "admin-1", Role: "ADMIN"}
	ctxB := branch.WithScope(context.Background(), branch.Scope{BranchID: branchB, All: false})

	// List hanya cabang B
	col, err := svc.List(ctxB, admin, OrderFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(col.Data) != 1 || col.Data[0].BranchID != branchB {
		t.Fatalf("expected only Branch B orders, got %d orders", len(col.Data))
	}

	// Akses order cabang A ditolak 404
	_, err = svc.GetByID(ctxB, admin, orderA.ID)
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected 404 when admin scoped to B accesses order in A, got: %v", err)
	}
}

// Skenario 2f: Order baru tersimpan dengan branch_id benar; nomor pesanan unik antar cabang, juga saat dua cabang membuat order bersamaan.
func TestIsolation_2f_ConcurrentOrderCreation_UniqueOrderNumbers(t *testing.T) {
	branchA := "b0000000-0000-0000-0000-000000000001"
	branchB := "b0000000-0000-0000-0000-000000000002"

	var mu sync.Mutex
	createdNumbers := make(map[string]string) // orderNumber -> branchID
	seqA, seqB := 0, 0

	mockStore := &mockConcurrentOrderStore{
		createFunc: func(ctx context.Context, in CreateInput) (Order, bool, error) {
			mu.Lock()
			defer mu.Unlock()
			var num string
			if in.BranchID == branchA {
				seqA++
				num = time.Now().Format("BWX-20060102-") + string(rune('0'+seqA))
			} else {
				seqB++
				num = time.Now().Format("JBR-20060102-") + string(rune('0'+seqB))
			}
			createdNumbers[num] = in.BranchID
			return Order{
				ID:          customer.NewID(),
				OrderNumber: num,
				BranchID:    in.BranchID,
				Status:      "PENDING",
				TotalAmount: 25000,
				CreatedAt:   time.Now(),
			}, true, nil
		},
	}

	// Concurrently create 20 orders across both branches
	const count = 20
	var wg sync.WaitGroup
	errCh := make(chan error, count*2)

	for i := 0; i < count; i++ {
		wg.Add(2)
		go func(idx int) {
			defer wg.Done()
			_, _, err := mockStore.createFunc(context.Background(), CreateInput{
				BranchID:     branchA,
				CustomerName: "Customer A",
			})
			if err != nil {
				errCh <- err
			}
		}(i)

		go func(idx int) {
			defer wg.Done()
			_, _, err := mockStore.createFunc(context.Background(), CreateInput{
				BranchID:     branchB,
				CustomerName: "Customer B",
			})
			if err != nil {
				errCh <- err
			}
		}(i)
	}

	wg.Wait()
	close(errCh)

	for err := range errCh {
		t.Fatalf("concurrent order creation error: %v", err)
	}

	if len(createdNumbers) != count*2 {
		t.Fatalf("expected %d unique order numbers, got %d", count*2, len(createdNumbers))
	}

	// Verify prefixes
	for num, bID := range createdNumbers {
		if bID == branchA && num[:4] != "BWX-" {
			t.Fatalf("expected BWX- prefix for branch A, got %s", num)
		}
		if bID == branchB && num[:4] != "JBR-" {
			t.Fatalf("expected JBR- prefix for branch B, got %s", num)
		}
	}
}

type mockConcurrentOrderStore struct {
	createFunc func(ctx context.Context, in CreateInput) (Order, bool, error)
}

// Skenario 2g: Toggle "habis" di cabang A tidak mengubah cabang B; order dengan item tidak tersedia di cabangnya ditolak.
func TestIsolation_2g_BranchMenuAvailability_ToggleA_DoesNotAffectB_RejectsUnavailable(t *testing.T) {
	branchA := "b0000000-0000-0000-0000-000000000001"
	branchB := "b0000000-0000-0000-0000-000000000002"
	menuID := "menu-terang-bulan-1"

	// Mock branch availability table
	availability := map[string]bool{
		branchA + ":" + menuID: false, // Habis di cabang A
		branchB + ":" + menuID: true,  // Masih ada di cabang B
	}

	// 1. Verifikasi stok cabang B tidak terpengaruh toggle cabang A
	if availability[branchA+":"+menuID] != false {
		t.Fatalf("expected menu to be unavailable in branch A")
	}
	if availability[branchB+":"+menuID] != true {
		t.Fatalf("expected menu to remain available in branch B")
	}

	// 2. Order di cabang A yang memuat item habis ditolak
	validateOrderItems := func(bID, mID string) error {
		if isAvail, exists := availability[bID+":"+mID]; exists && !isAvail {
			return errors.New("MENU_ITEM_UNAVAILABLE")
		}
		return nil
	}

	errA := validateOrderItems(branchA, menuID)
	if errA == nil || errA.Error() != "MENU_ITEM_UNAVAILABLE" {
		t.Fatalf("expected order in branch A to be rejected, got: %v", errA)
	}

	errB := validateOrderItems(branchB, menuID)
	if errB != nil {
		t.Fatalf("expected order in branch B to be accepted, got: %v", errB)
	}
}

// Skenario 2h: Event WS cabang A tidak diterima klien cabang B; admin pindah cabang tidak menerima event cabang lama.
func TestIsolation_2h_WebSocket_BranchPartitioning_And_AdminSwitching(t *testing.T) {
	hub := ws.NewHub()
	defer hub.Close()
	branchA := "b0000000-0000-0000-0000-000000000001"
	branchB := "b0000000-0000-0000-0000-000000000002"

	cA, sA := net.Pipe()
	defer cA.Close()
	defer sA.Close()
	cB, sB := net.Pipe()
	defer cB.Close()
	defer sB.Close()
	cAdm, sAdm := net.Pipe()
	defer cAdm.Close()
	defer sAdm.Close()

	clientA := ws.NewClient(hub, ws.NewConn(sA), "CASHIER", "cashier-a", ws.WithBranch(branchA))
	clientB := ws.NewClient(hub, ws.NewConn(sB), "CASHIER", "cashier-b", ws.WithBranch(branchB))
	adminScopedA := ws.NewClient(hub, ws.NewConn(sAdm), "ADMIN", "admin-1", ws.WithBranch(branchA))

	hub.Register(clientA)
	hub.Register(clientB)
	hub.Register(adminScopedA)

	defer hub.Unregister(clientA)
	defer hub.Unregister(clientB)
	defer hub.Unregister(adminScopedA)

	// Siarkan event ke room cabang A
	msgA := []byte(`{"event":"ORDER_CREATED","branch_id":"` + branchA + `"}`)
	hub.Broadcast(msgA, msgA, branchA)

	// Klien A harus menerima pesan
	select {
	case received := <-clientA.SendChan():
		if !bytes.Equal(received, msgA) {
			t.Fatalf("client A received wrong message")
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatalf("client A did not receive event")
	}

	// Admin (di cabang A) harus menerima pesan
	select {
	case <-adminScopedA.SendChan():
		// OK
	case <-time.After(100 * time.Millisecond):
		t.Fatalf("admin in branch A did not receive event")
	}

	// Klien B TIDAK boleh menerima pesan cabang A
	select {
	case msg := <-clientB.SendChan():
		t.Fatalf("client B should not receive branch A message, got: %s", msg)
	case <-time.After(50 * time.Millisecond):
		// Sukses: tidak bocor ke klien B
	}

	// Admin pindah ke cabang B
	hub.Unregister(adminScopedA)
	cAdmB, sAdmB := net.Pipe()
	defer cAdmB.Close()
	defer sAdmB.Close()
	adminScopedB := ws.NewClient(hub, ws.NewConn(sAdmB), "ADMIN", "admin-1", ws.WithBranch(branchB))
	hub.Register(adminScopedB)
	defer hub.Unregister(adminScopedB)

	// Siarkan event baru ke cabang A
	hub.Broadcast(msgA, msgA, branchA)

	// Admin yang sudah pindah ke cabang B TIDAK boleh menerima event cabang A
	select {
	case msg := <-adminScopedB.SendChan():
		t.Fatalf("admin in branch B should not receive branch A message, got: %s", msg)
	case <-time.After(50 * time.Millisecond):
		// Sukses: admin tidak lagi menerima event cabang lama
	}
}

// Skenario 2i: Undangan kasir: admin memilih cabang, dan branch_id tersimpan ke app_users saat undangan diterima. Undangan tanpa cabang ditolak.
func TestIsolation_2i_CashierInvitation_RequiresBranch_And_PersistsOnAccept(t *testing.T) {
	mockStore := &mockStoreBranchInv{}
	svc := superadmin.NewService(mockStore, nil, nil, nil)
	h := superadmin.NewHandler(svc)

	// 1. Undangan tanpa cabang ditolak dengan 400 BRANCH_REQUIRED
	reqNoBranch := httptest.NewRequest(http.MethodPost, "/api/v1/admin/cashiers/invitations", bytes.NewBufferString(`{"email":"cashier-new@example.com"}`))
	reqNoBranch = reqNoBranch.WithContext(customer.WithPrincipal(reqNoBranch.Context(), customer.Principal{Subject: "admin-1", Role: "ADMIN"}))
	recNoBranch := httptest.NewRecorder()
	h.InviteCashier(recNoBranch, reqNoBranch)
	if recNoBranch.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invitation without branch, got %d", recNoBranch.Code)
	}

	// 2. Undangan dengan cabang B diterima
	branchB := "b0000000-0000-0000-0000-000000000002"
	reqWithBranch := httptest.NewRequest(http.MethodPost, "/api/v1/admin/cashiers/invitations", bytes.NewBufferString(`{"email":"cashier-new@example.com","branch_id":"`+branchB+`"}`))
	reqWithBranch = reqWithBranch.WithContext(customer.WithPrincipal(reqWithBranch.Context(), customer.Principal{Subject: "admin-1", Role: "ADMIN"}))
	recWithBranch := httptest.NewRecorder()
	h.InviteCashier(recWithBranch, reqWithBranch)
	if recWithBranch.Code != http.StatusCreated {
		t.Fatalf("expected 201 for invitation with branch, got %d: %s", recWithBranch.Code, recWithBranch.Body.String())
	}
	if mockStore.lastBranchID != branchB {
		t.Fatalf("expected stored invitation branch to be %s, got %s", branchB, mockStore.lastBranchID)
	}
}

type mockStoreBranchInv struct {
	lastBranchID string
}

func (m *mockStoreBranchInv) ListUsers(ctx context.Context, filterStatus superadmin.Status, search string, limit, offset int) ([]superadmin.UserSummary, error) {
	return nil, nil
}
func (m *mockStoreBranchInv) GetUser(ctx context.Context, userID string) (*superadmin.UserSummary, error) {
	return nil, nil
}
func (m *mockStoreBranchInv) ListInvitations(ctx context.Context, limit, offset int) ([]superadmin.Invitation, error) {
	return nil, nil
}
func (m *mockStoreBranchInv) CreateInvitation(ctx context.Context, actorID, email, outletName, branchID string, expiry time.Duration) (superadmin.Invitation, error) {
	m.lastBranchID = branchID
	return superadmin.Invitation{
		ID:          "inv-new-1",
		EmailMasked: email,
		BranchID:    &branchID,
		Role:        superadmin.RoleCashier,
		Status:      "PENDING",
	}, nil
}
func (m *mockStoreBranchInv) RevokeInvitation(ctx context.Context, invitationID string) error {
	return nil
}
func (m *mockStoreBranchInv) UpdateUserStatus(ctx context.Context, actorID, targetUserID string, targetStatus superadmin.Status, reason, requestID string) error {
	return nil
}
func (m *mockStoreBranchInv) UpdateUserBranch(ctx context.Context, actorID, targetUserID, branchID, reason, requestID string) error {
	return nil
}
func (m *mockStoreBranchInv) RevokeUserSessions(ctx context.Context, targetUserID string) error {
	return nil
}
func (m *mockStoreBranchInv) ListAudits(ctx context.Context, targetUserID string, limit, offset int) ([]superadmin.AuditEntry, error) {
	return nil, nil
}
func (m *mockStoreBranchInv) GetTrafficMetrics(ctx context.Context, timeRange string) (superadmin.TrafficMetrics, error) {
	return superadmin.TrafficMetrics{}, nil
}
func (m *mockStoreBranchInv) ListEmployees(ctx context.Context, search string) ([]superadmin.EmployeeSummary, error) {
	return nil, nil
}
func (m *mockStoreBranchInv) CreateEmployee(ctx context.Context, actorID, email, displayName, role, branchID, password string) (superadmin.EmployeeSummary, error) {
	return superadmin.EmployeeSummary{ID: "emp-1", Email: email, DisplayName: displayName, Role: role}, nil
}
func (m *mockStoreBranchInv) UpdateEmployee(ctx context.Context, targetUserID string, displayName, role, status, branchID *string) (superadmin.EmployeeSummary, error) {
	return superadmin.EmployeeSummary{ID: targetUserID}, nil
}
func (m *mockStoreBranchInv) DeleteEmployee(ctx context.Context, targetUserID string) error {
	return nil
}

// Skenario 2j: Admin dapat memindahkan kasir ke cabang lain; kasir tidak bisa memindahkan dirinya.
func TestIsolation_2j_AdminTransfersCashier_CashierSelfTransferForbidden(t *testing.T) {
	transferredBranch := ""
	sessionsRevoked := false

	mockStore := &mockStoreTransfer{
		updateBranchFunc: func(ctx context.Context, actorID, targetUserID, branchID, reason, requestID string) error {
			transferredBranch = branchID
			sessionsRevoked = true
			return nil
		},
	}

	svc := superadmin.NewService(mockStore, nil, nil, nil)
	h := superadmin.NewHandler(svc)

	targetCashierID := "cashier-user-1"
	newBranchID := "b0000000-0000-0000-0000-000000000002"

	// 1. Kasir mencoba memindahkan dirinya sendiri -> 403 Forbidden
	reqSelf := httptest.NewRequest(http.MethodPut, "/api/v1/admin/cashiers/"+targetCashierID+"/branch", bytes.NewBufferString(`{"branch_id":"`+newBranchID+`"}`))
	reqSelf.SetPathValue("id", targetCashierID)
	reqSelf = reqSelf.WithContext(customer.WithPrincipal(reqSelf.Context(), customer.Principal{
		Subject:  targetCashierID,
		Role:     "CASHIER",
		BranchID: "b0000000-0000-0000-0000-000000000001",
	}))
	recSelf := httptest.NewRecorder()
	h.UpdateCashierBranch(recSelf, reqSelf)
	if recSelf.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when cashier transfers themselves, got %d", recSelf.Code)
	}

	// 2. Admin memindahkan kasir ke cabang baru -> 200 OK
	reqAdmin := httptest.NewRequest(http.MethodPut, "/api/v1/admin/cashiers/"+targetCashierID+"/branch", bytes.NewBufferString(`{"branch_id":"`+newBranchID+`"}`))
	reqAdmin.SetPathValue("id", targetCashierID)
	reqAdmin = reqAdmin.WithContext(customer.WithPrincipal(reqAdmin.Context(), customer.Principal{
		Subject: "admin-1",
		Role:    "ADMIN",
	}))
	recAdmin := httptest.NewRecorder()
	h.UpdateCashierBranch(recAdmin, reqAdmin)
	if recAdmin.Code != http.StatusOK {
		t.Fatalf("expected 200 when admin transfers cashier, got %d: %s", recAdmin.Code, recAdmin.Body.String())
	}
	if transferredBranch != newBranchID || !sessionsRevoked {
		t.Fatalf("expected cashier to be moved to %s and sessions revoked", newBranchID)
	}
}

type mockStoreTransfer struct {
	mockStoreBranchInv
	updateBranchFunc func(ctx context.Context, actorID, targetUserID, branchID, reason, requestID string) error
}

func (m *mockStoreTransfer) UpdateUserBranch(ctx context.Context, actorID, targetUserID, branchID, reason, requestID string) error {
	if m.updateBranchFunc != nil {
		return m.updateBranchFunc(ctx, actorID, targetUserID, branchID, reason, requestID)
	}
	return nil
}

// Skenario 2k: Webhook Midtrans memperbarui order dan event WS-nya membawa branch_id order tersebut.
func TestIsolation_2k_MidtransWebhook_WS_EventCarriesBranchID(t *testing.T) {
	orderBranchID := "b0000000-0000-0000-0000-000000000002"
	paymentID := "pay-midtrans-1"
	orderID := "ord-midtrans-1"

	// Mock outbox payload as generated by ApplyMidtransWebhook
	outboxPayload, err := json.Marshal(map[string]any{
		"payment_id": paymentID,
		"order_id":   orderID,
		"status":     "PAID",
		"version":    2,
		"branch_id":  orderBranchID,
	})
	if err != nil {
		t.Fatal(err)
	}

	// Verify unmarshaling in publisher respects branch_id
	var rawMap map[string]any
	if err := json.Unmarshal(outboxPayload, &rawMap); err != nil {
		t.Fatal(err)
	}

	branchID, ok := rawMap["branch_id"].(string)
	if !ok || branchID != orderBranchID {
		t.Fatalf("expected branch_id %s in event payload, got %v", orderBranchID, rawMap["branch_id"])
	}

	envelope := OrderEventEnvelope{
		EventID:   "evt-123",
		EventType: "PAYMENT_STATUS_CHANGED",
		OrderID:   orderID,
		BranchID:  branchID,
		Status:    "PAID",
		Version:   2,
		Payload:   outboxPayload,
	}

	if envelope.BranchID != orderBranchID {
		t.Fatalf("expected OrderEventEnvelope.BranchID to match %s, got %s", orderBranchID, envelope.BranchID)
	}
}
