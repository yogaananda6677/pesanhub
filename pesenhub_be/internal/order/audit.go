package order

import (
	"encoding/json"
	"fmt"
	"strings"
)

// MaskPhone masks the middle digits of a phone number to prevent PII exposure in logs.
// For example: "+6281234567890" -> "+62812****7890".
func MaskPhone(phone string) string {
	phone = strings.TrimSpace(phone)
	if phone == "" {
		return ""
	}
	if len(phone) < 8 {
		return "****"
	}
	prefixLen := 6
	suffixLen := 4
	if len(phone) < prefixLen+suffixLen {
		prefixLen = len(phone) / 2
		suffixLen = len(phone) - prefixLen
		return phone[:prefixLen] + "****" + phone[len(phone)-suffixLen:]
	}
	return phone[:prefixLen] + "****" + phone[len(phone)-suffixLen:]
}

// SanitizeAuditMetadata produces a safe JSON object for the metadata_redacted column.
// Sensitive keys such as phone numbers are masked, and tokens/secrets are redacted.
func SanitizeAuditMetadata(raw map[string]any) []byte {
	if raw == nil {
		return []byte("{}")
	}

	sanitized := make(map[string]any, len(raw))
	for k, v := range raw {
		lowerKey := strings.ToLower(k)
		switch {
		case strings.Contains(lowerKey, "phone"):
			if s, ok := v.(string); ok {
				sanitized[k] = MaskPhone(s)
			} else {
				sanitized[k] = MaskPhone(fmt.Sprint(v))
			}
		case strings.Contains(lowerKey, "token") || strings.Contains(lowerKey, "secret") || strings.Contains(lowerKey, "password"):
			sanitized[k] = "[REDACTED]"
		default:
			sanitized[k] = v
		}
	}

	b, err := json.Marshal(sanitized)
	if err != nil {
		return []byte("{}")
	}
	return b
}
