package waha

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestParseInboundMessage(t *testing.T) {
	now := time.Date(2026, 9, 4, 12, 0, 0, 0, time.UTC)

	t.Run("valid inbound message", func(t *testing.T) {
		body := []byte(`{
			"event": "message",
			"session": "default",
			"payload": {
				"id": "false_6281234567890@c.us_3EB0123456",
				"timestamp": 1725451200,
				"from": "6281234567890@c.us",
				"fromMe": false,
				"to": "628999999999@c.us",
				"body": "halo pesan nasi goreng 2 porsi",
				"_data": {
					"notifyName": "Budi Santoso"
				}
			}
		}`)

		msg, isMsg, isFromMe, err := ParseInboundMessage(body, "req-1", now)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !isMsg {
			t.Fatal("expected isMsg to be true")
		}
		if isFromMe {
			t.Fatal("expected isFromMe to be false")
		}
		if msg == nil {
			t.Fatal("expected msg to not be nil")
		}
		if msg.ProviderMessageID != "false_6281234567890@c.us_3EB0123456" {
			t.Fatalf("unexpected provider ID: %s", msg.ProviderMessageID)
		}
		if msg.PhoneE164 == nil || *msg.PhoneE164 != "+6281234567890" {
			t.Fatalf("unexpected phone: %v", msg.PhoneE164)
		}
		if msg.SenderName != "Budi Santoso" {
			t.Fatalf("unexpected sender name: %s", msg.SenderName)
		}
		if msg.MessageBody != "halo pesan nasi goreng 2 porsi" {
			t.Fatalf("unexpected body: %s", msg.MessageBody)
		}
		if msg.Status != StatusReceived {
			t.Fatalf("unexpected status: %s", msg.Status)
		}
		if msg.QuarantineReason != "" {
			t.Fatalf("unexpected quarantine reason: %s", msg.QuarantineReason)
		}
	})

	t.Run("outgoing message fromMe ignored", func(t *testing.T) {
		body := []byte(`{
			"event": "message.any",
			"session": "default",
			"payload": {
				"id": "true_6281234567890@c.us_3EB09999",
				"from": "628999999999@c.us",
				"fromMe": true,
				"body": "Pesanan Anda sedang dimasak"
			}
		}`)

		msg, isMsg, isFromMe, err := ParseInboundMessage(body, "req-2", now)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !isMsg || !isFromMe {
			t.Fatalf("expected isMsg=true, isFromMe=true, got isMsg=%v, isFromMe=%v", isMsg, isFromMe)
		}
		if msg != nil {
			t.Fatal("expected msg to be nil for fromMe")
		}
	})

	t.Run("group message is quarantined", func(t *testing.T) {
		body := []byte(`{
			"event": "message",
			"session": "default",
			"payload": {
				"id": "false_120363025412345678@g.us_3EB01111",
				"from": "120363025412345678@g.us",
				"fromMe": false,
				"body": "pesan di grup"
			}
		}`)

		msg, isMsg, isFromMe, err := ParseInboundMessage(body, "req-3", now)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !isMsg || isFromMe {
			t.Fatalf("expected isMsg=true, isFromMe=false")
		}
		if msg == nil {
			t.Fatal("expected msg to not be nil")
		}
		if msg.Status != StatusQuarantined {
			t.Fatalf("expected status QUARANTINED, got %s", msg.Status)
		}
		if msg.PhoneE164 != nil {
			t.Fatalf("expected nil PhoneE164 for quarantined group, got %v", *msg.PhoneE164)
		}
		if msg.QuarantineReason != "group_message_not_supported" {
			t.Fatalf("unexpected quarantine reason: %s", msg.QuarantineReason)
		}
	})

	t.Run("invalid phone number is quarantined without customer", func(t *testing.T) {
		body := []byte(`{
			"event": "message",
			"session": "default",
			"payload": {
				"id": "false_15551234567@c.us_3EB02222",
				"from": "15551234567@c.us",
				"fromMe": false,
				"body": "international spam"
			}
		}`)

		msg, isMsg, _, err := ParseInboundMessage(body, "req-4", now)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !isMsg || msg == nil {
			t.Fatal("expected valid message parsed")
		}
		if msg.Status != StatusQuarantined {
			t.Fatalf("expected status QUARANTINED, got %s", msg.Status)
		}
		if msg.PhoneE164 != nil {
			t.Fatalf("expected nil PhoneE164, got %v", *msg.PhoneE164)
		}
		if msg.QuarantineReason != "unsupported_country_code_or_prefix" {
			t.Fatalf("unexpected quarantine reason: %s", msg.QuarantineReason)
		}
	})

	t.Run("non-message event", func(t *testing.T) {
		body := []byte(`{
			"event": "session.status",
			"session": "default",
			"payload": {"status": "WORKING"}
		}`)

		msg, isMsg, _, err := ParseInboundMessage(body, "req-5", now)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if isMsg || msg != nil {
			t.Fatalf("expected isMsg=false, got %v", isMsg)
		}
	})
}

func TestSanitizePayload(t *testing.T) {
	raw := json.RawMessage(`{
		"id": "msg-1",
		"token": "secret-token-value",
		"auth_secret": "my-password",
		"nested": {
			"api_key": "xyz123",
			"text": "normal value"
		}
	}`)

	redacted := SanitizePayload(raw)
	str := string(redacted)

	if strings.Contains(str, "secret-token-value") {
		t.Fatal("token was not redacted")
	}
	if strings.Contains(str, "my-password") {
		t.Fatal("auth_secret was not redacted")
	}
	if strings.Contains(str, "xyz123") {
		t.Fatal("api_key was not redacted")
	}
	if !strings.Contains(str, "normal value") {
		t.Fatal("normal text was lost in redaction")
	}
}
