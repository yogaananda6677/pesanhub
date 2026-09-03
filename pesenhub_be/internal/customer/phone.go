package customer

import (
	"errors"
	"strings"
	"unicode"
)

var ErrInvalidPhone = errors.New("invalid Indonesian mobile phone number")

// NormalizeIndonesia maps common Indonesian mobile notation to E.164. It
// intentionally accepts only mobile NSNs beginning with 8, not arbitrary PSTN.
func NormalizeIndonesia(raw string) (string, error) {
	var b strings.Builder
	for i, r := range strings.TrimSpace(raw) {
		if unicode.IsDigit(r) {
			if r > unicode.MaxASCII {
				return "", ErrInvalidPhone
			}
			b.WriteRune(r)
			continue
		}
		if r == '+' && i == 0 {
			b.WriteRune(r)
			continue
		}
		if strings.ContainsRune(" -().", r) {
			continue
		}
		return "", ErrInvalidPhone
	}
	n := b.String()
	switch {
	case strings.HasPrefix(n, "+62"):
		n = n[3:]
	case strings.HasPrefix(n, "62"):
		n = n[2:]
	case strings.HasPrefix(n, "0"):
		n = n[1:]
	case strings.HasPrefix(n, "8"):
	default:
		return "", ErrInvalidPhone
	}
	if len(n) < 9 || len(n) > 12 || n[0] != '8' {
		return "", ErrInvalidPhone
	}
	for _, r := range n {
		if r < '0' || r > '9' {
			return "", ErrInvalidPhone
		}
	}
	return "+62" + n, nil
}
