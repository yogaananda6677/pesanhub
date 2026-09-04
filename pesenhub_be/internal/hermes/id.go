package hermes

import (
	"crypto/rand"
	"fmt"
	"strings"
)

func newID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic("secure random source unavailable")
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// MaskPhone masks a phone number for privacy-safe logging (e.g. "+62812****7890").
func MaskPhone(phone string) string {
	phone = strings.TrimSpace(phone)
	if len(phone) <= 7 {
		return "[REDACTED]"
	}
	if strings.HasPrefix(phone, "+") && len(phone) >= 9 {
		prefix := phone[:5]
		suffix := phone[len(phone)-4:]
		return prefix + "****" + suffix
	}
	if len(phone) >= 8 {
		prefix := phone[:4]
		suffix := phone[len(phone)-4:]
		return prefix + "****" + suffix
	}
	return "[REDACTED]"
}
