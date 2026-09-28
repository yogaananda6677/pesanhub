package inviteemail

import "testing"

func TestNewGmailSenderValidatesHeadersAndRecipientConfiguration(t *testing.T) {
	if _, err := NewGmailSender("sender@gmail.com", "abcd efgh ijkl mnop", "PesenHub", "https://app.example.test"); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		name, username, fromName string
	}{
		{"invalid sender", "not-an-email", "PesenHub"},
		{"header injection", "sender@gmail.com", "PesenHub\r\nBcc: attacker@example.test"},
	} {
		t.Run(test.name, func(t *testing.T) {
			if _, err := NewGmailSender(test.username, "abcdefghijklmnop", test.fromName, "https://app.example.test"); err == nil {
				t.Fatal("expected invalid configuration")
			}
		})
	}
}
