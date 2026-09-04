package waha

import (
	"testing"
)

func TestNormalizeSenderPhone(t *testing.T) {
	tests := []struct {
		name           string
		raw            string
		wantPhone      string
		wantQuarantine bool
		wantReason     string
	}{
		{
			name:           "standard waha jid",
			raw:            "628123456789@c.us",
			wantPhone:      "+628123456789",
			wantQuarantine: false,
		},
		{
			name:           "jid with device suffix",
			raw:            "628123456789:12@s.whatsapp.net",
			wantPhone:      "+628123456789",
			wantQuarantine: false,
		},
		{
			name:           "08 local format",
			raw:            "081234567890",
			wantPhone:      "+6281234567890",
			wantQuarantine: false,
		},
		{
			name:           "already e164",
			raw:            "+6281234567890",
			wantPhone:      "+6281234567890",
			wantQuarantine: false,
		},
		{
			name:           "group jid",
			raw:            "120363025412345678@g.us",
			wantPhone:      "",
			wantQuarantine: true,
			wantReason:     "group_message_not_supported",
		},
		{
			name:           "status broadcast",
			raw:            "status@broadcast",
			wantPhone:      "",
			wantQuarantine: true,
			wantReason:     "broadcast_ignored",
		},
		{
			name:           "us international number",
			raw:            "15551234567@c.us",
			wantPhone:      "",
			wantQuarantine: true,
			wantReason:     "unsupported_country_code_or_prefix",
		},
		{
			name:           "empty sender",
			raw:            "   ",
			wantPhone:      "",
			wantQuarantine: true,
			wantReason:     "empty_sender",
		},
		{
			name:           "too short",
			raw:            "0812@c.us",
			wantPhone:      "",
			wantQuarantine: true,
			wantReason:     "invalid_phone_length",
		},
		{
			name:           "alphabetic characters in phone",
			raw:            "62812ABCD890@c.us",
			wantPhone:      "",
			wantQuarantine: true,
			wantReason:     "invalid_phone_characters",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotPhone, gotQuarantined, gotReason := NormalizeSenderPhone(tt.raw)
			if gotQuarantined != tt.wantQuarantine {
				t.Fatalf("NormalizeSenderPhone(%q) gotQuarantined=%v, want=%v", tt.raw, gotQuarantined, tt.wantQuarantine)
			}
			if gotPhone != tt.wantPhone {
				t.Fatalf("NormalizeSenderPhone(%q) gotPhone=%q, want=%q", tt.raw, gotPhone, tt.wantPhone)
			}
			if tt.wantQuarantine && gotReason != tt.wantReason {
				t.Fatalf("NormalizeSenderPhone(%q) gotReason=%q, want=%q", tt.raw, gotReason, tt.wantReason)
			}
		})
	}
}

func TestMaskPhone(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{input: "+6281234567890", want: "+6281****7890"},
		{input: "081234567890", want: "0812****7890"},
		{input: "123", want: "[REDACTED]"},
		{input: "", want: "[REDACTED]"},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got := MaskPhone(tt.input)
			if got != tt.want {
				t.Fatalf("MaskPhone(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}
