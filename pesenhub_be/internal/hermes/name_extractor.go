package hermes

import (
	"regexp"
	"strings"
)

var (
	nameRegexIntro  = regexp.MustCompile(`(?i)\b(?:nama\s+saya|namaku|nama\s+gw|nama\s+gue)\s+([a-zA-Z\s]{2,30})`)
	nameRegexCall   = regexp.MustCompile(`(?i)\b(?:panggil\s+saya|panggil\s+aja|panggil\s+ku)\s+([a-zA-Z\s]{2,30})`)
	nameRegexAtas   = regexp.MustCompile(`(?i)\b(?:atas\s+nama|a/n|\ban\b)\s+([a-zA-Z\s]{2,30})`)
	nameRegexSaya   = regexp.MustCompile(`(?i)^(?:halo|hai|hi|hey)?\s*(?:kak\s*)?(?:saya|aku)\s+([a-zA-Z]{2,20})(?:[,.\s]|$)`)
	nameRegexDengan = regexp.MustCompile(`(?i)\b(?:dengan|sama)\s+(?:kak\s+)?([a-zA-Z\s]{2,30})`)
	nameRegexKak    = regexp.MustCompile(`(?i)^([a-zA-Z]{2,20})\s+(?:kak|min|ya|aja|mas|mbak)[\s.!,]*$`)
)

var commonNonNames = map[string]bool{
	// Question words & pronouns
	"siapa": true, "siapakah": true, "apa": true, "apakah": true, "kenapa": true,
	"mengapa": true, "bagaimana": true, "gimana": true, "mana": true, "kapan": true,
	"ngapain": true, "berapa": true, "siap": true, "siapaan": true,

	// Negations & corrections
	"bukan": true, "bukanlah": true, "bkn": true, "gak": true, "nggak": true,
	"ngga": true, "tidak": true, "tdk": true, "batal": true, "jangan": true,
	"tapi": true, "tp": true, "tetapi": true, "melainkan": true,

	// Common verbs
	"mau": true, "ingin": true, "pesan": true, "order": true, "bisa": true,
	"minta": true, "beli": true, "kirim": true, "ambil": true, "tahu": true,
	"tau": true, "kenal": true, "buka": true, "tutup": true, "tanya": true,
	"panggil": true, "bilang": true, "kasih": true, "terima": true, "makasih": true,

	// Particles & fillers
	"dong": true, "sih": true, "nih": true, "deh": true, "kan": true, "kok": true,
	"aja": true, "saja": true, "ya": true, "iya": true, "oke": true, "ok": true,
	"kah": true, "lah": true, "pun": true, "ta": true, "yuk": true, "kuy": true,

	// Greetings & honorifics
	"halo": true, "hai": true, "hey": true, "hi": true, "hei": true,
	"kak": true, "kakak": true, "min": true, "admin": true, "mas": true,
	"mbak": true, "bang": true, "om": true, "tante": true, "gan": true,
	"bos": true, "boss": true, "bro": true, "sis": true, "pak": true, "bu": true,

	// Pronouns & roles
	"saya": true, "aku": true, "gw": true, "gue": true, "kamu": true, "anda": true,
	"kita": true, "kami": true, "dia": true, "mereka": true,
	"pelanggan": true, "pembeli": true, "customer": true, "orang": true,
	"bot": true, "ai": true, "cs": true, "jenggirat": true,

	// Menu & food terms
	"menu": true, "katalog": true, "pricelist": true, "harga": true, "foto": true,
	"gambar": true, "alamat": true, "lokasi": true, "posisi": true, "struk": true,
	"nota": true, "bon": true, "martabak": true, "terang": true, "bulan": true,
	"terbul": true, "martel": true, "telur": true, "telor": true, "pedas": true,
	"manis": true, "asin": true, "biasa": true, "spesial": true, "istimewa": true,
	"coklat": true, "keju": true, "kacang": true, "ayam": true, "sapi": true,
	"sosis": true, "jamur": true, "topping": true, "toping": true, "adonan": true,
	"pandan": true, "red": true, "velvet": true, "taro": true, "mocca": true,

	// Status / time words
	"baru": true, "sudah": true, "udah": true, "lagi": true, "sedang": true,
	"masih": true, "belum": true, "belom": true, "kelar": true, "beres": true,
	"jadi": true, "hari": true, "ini": true, "itu": true, "di": true, "ke": true,
	"dari": true, "yang": true, "dan": true, "atau": true,
}

// cleanCandidateName truncates candidate string at punctuation and negation/correction words.
func cleanCandidateName(candidate string) string {
	candidate = strings.TrimSpace(candidate)
	for _, sep := range []string{",", ";", "?", "!", "\n"} {
		if idx := strings.Index(candidate, sep); idx != -1 {
			candidate = candidate[:idx]
		}
	}

	candidateLower := strings.ToLower(candidate)
	cutWords := []string{
		" bukan", " bukanlah", " bkn", " tapi", " tp", " tetapi", " melainkan",
		" aja", " saja", " ya", " kok", " dong", " kak", " mas", " mbak", " min",
	}
	for _, cw := range cutWords {
		if idx := strings.Index(candidateLower, cw); idx != -1 {
			candidate = candidate[:idx]
			candidateLower = strings.ToLower(candidate)
		}
	}
	return strings.TrimSpace(candidate)
}

// ExtractCustomerName parses conversational introductions to extract the customer's name.
func ExtractCustomerName(text string) string {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" || strings.Contains(trimmed, "?") || DetectNameInquiry(trimmed) {
		return ""
	}

	for _, re := range []*regexp.Regexp{nameRegexIntro, nameRegexCall, nameRegexAtas, nameRegexSaya, nameRegexDengan, nameRegexKak} {
		matches := re.FindStringSubmatch(trimmed)
		if len(matches) >= 2 {
			candidate := cleanCandidateName(matches[1])
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

// ExtractBareCustomerName extracts a name when the bot explicitly asked for the customer's name.
func ExtractBareCustomerName(text string) string {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" || strings.Contains(trimmed, "?") || DetectNameInquiry(trimmed) {
		return ""
	}
	if n := ExtractCustomerName(trimmed); n != "" {
		return n
	}
	cleaned := cleanCandidateName(trimmed)
	words := strings.Fields(cleaned)
	if len(words) == 1 || len(words) == 2 {
		first := strings.ToLower(words[0])
		if commonNonNames[first] || len(first) < 2 {
			return ""
		}
		for _, r := range words[0] {
			if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')) {
				return ""
			}
		}
		clean := titleCase(words[0])
		if len(words) == 2 {
			second := strings.ToLower(words[1])
			if commonNonNames[second] || len(second) < 2 || len(second) > 15 {
				return clean
			}
			for _, r := range words[1] {
				if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')) {
					return clean
				}
			}
			clean += " " + titleCase(words[1])
		}
		return clean
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
