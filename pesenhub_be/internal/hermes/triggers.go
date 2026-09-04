package hermes

import (
	"regexp"
	"strings"
)

var (
	complaintPatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)\b(komplain|kecewa|marah|pelayanan buruk|lama banget|gak beres|tidak beres|kapok|pesanan salah|salah pesanan)\b`),
	}

	humanRequestPatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)\b(bicara|ngomong|hubungin|hubungi|minta|mau)\s+(sama\s+|dengan\s+|ke\s+)?(manusia|orang|staf|staff|admin|cs|customer service)\b`),
		regexp.MustCompile(`(?i)\b(jangan bot|bukan bot|jangan ai|bukan ai|bisa bicara sama orang|panggil admin|panggil staf)\b`),
	}

	outOfScopePatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)\b(pinjam(an)?\s+uang|pinjol|dana gaib|kredit tanpa agunan)\b`),
		regexp.MustCompile(`(?i)\b(lowongan\s+kerja|loker|ada loker|buka lowongan|terima karyawan)\b`),
		regexp.MustCompile(`(?i)\b(servis\s+motor|bengkel|ganti oli|jual mobil|sparepart)\b`),
		regexp.MustCompile(`(?i)\b(siapa presiden|ramalan cuaca|jadwal bioskop|info gempa|kurs dollar)\b`),
	}
)

// DetectComplaint detects whether the customer message is a complaint or explicit human takeover request.
func DetectComplaint(text string) (bool, string, string) {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return false, "", ""
	}

	for _, p := range humanRequestPatterns {
		if p.MatchString(trimmed) {
			return true, "customer_requested_human", HandoffPriorityHigh
		}
	}

	for _, p := range complaintPatterns {
		if p.MatchString(trimmed) {
			return true, "customer_complaint", HandoffPriorityUrgent
		}
	}

	return false, "", ""
}

// DetectOutOfScope detects whether the customer message is outside restaurant ordering domain.
func DetectOutOfScope(text string) (bool, string, string) {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return false, "", ""
	}

	for _, p := range outOfScopePatterns {
		if p.MatchString(trimmed) {
			return true, "out_of_scope_inquiry", HandoffPriorityLow
		}
	}

	return false, "", ""
}
