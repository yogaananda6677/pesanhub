package hermes

import "testing"

func TestExtractCustomerName(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"Halo nama saya Yoga", "Yoga"},
		{"Halo kak namaku Budi Pratama", "Budi Pratama"},
		{"Panggil saya Rina aja", "Rina"},
		{"Panggil saya Rina", "Rina"},
		{"Halo saya Yoga, mau pesan martabak", "Yoga"},
		{"Atas nama Dimas", "Dimas"},
		{"a/n Siti", "Siti"},
		{"dengan Doni", "Doni"},
		{"sama kak Doni", "Doni"},
		{"Rian kak", "Rian"},
		{"Siti ya", "Siti"},
		{"Saya mau pesan martabak telur 1", ""}, // 'mau' is not a name
		{"Halo kak", ""},
		{"Berapa harga terang bulan?", ""},
		// Inquiries should NOT extract a name
		{"nama saya siapa", ""},
		{"nama saya siapa ya?", ""},
		{"siapa nama saya", ""},
		{"tau nama saya gak", ""},
		// Negation / correction stripping
		{"nama saya Yoga bukan siapa!", "Yoga"},
		{"nama saya Yoga bukan siapa", "Yoga"},
		{"nama saya Yoga, bukan siapa", "Yoga"},
		{"namaku Dimas tapi bukan siapa", "Dimas"},
	}

	for _, tt := range tests {
		got := ExtractCustomerName(tt.input)
		if got != tt.expected {
			t.Errorf("ExtractCustomerName(%q) = %q, expected %q", tt.input, got, tt.expected)
		}
	}
}

func TestExtractBareCustomerName(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"Doni", "Doni"},
		{"Doni Santoso", "Doni Santoso"},
		{"doni", "Doni"},
		{"siti nurhaliza", "Siti Nurhaliza"},
		{"martabak", ""},
		{"pedas", ""},
		{"oke", ""},
		{"siap", ""},
		{"123", ""},
		{"siapa", ""},
		{"nama saya siapa", ""},
		{"Yoga bukan siapa!", "Yoga"},
	}

	for _, tt := range tests {
		got := ExtractBareCustomerName(tt.input)
		if got != tt.expected {
			t.Errorf("ExtractBareCustomerName(%q) = %q, expected %q", tt.input, got, tt.expected)
		}
	}
}

func TestDetectNameInquiry(t *testing.T) {
	tests := []struct {
		input    string
		expected bool
	}{
		{"nama saya siapa", true},
		{"nama saya siapa?", true},
		{"nama saya siapa ya", true},
		{"namaku siapa", true},
		{"nama ku siapa dong", true},
		{"siapa nama saya", true},
		{"siapa namaku", true},
		{"tau nama saya gak", true},
		{"tahu nama saya gak?", true},
		{"kamu tau nama aku gak", true},
		{"kenal saya gak", true},
		{"nama saya Yoga", false},
		{"nama saya Yoga bukan siapa!", false},
		{"halo kak", false},
		{"minta katalog dong", false},
		{"pesan martabak telur 1", false},
	}

	for _, tt := range tests {
		got := DetectNameInquiry(tt.input)
		if got != tt.expected {
			t.Errorf("DetectNameInquiry(%q) = %v, expected %v", tt.input, got, tt.expected)
		}
	}
}
