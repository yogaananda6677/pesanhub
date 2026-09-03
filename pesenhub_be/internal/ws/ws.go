package ws

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

const (
	websocketMagicGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	maxPayloadSize     = 10 * 1024 * 1024 // 10MB
)

const (
	OpcodeText   = 0x1
	OpcodeBinary = 0x2
	OpcodeClose  = 0x8
	OpcodePing   = 0x9
	OpcodePong   = 0xA
)

var (
	ErrNotWebsocket = errors.New("request is not a valid websocket upgrade")
	ErrClosed       = errors.New("websocket connection closed")
)

type Conn struct {
	netConn net.Conn
	rw      *bufio.ReadWriter
	mu      sync.Mutex
	closed  bool
}

func Upgrade(w http.ResponseWriter, r *http.Request) (*Conn, error) {
	if !strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
		return nil, ErrNotWebsocket
	}
	connHeader := strings.ToLower(r.Header.Get("Connection"))
	if !strings.Contains(connHeader, "upgrade") {
		return nil, ErrNotWebsocket
	}
	key := strings.TrimSpace(r.Header.Get("Sec-WebSocket-Key"))
	if key == "" {
		return nil, ErrNotWebsocket
	}

	hj, ok := w.(http.Hijacker)
	if !ok {
		return nil, errors.New("response writer does not support hijacking")
	}

	netConn, rw, err := hj.Hijack()
	if err != nil {
		return nil, err
	}

	h := sha1.New()
	h.Write([]byte(key + websocketMagicGUID))
	accept := base64.StdEncoding.EncodeToString(h.Sum(nil))

	res := "HTTP/1.1 101 Switching Protocols\r\n" +
		"Upgrade: websocket\r\n" +
		"Connection: Upgrade\r\n" +
		"Sec-WebSocket-Accept: " + accept + "\r\n\r\n"

	if _, err := rw.WriteString(res); err != nil {
		_ = netConn.Close()
		return nil, err
	}
	if err := rw.Flush(); err != nil {
		_ = netConn.Close()
		return nil, err
	}

	return &Conn{
		netConn: netConn,
		rw:      rw,
	}, nil
}

func NewConn(netConn net.Conn) *Conn {
	return &Conn{
		netConn: netConn,
		rw:      bufio.NewReadWriter(bufio.NewReader(netConn), bufio.NewWriter(netConn)),
	}
}

func (c *Conn) WriteText(payload []byte) error {
	return c.writeFrame(OpcodeText, payload)
}

func (c *Conn) WritePing(payload []byte) error {
	return c.writeFrame(OpcodePing, payload)
}

func (c *Conn) WritePong(payload []byte) error {
	return c.writeFrame(OpcodePong, payload)
}

func (c *Conn) WriteClose() error {
	return c.writeFrame(OpcodeClose, nil)
}

func (c *Conn) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return nil
	}
	c.closed = true
	_ = c.writeFrameLocked(OpcodeClose, nil)
	return c.netConn.Close()
}

func (c *Conn) SetReadDeadline(t time.Time) error {
	return c.netConn.SetReadDeadline(t)
}

func (c *Conn) SetWriteDeadline(t time.Time) error {
	return c.netConn.SetWriteDeadline(t)
}

func (c *Conn) writeFrame(opcode byte, payload []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.writeFrameLocked(opcode, payload)
}

func (c *Conn) writeFrameLocked(opcode byte, payload []byte) error {
	if c.closed && opcode != OpcodeClose {
		return ErrClosed
	}

	length := len(payload)
	var header []byte
	b0 := byte(0x80 | (opcode & 0x0F))

	if length <= 125 {
		header = []byte{b0, byte(length)}
	} else if length <= 65535 {
		header = []byte{b0, 126, byte(length >> 8), byte(length)}
	} else {
		header = make([]byte, 10)
		header[0] = b0
		header[1] = 127
		binary.BigEndian.PutUint64(header[2:], uint64(length))
	}

	if _, err := c.rw.Write(header); err != nil {
		return err
	}
	if length > 0 {
		if _, err := c.rw.Write(payload); err != nil {
			return err
		}
	}
	return c.rw.Flush()
}

func (c *Conn) ReadMessage() (byte, []byte, error) {
	for {
		opcode, payload, err := c.readFrame()
		if err != nil {
			return 0, nil, err
		}
		switch opcode {
		case OpcodePing:
			_ = c.WritePong(payload)
			continue
		case OpcodePong:
			continue
		case OpcodeClose:
			_ = c.Close()
			return OpcodeClose, nil, io.EOF
		default:
			return opcode, payload, nil
		}
	}
}

func (c *Conn) readFrame() (byte, []byte, error) {
	var h [2]byte
	if _, err := io.ReadFull(c.rw, h[:]); err != nil {
		return 0, nil, err
	}

	opcode := h[0] & 0x0F
	masked := (h[1] & 0x80) != 0
	lenByte := h[1] & 0x7F

	var length uint64
	if lenByte <= 125 {
		length = uint64(lenByte)
	} else if lenByte == 126 {
		var b [2]byte
		if _, err := io.ReadFull(c.rw, b[:]); err != nil {
			return 0, nil, err
		}
		length = uint64(binary.BigEndian.Uint16(b[:]))
	} else if lenByte == 127 {
		var b [8]byte
		if _, err := io.ReadFull(c.rw, b[:]); err != nil {
			return 0, nil, err
		}
		length = binary.BigEndian.Uint64(b[:])
	}

	if length > maxPayloadSize {
		return 0, nil, errors.New("frame payload exceeds maximum size")
	}

	var mask [4]byte
	if masked {
		if _, err := io.ReadFull(c.rw, mask[:]); err != nil {
			return 0, nil, err
		}
	}

	payload := make([]byte, length)
	if length > 0 {
		if _, err := io.ReadFull(c.rw, payload); err != nil {
			return 0, nil, err
		}
		if masked {
			for i := 0; i < len(payload); i++ {
				payload[i] ^= mask[i%4]
			}
		}
	}

	return opcode, payload, nil
}
