package order

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/appauth"
	"pesenhub/backend/internal/branch"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/ws"
)

type mockBranchRepo struct{}

func (m *mockBranchRepo) List(_ context.Context, _ bool) ([]branch.Branch, error) {
	return nil, nil
}
func (m *mockBranchRepo) GetByID(_ context.Context, id string) (branch.Branch, error) {
	return branch.Branch{ID: id, Code: "BR-" + id, Name: "Branch " + id, IsActive: true}, nil
}
func (m *mockBranchRepo) GetByCode(_ context.Context, code string) (branch.Branch, error) {
	return branch.Branch{ID: "b-1", Code: code, Name: "Branch " + code, IsActive: true}, nil
}
func (m *mockBranchRepo) GetDefault(_ context.Context) (branch.Branch, error) {
	return branch.Branch{ID: "default", Code: "DEF", Name: "Default Branch", IsActive: true}, nil
}
func (m *mockBranchRepo) Create(_ context.Context, b branch.Branch) (branch.Branch, error) {
	return b, nil
}
func (m *mockBranchRepo) Update(_ context.Context, b branch.Branch) (branch.Branch, error) {
	return b, nil
}
func (m *mockBranchRepo) AssignUserBranch(_ context.Context, _, _ string) error {
	return nil
}

func TestOrderWebSocketMultiBranchDelivery(t *testing.T) {
	hub := ws.NewHub()
	defer hub.Close()

	svc := &Service{}
	h := NewHandler(svc, hub)

	sessions, err := appauth.NewSessionManager("12345678901234567890123456789012", 8*time.Hour)
	if err != nil {
		t.Fatal(err)
	}

	branchA := "b0000000-0000-0000-0000-000000000001"
	branchB := "b0000000-0000-0000-0000-000000000002"
	tokenCashierA, _, _, _ := sessions.IssuePersistentWithBranch("cashier-a-id", "CASHIER", branchA)
	tokenCashierB, _, _, _ := sessions.IssuePersistentWithBranch("cashier-b-id", "CASHIER", branchB)
	tokenAdmin, _, _, _ := sessions.IssuePersistentWithBranch("admin-id", "ADMIN", "")

	branchSvc := branch.NewService(&mockBranchRepo{})

	wsHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h.WS(w, r)
	})

	server := httptest.NewServer(customer.Authenticate("", "", sessions, branch.Middleware(branchSvc)(wsHandler)))
	defer server.Close()

	connectWS := func(token, branchHeader, queryBranch string) (*ws.Conn, error) {
		u, _ := url.Parse(server.URL)
		tcpConn, err := net.Dial("tcp", u.Host)
		if err != nil {
			return nil, err
		}

		path := "/api/v1/ws/orders?token=" + token
		if queryBranch != "" {
			path += "&branch_id=" + queryBranch
		}

		req := "GET " + path + " HTTP/1.1\r\n" +
			"Host: " + u.Host + "\r\n" +
			"Upgrade: websocket\r\n" +
			"Connection: Upgrade\r\n" +
			"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" +
			"Sec-WebSocket-Version: 13\r\n"
		if branchHeader != "" {
			req += "X-Branch-ID: " + branchHeader + "\r\n"
		}
		req += "\r\n"

		if _, err = tcpConn.Write([]byte(req)); err != nil {
			tcpConn.Close()
			return nil, err
		}

		clientConn := ws.NewConn(tcpConn)
		var line string
		for {
			var b [1]byte
			_, err = tcpConn.Read(b[:])
			if err != nil {
				return nil, err
			}
			line += string(b[0])
			if strings.HasSuffix(line, "\r\n\r\n") {
				break
			}
		}
		if !strings.Contains(line, "101 Switching Protocols") {
			tcpConn.Close()
			return nil, fmt.Errorf("websocket upgrade failed: %s", strings.TrimSpace(line))
		}
		return clientConn, nil
	}

	// Connect Cashier A (bound to branch-A)
	connCashierA, err := connectWS(tokenCashierA, branchA, "")
	if err != nil {
		t.Fatalf("failed to connect Cashier A: %v", err)
	}
	defer connCashierA.Close()

	// Connect Cashier B (bound to branch-B)
	connCashierB, err := connectWS(tokenCashierB, branchB, "")
	if err != nil {
		t.Fatalf("failed to connect Cashier B: %v", err)
	}
	defer connCashierB.Close()

	// Connect Admin All Branches (no branch header)
	connAdminAll, err := connectWS(tokenAdmin, "", "")
	if err != nil {
		t.Fatalf("failed to connect Admin All: %v", err)
	}
	defer connAdminAll.Close()

	// Connect Admin Scoped to Branch A
	connAdminScopedA, err := connectWS(tokenAdmin, branchA, "")
	if err != nil {
		t.Fatalf("failed to connect Admin Scoped A: %v", err)
	}
	defer connAdminScopedA.Close()

	// Wait for all 4 clients to register
	deadline := time.Now().Add(2 * time.Second)
	for hub.ClientCount() < 4 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if hub.ClientCount() < 4 {
		t.Fatalf("expected 4 connected clients, got %d", hub.ClientCount())
	}

	readWithTimeout := func(conn *ws.Conn, timeout time.Duration) (OrderEventEnvelope, error) {
		_ = conn.SetReadDeadline(time.Now().Add(timeout))
		_, payload, err := conn.ReadMessage()
		if err != nil {
			return OrderEventEnvelope{}, err
		}
		var env OrderEventEnvelope
		err = json.Unmarshal(payload, &env)
		return env, err
	}

	adapter := NewHubBroadcasterAdapter(hub)

	// Broadcast an event for Branch A
	envBranchA := OrderEventEnvelope{
		EventID:   "evt-1",
		EventType: "ORDER_CREATED",
		OrderID:   "ord-branch-a",
		BranchID:  branchA,
		Status:    "PENDING",
		Version:   1,
	}
	payloadA, _ := json.Marshal(envBranchA)
	adapter.Broadcast(payloadA, payloadA, branchA)

	// 1. Cashier A MUST receive it
	gotA, err := readWithTimeout(connCashierA, 500*time.Millisecond)
	if err != nil || gotA.OrderID != "ord-branch-a" {
		t.Fatalf("Cashier A failed to receive branch-A event: %v", err)
	}

	// 2. Cashier B MUST NOT receive it
	_, err = readWithTimeout(connCashierB, 50*time.Millisecond)
	if err == nil {
		t.Fatal("Cashier B should NOT receive branch-A event, but received it!")
	}

	// 3. Admin All MUST receive it
	gotAdminAll, err := readWithTimeout(connAdminAll, 500*time.Millisecond)
	if err != nil || gotAdminAll.OrderID != "ord-branch-a" {
		t.Fatalf("Admin All failed to receive branch-A event: %v", err)
	}

	// 4. Admin Scoped A MUST receive it
	gotAdminA, err := readWithTimeout(connAdminScopedA, 500*time.Millisecond)
	if err != nil || gotAdminA.OrderID != "ord-branch-a" {
		t.Fatalf("Admin Scoped A failed to receive branch-A event: %v", err)
	}

	// Now broadcast an event for Branch B
	envBranchB := OrderEventEnvelope{
		EventID:   "evt-2",
		EventType: "ORDER_CREATED",
		OrderID:   "ord-branch-b",
		BranchID:  branchB,
		Status:    "PENDING",
		Version:   1,
	}
	payloadB, _ := json.Marshal(envBranchB)
	adapter.Broadcast(payloadB, payloadB, branchB)

	// 5. Cashier A MUST NOT receive it
	_, err = readWithTimeout(connCashierA, 50*time.Millisecond)
	if err == nil {
		t.Fatal("Cashier A should NOT receive branch-B event, but received it!")
	}

	// 6. Cashier B MUST receive it
	gotB, err := readWithTimeout(connCashierB, 500*time.Millisecond)
	if err != nil || gotB.OrderID != "ord-branch-b" {
		t.Fatalf("Cashier B failed to receive branch-B event: %v", err)
	}

	// 7. Admin Scoped A MUST NOT receive it
	_, err = readWithTimeout(connAdminScopedA, 50*time.Millisecond)
	if err == nil {
		t.Fatal("Admin Scoped A should NOT receive branch-B event, but received it!")
	}

	// 8. Admin All MUST receive it
	gotAdminAllB, err := readWithTimeout(connAdminAll, 500*time.Millisecond)
	if err != nil || gotAdminAllB.OrderID != "ord-branch-b" {
		t.Fatalf("Admin All failed to receive branch-B event: %v", err)
	}
}
