package waha

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type APIState string
type SessionState string

const (
	APIUp   APIState = "up"
	APIDown APIState = "down"

	SessionReady        SessionState = "ready"
	SessionAbsent       SessionState = "absent"
	SessionDisconnected SessionState = "disconnected"
	SessionDegraded     SessionState = "degraded"
	SessionUnknown      SessionState = "unknown"
)

// Readiness contains only bounded, non-sensitive values safe for health output.
type Readiness struct {
	API     APIState
	Session SessionState
	Status  string
	Reason  string
}

type Checker interface {
	Readiness(context.Context) Readiness
}

var (
	ErrValidation      = errors.New("validation_failed")
	ErrAuthentication  = errors.New("authentication_failed")
	ErrSessionAbsent   = errors.New("session_not_found")
	ErrSessionNotReady = errors.New("session_not_ready")
	ErrProvider        = errors.New("provider_error")
	ErrTimeout         = errors.New("timeout")
)

type Sender interface {
	SendMessage(ctx context.Context, toPhone, text string) (string, error)
}

type Client struct {
	baseURL, apiKey, session string
	http                     *http.Client
}

func New(baseURL, apiKey, session string, timeout time.Duration) *Client {
	return &Client{strings.TrimRight(baseURL, "/"), apiKey, session, &http.Client{Timeout: timeout}}
}

func (c *Client) Readiness(ctx context.Context) Readiness {
	endpoint := c.baseURL + "/api/sessions/" + url.PathEscape(c.session)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return Readiness{API: APIDown, Session: SessionUnknown, Reason: "invalid_request"}
	}
	req.Header.Set("X-Api-Key", c.apiKey)
	resp, err := c.http.Do(req)
	if err != nil {
		reason := "unavailable"
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(ctx.Err(), context.DeadlineExceeded) {
			reason = "timeout"
		}
		return Readiness{API: APIDown, Session: SessionUnknown, Reason: reason}
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return Readiness{API: APIUp, Session: SessionAbsent, Reason: "session_not_found"}
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		reason := "api_error"
		if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
			reason = "authentication_failed"
		}
		return Readiness{API: APIDown, Session: SessionUnknown, Reason: reason}
	}

	var body struct {
		Status string `json:"status"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&body); err != nil || strings.TrimSpace(body.Status) == "" {
		return Readiness{API: APIUp, Session: SessionDegraded, Reason: "invalid_response"}
	}
	status := strings.ToUpper(body.Status)
	if status == "WORKING" {
		return Readiness{API: APIUp, Session: SessionReady, Status: status}
	}
	switch status {
	case "STOPPED", "STARTING", "SCAN_QR_CODE", "PASSKEY_REQUIRED", "PASSKEY_CONFIRMATION_REQUIRED", "FAILED":
		return Readiness{API: APIUp, Session: SessionDisconnected, Status: status, Reason: "session_not_ready"}
	default:
		return Readiness{API: APIUp, Session: SessionDegraded, Status: "UNKNOWN", Reason: "unknown_session_status"}
	}
}

// SendMessage sends a text message to a WhatsApp recipient using WAHA /api/sendText endpoint.
// toPhone must be a valid Indonesian phone number (normalized to E.164, e.g. +628123456789).
// The phone number is converted to WAHA chatId format (628123456789@c.us).
func (c *Client) SendMessage(ctx context.Context, toPhone, text string) (string, error) {
	phone, quarantined, reason := NormalizeSenderPhone(toPhone)
	if quarantined {
		return "", fmt.Errorf("%w: invalid phone %s: %s", ErrValidation, MaskPhone(toPhone), reason)
	}
	text = strings.TrimSpace(text)
	if text == "" {
		return "", fmt.Errorf("%w: empty message text", ErrValidation)
	}

	chatId := strings.TrimPrefix(phone, "+") + "@c.us"
	payload := map[string]string{
		"session": c.session,
		"chatId":  chatId,
		"text":    text,
	}
	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("%w: marshal error: %v", ErrValidation, err)
	}

	endpoint := c.baseURL + "/api/sendText"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(bodyBytes))
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrValidation, err)
	}
	req.Header.Set("Content-Type", "application/json")
	if c.apiKey != "" {
		req.Header.Set("X-Api-Key", c.apiKey)
	}

	resp, err := c.http.Do(req)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return "", ErrTimeout
		}
		return "", fmt.Errorf("%w: %v", ErrProvider, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusBadRequest || resp.StatusCode == http.StatusUnprocessableEntity {
		return "", fmt.Errorf("%w: status %d", ErrValidation, resp.StatusCode)
	}
	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		return "", ErrAuthentication
	}
	if resp.StatusCode == http.StatusNotFound {
		return "", ErrSessionAbsent
	}
	if resp.StatusCode >= 500 {
		return "", fmt.Errorf("%w: status %d", ErrProvider, resp.StatusCode)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("%w: unexpected status %d", ErrProvider, resp.StatusCode)
	}

	var res struct {
		ID        any    `json:"id"`
		MessageID string `json:"messageId"`
	}
	_ = json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&res)

	var providerMessageID string
	if s, ok := res.ID.(string); ok && s != "" {
		providerMessageID = s
	} else if m, ok := res.ID.(map[string]any); ok {
		if serialized, ok := m["_serialized"].(string); ok {
			providerMessageID = serialized
		} else if idStr, ok := m["id"].(string); ok {
			providerMessageID = idStr
		}
	}
	if providerMessageID == "" && res.MessageID != "" {
		providerMessageID = res.MessageID
	}

	return providerMessageID, nil
}
