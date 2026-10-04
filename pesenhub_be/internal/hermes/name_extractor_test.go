package hermes

import "testing"

func TestExtractCustomerName(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"Halo nama saya Yoga", "Yoga"},
		{"Halo kak namaku Budi Pratama", "Budi Pratama"},
		{"Panggil saya Rina aja", "Rina Aja"}, // two words
		{"Panggil saya Rina", "Rina"},
		{"Halo saya Yoga, mau pesan martabak", "Yoga"},
		{"Atas nama Dimas", "Dimas"},
		{"a/n Siti", "Siti"},
		{"Saya mau pesan martabak telur 1", ""}, // 'mau' is not a name
		{"Halo kak", ""},
		{"Berapa harga terang bulan?", ""},
	}

	for _, tt := range tests {
		got := ExtractCustomerName(tt.input)
		if got != tt.expected {
			t.Errorf("ExtractCustomerName(%q) = %q, expected %q", tt.input, got, tt.expected)
		}
	}
}
