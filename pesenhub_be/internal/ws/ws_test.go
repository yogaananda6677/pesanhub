package ws

import (
	"bytes"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestWebSocketUpgradeRejections(t *testing.T) {
	// Not websocket
	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	w := httptest.NewRecorder()
	_, err := Upgrade(w, req)
	if err != ErrNotWebsocket {
		t.Fatalf("expected ErrNotWebsocket, got %v", err)
	}

	// Missing key
	req = httptest.NewRequest(http.MethodGet, "/ws", nil)
	req.Header.Set("Upgrade", "websocket")
	req.Header.Set("Connection", "Upgrade")
	w = httptest.NewRecorder()
	_, err = Upgrade(w, req)
	if err != ErrNotWebsocket {
		t.Fatalf("expected ErrNotWebsocket on missing key, got %v", err)
	}
}

func TestWebSocketClientServerFrameRoundtrip(t *testing.T) {
	serverPipe, clientPipe := net.Pipe()
	defer serverPipe.Close()
	defer clientPipe.Close()

	serverConn := NewConn(serverPipe)
	clientConn := NewConn(clientPipe)

	msgText := `{"event_type":"ORDER_CREATED","version":1}`

	// Test Server to Client (unmasked server frame)
	errChan := make(chan error, 1)
	go func() {
		errChan <- serverConn.WriteText([]byte(msgText))
	}()

	op, payload, err := clientConn.ReadMessage()
	if err != nil {
		t.Fatalf("client read error: %v", err)
	}
	if op != OpcodeText || string(payload) != msgText {
		t.Fatalf("unexpected message: op=%d, text=%s", op, string(payload))
	}
	if err = <-errChan; err != nil {
		t.Fatalf("server write error: %v", err)
	}

	// Test Client to Server with masking (RFC 6455 requires client-to-server frames to be masked)
	go func() {
		// Manually build masked frame from client
		mask := [4]byte{0x12, 0x34, 0x56, 0x78}
		data := []byte("hello from client")
		masked := make([]byte, len(data))
		for i := 0; i < len(data); i++ {
			masked[i] = data[i] ^ mask[i%4]
		}
		var buf bytes.Buffer
		buf.WriteByte(0x81)                   // FIN + text
		buf.WriteByte(0x80 | byte(len(data))) // MASK + len
		buf.Write(mask[:])
		buf.Write(masked)
		_, _ = clientPipe.Write(buf.Bytes())
	}()

	op, payload, err = serverConn.ReadMessage()
	if err != nil {
		t.Fatalf("server read error: %v", err)
	}
	if string(payload) != "hello from client" {
		t.Fatalf("expected 'hello from client', got '%s'", string(payload))
	}
}

func TestWebSocketMediumPayloadFraming(t *testing.T) {
	serverPipe, clientPipe := net.Pipe()
	defer serverPipe.Close()
	defer clientPipe.Close()

	serverConn := NewConn(serverPipe)
	clientConn := NewConn(clientPipe)

	// Medium payload (length between 126 and 65535)
	medium := make([]byte, 1000)
	for i := range medium {
		medium[i] = byte(i % 256)
	}

	go func() {
		_ = serverConn.WriteText(medium)
	}()

	op, payload, err := clientConn.ReadMessage()
	if err != nil {
		t.Fatalf("read error: %v", err)
	}
	if op != OpcodeText || len(payload) != len(medium) || !bytes.Equal(payload, medium) {
		t.Fatalf("medium payload mismatch: got %d bytes, want %d", len(payload), len(medium))
	}
}

func TestHubRegistrationAndRoleAwareBroadcast(t *testing.T) {
	hub := NewHub()
	defer hub.Close()

	sPipe1, cPipe1 := net.Pipe()
	defer sPipe1.Close()
	defer cPipe1.Close()

	sPipe2, cPipe2 := net.Pipe()
	defer sPipe2.Close()
	defer cPipe2.Close()

	staffClient := NewClient(hub, NewConn(sPipe1), "STAFF", "staff-1")
	kdsClient := NewClient(hub, NewConn(sPipe2), "KDS", "kds-1")

	hub.Register(staffClient)
	hub.Register(kdsClient)

	if hub.ClientCount() != 2 {
		t.Fatalf("expected 2 clients, got %d", hub.ClientCount())
	}

	// Start write pumps
	go staffClient.WritePump(1 * time.Hour)
	go kdsClient.WritePump(1 * time.Hour)

	staffPayload := []byte(`{"role":"STAFF","customer_phone":"+62811"}`)
	kdsPayload := []byte(`{"role":"KDS","customer_phone":null}`)

	hub.Broadcast(staffPayload, kdsPayload)

	cConn1 := NewConn(cPipe1)
	cConn2 := NewConn(cPipe2)

	_, p1, err := cConn1.ReadMessage()
	if err != nil {
		t.Fatalf("staff client read error: %v", err)
	}
	if string(p1) != string(staffPayload) {
		t.Fatalf("staff received wrong payload: %s", string(p1))
	}

	_, p2, err := cConn2.ReadMessage()
	if err != nil {
		t.Fatalf("kds client read error: %v", err)
	}
	if string(p2) != string(kdsPayload) {
		t.Fatalf("kds received wrong payload: %s", string(p2))
	}

	hub.Unregister(staffClient)
	if hub.ClientCount() != 1 {
		t.Fatalf("expected 1 client after unregister, got %d", hub.ClientCount())
	}
}

func TestHubBackpressureSlowClientDisconnect(t *testing.T) {
	hub := NewHub()
	defer hub.Close()

	sPipe, cPipe := net.Pipe()
	defer sPipe.Close()
	defer cPipe.Close()

	slowClient := NewClient(hub, NewConn(sPipe), "STAFF", "slow-staff")
	hub.Register(slowClient)

	// Fill the buffer completely
	for i := 0; i < clientSendBufferSize; i++ {
		slowClient.send <- []byte("fill")
	}

	// Next broadcast should trigger slow client disconnect
	hub.Broadcast([]byte("overflow"), []byte("overflow"))

	time.Sleep(50 * time.Millisecond)
	if hub.ClientCount() != 0 {
		t.Fatalf("expected slow client to be disconnected, client count=%d", hub.ClientCount())
	}
}
