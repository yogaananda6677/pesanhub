package ws

import (
	"net"
	"testing"
	"time"
)

func TestHubMultiBranchBroadcastIsolation(t *testing.T) {
	hub := NewHub()
	defer hub.Close()

	cPipeCashierA, sPipeCashierA := net.Pipe()
	defer cPipeCashierA.Close()
	defer sPipeCashierA.Close()

	cPipeCashierB, sPipeCashierB := net.Pipe()
	defer cPipeCashierB.Close()
	defer sPipeCashierB.Close()

	cPipeAdminA, sPipeAdminA := net.Pipe()
	defer cPipeAdminA.Close()
	defer sPipeAdminA.Close()

	cPipeAdminAll, sPipeAdminAll := net.Pipe()
	defer cPipeAdminAll.Close()
	defer sPipeAdminAll.Close()

	cashierA := NewClient(hub, NewConn(sPipeCashierA), "CASHIER", "cashier-1", WithBranch("branch-A"))
	cashierB := NewClient(hub, NewConn(sPipeCashierB), "CASHIER", "cashier-2", WithBranch("branch-B"))
	adminScopedA := NewClient(hub, NewConn(sPipeAdminA), "ADMIN", "admin-1", WithBranch("branch-A"))
	adminAll := NewClient(hub, NewConn(sPipeAdminAll), "ADMIN", "admin-2", WithAllBranches(true))

	hub.Register(cashierA)
	hub.Register(cashierB)
	hub.Register(adminScopedA)
	hub.Register(adminAll)

	defer hub.Unregister(cashierA)
	defer hub.Unregister(cashierB)
	defer hub.Unregister(adminScopedA)
	defer hub.Unregister(adminAll)

	// Step 1: Broadcast event for Branch A
	eventBranchAPayload := []byte(`{"event_type":"ORDER_CREATED","branch_id":"branch-A"}`)
	hub.Broadcast(eventBranchAPayload, eventBranchAPayload, "branch-A")

	// Verification 1:
	// - Cashier A receives event
	// - Cashier B does NOT receive event
	// - Admin Scoped A receives event
	// - Admin All receives event
	select {
	case msg := <-cashierA.send:
		if string(msg) != string(eventBranchAPayload) {
			t.Fatalf("unexpected message for cashier A: %s", string(msg))
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("cashier A did not receive event for branch A")
	}

	select {
	case msg := <-cashierB.send:
		t.Fatalf("cashier B should NOT receive event for branch A, but got: %s", string(msg))
	case <-time.After(50 * time.Millisecond):
		// Expected: nothing received
	}

	select {
	case msg := <-adminScopedA.send:
		if string(msg) != string(eventBranchAPayload) {
			t.Fatalf("unexpected message for admin scoped A: %s", string(msg))
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("admin scoped A did not receive event for branch A")
	}

	select {
	case msg := <-adminAll.send:
		if string(msg) != string(eventBranchAPayload) {
			t.Fatalf("unexpected message for admin all branches: %s", string(msg))
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("admin all branches did not receive event for branch A")
	}

	// Step 2: Broadcast event for Branch B
	eventBranchBPayload := []byte(`{"event_type":"ORDER_CREATED","branch_id":"branch-B"}`)
	hub.Broadcast(eventBranchBPayload, eventBranchBPayload, "branch-B")

	// Verification 2:
	// - Cashier A does NOT receive event
	// - Cashier B receives event
	// - Admin Scoped A does NOT receive event
	// - Admin All receives event
	select {
	case msg := <-cashierA.send:
		t.Fatalf("cashier A should NOT receive event for branch B, but got: %s", string(msg))
	case <-time.After(50 * time.Millisecond):
		// Expected: nothing received
	}

	select {
	case msg := <-cashierB.send:
		if string(msg) != string(eventBranchBPayload) {
			t.Fatalf("unexpected message for cashier B: %s", string(msg))
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("cashier B did not receive event for branch B")
	}

	select {
	case msg := <-adminScopedA.send:
		t.Fatalf("admin scoped A should NOT receive event for branch B, but got: %s", string(msg))
	case <-time.After(50 * time.Millisecond):
		// Expected: nothing received
	}

	select {
	case msg := <-adminAll.send:
		if string(msg) != string(eventBranchBPayload) {
			t.Fatalf("unexpected message for admin all branches: %s", string(msg))
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("admin all branches did not receive event for branch B")
	}

	// Step 3: Broadcast system-wide event (no branch specified)
	systemPayload := []byte(`{"event_type":"SYSTEM_ANNOUNCEMENT"}`)
	hub.Broadcast(systemPayload, systemPayload)

	for _, client := range []*Client{cashierA, cashierB, adminScopedA, adminAll} {
		select {
		case msg := <-client.send:
			if string(msg) != string(systemPayload) {
				t.Fatalf("unexpected system message for %s: %s", client.Subject, string(msg))
			}
		case <-time.After(100 * time.Millisecond):
			t.Fatalf("%s did not receive system broadcast", client.Subject)
		}
	}

	// Step 4: Admin switches from branch A to branch B
	hub.Unregister(adminScopedA)
	cPipeAdminB, sPipeAdminB := net.Pipe()
	defer cPipeAdminB.Close()
	defer sPipeAdminB.Close()
	adminScopedB := NewClient(hub, NewConn(sPipeAdminB), "ADMIN", "admin-1", WithBranch("branch-B"))
	hub.Register(adminScopedB)
	defer hub.Unregister(adminScopedB)

	// Broadcast again to branch A -> adminScopedB should NOT receive it
	hub.Broadcast(eventBranchAPayload, eventBranchAPayload, "branch-A")
	select {
	case msg := <-adminScopedB.send:
		t.Fatalf("admin switched to branch B should NOT receive event for branch A, but got: %s", string(msg))
	case <-time.After(50 * time.Millisecond):
		// Expected: nothing received
	}

	// Broadcast to branch B -> adminScopedB SHOULD receive it
	hub.Broadcast(eventBranchBPayload, eventBranchBPayload, "branch-B")
	select {
	case msg := <-adminScopedB.send:
		if string(msg) != string(eventBranchBPayload) {
			t.Fatalf("unexpected message for switched admin: %s", string(msg))
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("admin switched to branch B did not receive event for branch B")
	}
}
