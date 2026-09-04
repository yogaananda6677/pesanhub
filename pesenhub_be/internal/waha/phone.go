package waha

import (
	"strings"
)

// NormalizeSenderPhone normalizes a sender JID or phone number into an Indonesian E.164 number.
// If the sender is invalid, from a group, broadcast, or non-Indonesian number, it marks the sender
// as quarantined with a specific reason string, without producing a fake customer.
func NormalizeSenderPhone(rawJID string) (phoneE164 string, isQuarantined bool, reason string) {
	raw := strings.TrimSpace(rawJID)
	if raw == "" {
		return "", true, "empty_sender"
	}

	// 1. Quarantine groups and broadcast
	if strings.HasSuffix(raw, "@g.us") || strings.Contains(raw, "@g.us") {
		return "", true, "group_message_not_supported"
	}
	if strings.HasSuffix(raw, "@broadcast") || strings.Contains(raw, "@broadcast") {
		return "", true, "broadcast_ignored"
	}

	// 2. Strip JID domain suffix
	if idx := strings.Index(raw, "@"); idx != -1 {
		raw = raw[:idx]
	}

	// 3. Strip device ID suffix (e.g. "628123456789:2")
	if idx := strings.Index(raw, ":"); idx != -1 {
		raw = raw[:idx]
	}

	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", true, "invalid_phone_number"
	}

	// 4. Normalize Indonesian phone prefix
	if strings.HasPrefix(raw, "08") {
		raw = "+628" + raw[2:]
	} else if strings.HasPrefix(raw, "628") {
		raw = "+" + raw
	} else if !strings.HasPrefix(raw, "+628") {
		return "", true, "unsupported_country_code_or_prefix"
	}

	// 5. Verify digit validity and length (10 to 15 digits total after '+')
	digits := raw[1:] // after '+'
	if len(digits) < 10 || len(digits) > 15 {
		return "", true, "invalid_phone_length"
	}
	for _, c := range digits {
		if c < '0' || c > '9' {
			return "", true, "invalid_phone_characters"
		}
	}

	return raw, false, ""
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
