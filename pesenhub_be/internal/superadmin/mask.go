package superadmin

import "strings"

// MaskEmail masks the local part of an email while keeping domain visible.
func MaskEmail(email string) string {
	email = strings.TrimSpace(email)
	if email == "" {
		return ""
	}
	parts := strings.Split(email, "@")
	if len(parts) != 2 {
		return "***"
	}
	local := parts[0]
	domain := parts[1]
	if len(local) <= 2 {
		return local[:1] + "***@" + domain
	}
	return local[:2] + "***@" + domain
}

// MaskIdentifier masks arbitrary long identifiers or device tokens.
func MaskIdentifier(id string) string {
	id = strings.TrimSpace(id)
	if len(id) <= 6 {
		return "***"
	}
	return id[:3] + "..." + id[len(id)-3:]
}
