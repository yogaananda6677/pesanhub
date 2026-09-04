package waha

import (
	"encoding/json"
	"strings"
	"time"
)

// Message status constants.
const (
	StatusReceived    = "RECEIVED"
	StatusProcessed   = "PROCESSED"
	StatusDuplicate   = "DUPLICATE"
	StatusQuarantined = "QUARANTINED"
	StatusFailed      = "FAILED"
)

// InboundMessage represents a received WhatsApp message from WAHA stored in the database.
type InboundMessage struct {
	ID                string     `json:"id"`
	ProviderMessageID string     `json:"provider_message_id"`
	WebhookRequestID  string     `json:"webhook_request_id,omitempty"`
	Session           string     `json:"session"`
	EventType         string     `json:"event_type"`
	FromRaw           string     `json:"from_raw"`
	PhoneE164         *string    `json:"phone_e164,omitempty"`
	SenderName        string     `json:"sender_name,omitempty"`
	MessageBody       string     `json:"message_body,omitempty"`
	PayloadRedacted   []byte     `json:"payload_redacted"`
	Status            string     `json:"status"`
	QuarantineReason  string     `json:"quarantine_reason,omitempty"`
	ReceivedAt        time.Time  `json:"received_at"`
	ProcessedAt       *time.Time `json:"processed_at,omitempty"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at"`
}

// WebhookEnvelope represents the outer JSON structure sent by WAHA.
type WebhookEnvelope struct {
	Event   string          `json:"event"`
	Session string          `json:"session"`
	Engine  string          `json:"engine,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

// WAHAMessageData represents inner message payload structure.
type WAHAMessageData struct {
	ID        string `json:"id"`
	Timestamp int64  `json:"timestamp,omitempty"`
	From      string `json:"from"`
	FromMe    bool   `json:"fromMe"`
	To        string `json:"to,omitempty"`
	Body      string `json:"body"`
	PushName  string `json:"pushName,omitempty"`
	Data      struct {
		NotifyName string `json:"notifyName,omitempty"`
	} `json:"_data"`
}

// IsMessageEvent returns true if the event represents an inbound message.
func IsMessageEvent(event string) bool {
	switch strings.ToLower(strings.TrimSpace(event)) {
	case "message", "message.any", "message.created":
		return true
	default:
		return false
	}
}

// ParseInboundMessage parses a raw WAHA webhook JSON body into an InboundMessage entity.
// It normalizes the sender phone number and applies the quarantine policy.
func ParseInboundMessage(body []byte, webhookRequestID string, now time.Time) (*InboundMessage, bool, bool, error) {
	var env WebhookEnvelope
	if err := json.Unmarshal(body, &env); err != nil {
		return nil, false, false, err
	}

	if !IsMessageEvent(env.Event) || len(env.Payload) == 0 {
		return nil, false, false, nil
	}

	var data WAHAMessageData
	if err := json.Unmarshal(env.Payload, &data); err != nil {
		return nil, true, false, err
	}

	// Provider message ID is required for message deduplication
	providerID := strings.TrimSpace(data.ID)
	if providerID == "" {
		return nil, true, false, nil
	}

	// Messages sent by bot itself (fromMe)
	if data.FromMe {
		return nil, true, true, nil
	}

	// Normalization & quarantine check
	phoneE164, isQuarantined, quarantineReason := NormalizeSenderPhone(data.From)

	senderName := strings.TrimSpace(data.PushName)
	if senderName == "" {
		senderName = strings.TrimSpace(data.Data.NotifyName)
	}
	if len(senderName) > 120 {
		senderName = senderName[:120]
	}

	status := StatusReceived
	var phonePtr *string
	if isQuarantined {
		status = StatusQuarantined
	} else if phoneE164 != "" {
		phonePtr = &phoneE164
	}

	redactedPayload := SanitizePayload(env.Payload)

	msg := &InboundMessage{
		ID:                newID(),
		ProviderMessageID: providerID,
		WebhookRequestID:  webhookRequestID,
		Session:           env.Session,
		EventType:         env.Event,
		FromRaw:           data.From,
		PhoneE164:         phonePtr,
		SenderName:        senderName,
		MessageBody:       data.Body,
		PayloadRedacted:   redactedPayload,
		Status:            status,
		QuarantineReason:  quarantineReason,
		ReceivedAt:        now,
		CreatedAt:         now,
		UpdatedAt:         now,
	}

	return msg, true, false, nil
}

// SanitizePayload recursively strips sensitive keys like token, secret, password, key.
func SanitizePayload(raw json.RawMessage) []byte {
	if len(raw) == 0 {
		return []byte("{}")
	}

	var obj any
	if err := json.Unmarshal(raw, &obj); err != nil {
		return []byte("{}")
	}

	sanitized := sanitizeNode(obj)
	b, err := json.Marshal(sanitized)
	if err != nil {
		return []byte("{}")
	}
	return b
}

func sanitizeNode(node any) any {
	switch v := node.(type) {
	case map[string]any:
		result := make(map[string]any, len(v))
		for k, val := range v {
			lowerK := strings.ToLower(k)
			if strings.Contains(lowerK, "secret") ||
				strings.Contains(lowerK, "token") ||
				strings.Contains(lowerK, "password") ||
				strings.Contains(lowerK, "auth") ||
				strings.Contains(lowerK, "api_key") ||
				strings.Contains(lowerK, "apikey") {
				result[k] = "[REDACTED]"
			} else {
				result[k] = sanitizeNode(val)
			}
		}
		return result
	case []any:
		result := make([]any, len(v))
		for i, val := range v {
			result[i] = sanitizeNode(val)
		}
		return result
	default:
		return v
	}
}
