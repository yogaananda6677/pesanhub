package customer

import "testing"

func TestNormalizeIndonesia(t *testing.T) {
	for _, input := range []string{"0812-3456-7890", "6281234567890", "+62 812 3456 7890", "81234567890"} {
		got, err := NormalizeIndonesia(input)
		if err != nil || got != "+6281234567890" {
			t.Errorf("NormalizeIndonesia(%q) = %q, %v", input, got, err)
		}
	}
}

func TestNormalizeIndonesiaRejectsInvalid(t *testing.T) {
	for _, input := range []string{"", "+621234", "+14155552671", "0812abc", "0215551234", "081234567890123"} {
		if got, err := NormalizeIndonesia(input); err == nil {
			t.Errorf("NormalizeIndonesia(%q) unexpectedly returned %q", input, got)
		}
	}
}
