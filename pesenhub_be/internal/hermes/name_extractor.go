package hermes

import (
	"regexp"
	"strings"
)

var (
	nameRegexIntro = regexp.MustCompile(`(?i)\b(?:nama\s+saya|namaku|nama\s+gw|nama\s+gue)\s+([a-zA-Z\s]{2,30})`)
	nameRegexCall  = regexp.MustCompile(`(?i)\b(?:panggil\s+saya|panggil\s+aja|panggil\s+ku)\s+([a-zA-Z\s]{2,30})`)
	nameRegexAtas  = regexp.MustCompile(`(?i)\b(?:atas\s+nama|a/n|\ban\b)\s+([a-zA-Z\s]{2,30})`)
	nameRegexSaya  = regexp.MustCompile(`(?i)^(?:halo|hai|hi|hey)?\s*(?:kak\s*)?(?:saya|aku)\s+([a-zA-Z]{2,20})(?:[,.\s]|$)`)
)

var commonNonNames = map[string]bool{
	"mau": true, "ingin": true, "pesan": true, "order": true, "bisa": true,
	"pelanggan": true, "pembeli": true, "customer": true, "orang": true,
	"minta": true, "beli": true, "batal": true, "gak": true, "nggak": true,
	"tidak": true, "lagi": true, "baru": true, "sudah": true, "udah": true,
	"di": true, "ke": true, "dari": true, "yang": true, "ini": true,
}

// ExtractCustomerName parses conversational introductions to extract the customer's name.
func ExtractCustomerName(text string) string {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return ""
	}

	for _, re := range []*regexp.Regexp{nameRegexIntro, nameRegexCall, nameRegexAtas, nameRegexSaya} {
		matches := re.FindStringSubmatch(trimmed)
		if len(matches) >= 2 {
			candidate := strings.TrimSpace(matches[1])
			words := strings.Fields(candidate)
			if len(words) == 0 {
				continue
			}
			firstWordLower := strings.ToLower(words[0])
			if commonNonNames[firstWordLower] || len(words[0]) < 2 {
				continue
			}
			clean := titleCase(words[0])
			if len(words) > 1 && !commonNonNames[strings.ToLower(words[1])] && len(words[1]) <= 15 {
				clean += " " + titleCase(words[1])
			}
			return clean
		}
	}
	return ""
}

func titleCase(s string) string {
	if s == "" {
		return ""
	}
	lower := strings.ToLower(s)
	return strings.ToUpper(lower[:1]) + lower[1:]
}
