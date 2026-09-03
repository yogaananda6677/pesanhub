package ws

import (
	"sync"
	"time"
)

const (
	clientSendBufferSize = 256
	defaultPingInterval  = 15 * time.Second
	writeTimeout         = 5 * time.Second
)

type Client struct {
	hub     *Hub
	conn    *Conn
	Role    string
	Subject string
	send    chan []byte
	done    chan struct{}
	once    sync.Once
}

func NewClient(hub *Hub, conn *Conn, role, subject string) *Client {
	return &Client{
		hub:     hub,
		conn:    conn,
		Role:    role,
		Subject: subject,
		send:    make(chan []byte, clientSendBufferSize),
		done:    make(chan struct{}),
	}
}

func (c *Client) Close() {
	c.once.Do(func() {
		close(c.done)
		_ = c.conn.Close()
	})
}

func (c *Client) WritePump(pingInterval time.Duration) {
	if pingInterval <= 0 {
		pingInterval = defaultPingInterval
	}
	ticker := time.NewTicker(pingInterval)
	defer func() {
		ticker.Stop()
		c.hub.Unregister(c)
		c.Close()
	}()

	for {
		select {
		case <-c.done:
			return
		case msg, ok := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeTimeout))
			if !ok {
				_ = c.conn.WriteClose()
				return
			}
			if err := c.conn.WriteText(msg); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeTimeout))
			if err := c.conn.WritePing([]byte("ping")); err != nil {
				return
			}
		}
	}
}

func (c *Client) ReadPump() {
	defer func() {
		c.hub.Unregister(c)
		c.Close()
	}()

	for {
		_, _, err := c.conn.ReadMessage()
		if err != nil {
			return
		}
	}
}

type Hub struct {
	mu      sync.RWMutex
	clients map[*Client]struct{}
	closed  bool
}

func NewHub() *Hub {
	return &Hub{
		clients: make(map[*Client]struct{}),
	}
}

func (h *Hub) Register(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.closed {
		client.Close()
		return
	}
	h.clients[client] = struct{}{}
}

func (h *Hub) Unregister(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if _, ok := h.clients[client]; ok {
		delete(h.clients, client)
		close(client.send)
	}
}

func (h *Hub) ClientCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}

func (h *Hub) Broadcast(staffPayload, kdsPayload []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	if h.closed {
		return
	}

	for client := range h.clients {
		var payload []byte
		if client.Role == "KDS" {
			payload = kdsPayload
		} else {
			payload = staffPayload
		}

		select {
		case client.send <- payload:
		default:
			// Backpressure handling: slow client queue full, disconnect slow client
			go func(c *Client) {
				h.Unregister(c)
				c.Close()
			}(client)
		}
	}
}

func (h *Hub) Close() {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.closed {
		return
	}
	h.closed = true
	for client := range h.clients {
		delete(h.clients, client)
		close(client.send)
		client.Close()
	}
}
