package order

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/ws"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestWebSocketOrderEventsIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	hub := ws.NewHub()
	defer hub.Close()

	publisher := NewOutboxPublisher(db, NewHubBroadcasterAdapter(hub), nil)
	store := NewStore(db)
	store.SetNotifier(publisher)

	// Drain any leftover outbox events from earlier tests
	for {
		c, err := publisher.ProcessBatch(ctx)
		if err != nil || c == 0 {
			break
		}
	}

	svc := NewService(store)
	h := NewHandler(svc, hub)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h.WS(w, r)
	}))
	defer server.Close()

	// 1. Acceptance Criteria: Unauthorized connection ditolak (403)
	resp, err := http.Get(server.URL)
	if err != nil {
		t.Fatalf("request error: %v", err)
	}
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("expected 403 for unauthenticated, got %d", resp.StatusCode)
	}

	// 2. Acceptance Criteria: Connect with STAFF and KDS roles
	connectClient := func(role, token string) (*ws.Conn, error) {
		u, _ := url.Parse(server.URL)
		tcpConn, err := net.Dial("tcp", u.Host)
		if err != nil {
			return nil, err
		}

		req := "GET /?token=" + token + " HTTP/1.1\r\n" +
			"Host: " + u.Host + "\r\n" +
			"Upgrade: websocket\r\n" +
			"Connection: Upgrade\r\n" +
			"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" +
			"Sec-WebSocket-Version: 13\r\n\r\n"

		if _, err = tcpConn.Write([]byte(req)); err != nil {
			tcpConn.Close()
			return nil, err
		}

		clientConn := ws.NewConn(tcpConn)
		// Read handshake response
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
			return nil, err
		}
		return clientConn, nil
	}

	staffConn, err := connectClient("STAFF", "staff-token-1")
	if err != nil {
		t.Fatalf("staff connect error: %v", err)
	}
	defer staffConn.Close()

	kdsConn, err := connectClient("KDS", "kds-token-1")
	if err != nil {
		t.Fatalf("kds connect error: %v", err)
	}
	defer kdsConn.Close()

	// Give hub a moment to register clients
	time.Sleep(50 * time.Millisecond)
	if hub.ClientCount() < 2 {
		t.Fatalf("expected at least 2 connected clients, got %d", hub.ClientCount())
	}

	// 3. Create an order and process outbox
	// Ensure catalog menu exists
	catID := "e1000000-0000-4000-8000-000000000001"
	menuID := "e2000000-0000-4000-8000-000000000001"
	if _, err = db.Exec(ctx, `INSERT INTO menu_categories(id,name) VALUES ($1,'Makanan') ON CONFLICT DO NOTHING`, catID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(ctx, `INSERT INTO menus(id,category_id,sku,name,price_amount,is_available) VALUES ($1,$2,'NASGOR-WS','Nasi Goreng WS',15000,true) ON CONFLICT DO NOTHING`, menuID, catID); err != nil {
		t.Fatal(err)
	}

	createIn := CreateInput{
		ClientOrderID: "f1000000-0000-4000-8000-000000000001",
		CustomerName:  "Test Realtime",
		CustomerPhone: "+62899999999",
		Notes:         "pedas level 3",
		Items: []ItemInput{
			{MenuID: menuID, Quantity: 1},
		},
	}

	order, _, err := svc.CreateManual(ctx, createIn, "ws-key-1", "staff-1", "req-1")
	if err != nil {
		t.Fatalf("create order error: %v", err)
	}

	// Drain outbox batch
	count, err := publisher.ProcessBatch(ctx)
	if err != nil {
		t.Fatalf("process outbox batch: %v", err)
	}
	if count == 0 {
		t.Fatal("expected outbox event to be processed")
	}

	// 4. Acceptance Criteria: Event committed diterima client aktif satu kali secara logis dalam target 5 detik
	readWithTimeout := func(conn *ws.Conn) (OrderEventEnvelope, error) {
		_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
		_, payload, err := conn.ReadMessage()
		if err != nil {
			return OrderEventEnvelope{}, err
		}
		var env OrderEventEnvelope
		err = json.Unmarshal(payload, &env)
		return env, err
	}

	staffEnv, err := readWithTimeout(staffConn)
	if err != nil {
		t.Fatalf("staff read error: %v", err)
	}
	if staffEnv.EventType != "ORDER_CREATED" || staffEnv.OrderID != order.ID || staffEnv.Version != 1 {
		t.Fatalf("unexpected staff event: %#v", staffEnv)
	}

	kdsEnv, err := readWithTimeout(kdsConn)
	if err != nil {
		t.Fatalf("kds read error: %v", err)
	}
	if kdsEnv.EventType != "ORDER_CREATED" || kdsEnv.OrderID != order.ID || kdsEnv.Version != 1 {
		t.Fatalf("unexpected kds event: %#v", kdsEnv)
	}

	// 5. Acceptance Criteria: Role KDS tidak menerima field pelanggan sensitif
	if strings.Contains(string(kdsEnv.Payload), "+62899999999") {
		t.Fatalf("KDS received sensitive customer phone in payload: %s", string(kdsEnv.Payload))
	}

	// 6. Transition order status and verify ORDER_STATUS_CHANGED event
	transRes, _, err := svc.Transition(ctx, order.ID, TransitionInput{TargetStatus: "ACCEPTED", ExpectedVersion: 1}, "ws-trans-key-1", "staff-1", "STAFF", "req-2")
	if err != nil {
		t.Fatalf("transition error: %v", err)
	}
	if transRes.Status != "ACCEPTED" || transRes.Version != 2 {
		t.Fatalf("unexpected transition result: %#v", transRes)
	}

	_, err = publisher.ProcessBatch(ctx)
	if err != nil {
		t.Fatalf("process transition outbox: %v", err)
	}

	staffTransEnv, err := readWithTimeout(staffConn)
	if err != nil {
		t.Fatalf("staff read transition error: %v", err)
	}
	if staffTransEnv.EventType != "ORDER_STATUS_CHANGED" || staffTransEnv.Version != 2 || staffTransEnv.Status != "ACCEPTED" {
		t.Fatalf("unexpected staff transition event: %#v", staffTransEnv)
	}

	kdsTransEnv, err := readWithTimeout(kdsConn)
	if err != nil {
		t.Fatalf("kds read transition error: %v", err)
	}
	if kdsTransEnv.EventType != "ORDER_STATUS_CHANGED" || kdsTransEnv.Version != 2 || kdsTransEnv.Status != "ACCEPTED" {
		t.Fatalf("unexpected kds transition event: %#v", kdsTransEnv)
	}
}
