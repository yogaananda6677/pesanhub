package superadmin

import (
	"testing"
)

func TestMaskEmail(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"user@example.com", "us***@example.com"},
		{"ab@example.com", "a***@example.com"},
		{"a@example.com", "a***@example.com"},
		{"superadmin@pesenhub.id", "su***@pesenhub.id"},
		{"invalid-email", "***"},
		{"", ""},
	}

	for _, tc := range tests {
		result := MaskEmail(tc.input)
		if result != tc.expected {
			t.Errorf("MaskEmail(%q) = %q, expected %q", tc.input, result, tc.expected)
		}
	}
}

func TestMaskIdentifier(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"1234567890", "123...890"},
		{"abcdefgh", "abc...fgh"},
		{"short", "***"},
		{"123456", "***"},
		{"", "***"},
	}

	for _, tc := range tests {
		result := MaskIdentifier(tc.input)
		if result != tc.expected {
			t.Errorf("MaskIdentifier(%q) = %q, expected %q", tc.input, result, tc.expected)
		}
	}
}
