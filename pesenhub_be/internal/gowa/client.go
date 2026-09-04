package gowa

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
type DeviceState string

const (
	APIUp              APIState    = "up"
	APIDown            APIState    = "down"
	DeviceReady        DeviceState = "ready"
	DeviceAbsent       DeviceState = "absent"
	DeviceDisconnected DeviceState = "disconnected"
	DeviceDegraded     DeviceState = "degraded"
	DeviceUnknown      DeviceState = "unknown"
)

type Readiness struct {
	API            APIState
	Device         DeviceState
	Status, Reason string
}
type Checker interface {
	Readiness(context.Context) Readiness
}

var (
	ErrValidation     = errors.New("validation_failed")
	ErrAuthentication = errors.New("authentication_failed")
	ErrDeviceAbsent   = errors.New("device_not_found")
	ErrDeviceNotReady = errors.New("device_not_ready")
	ErrProvider       = errors.New("provider_error")
	ErrTimeout        = errors.New("timeout")
)

type Sender interface {
	SendMessage(context.Context, string, string) (string, error)
}

type Client struct {
	baseURL, username, password, deviceID string
	http                                  *http.Client
}

func New(baseURL, username, password, deviceID string, timeout time.Duration) *Client {
	return &Client{strings.TrimRight(baseURL, "/"), username, password, deviceID, &http.Client{Timeout: timeout}}
}

func (c *Client) request(ctx context.Context, method, endpoint string, body io.Reader) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, method, endpoint, body)
	if err != nil {
		return nil, err
	}
	if c.username != "" || c.password != "" {
		req.SetBasicAuth(c.username, c.password)
	}
	if c.deviceID != "" {
		req.Header.Set("X-Device-Id", c.deviceID)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	return c.http.Do(req)
}

func (c *Client) Readiness(ctx context.Context) Readiness {
	resp, err := c.request(ctx, http.MethodGet, c.baseURL+"/health", nil)
	if err != nil {
		return readinessTransportError(ctx, err)
	}
	resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return Readiness{API: APIDown, Device: DeviceUnknown, Reason: "api_error"}
	}
	resp, err = c.request(ctx, http.MethodGet, c.baseURL+"/devices/"+url.PathEscape(c.deviceID)+"/status", nil)
	if err != nil {
		return readinessTransportError(ctx, err)
	}
	defer resp.Body.Close()
	responseBody, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if resp.StatusCode == http.StatusNotFound || responseMentionsDeviceAbsent(responseBody) {
		return Readiness{API: APIUp, Device: DeviceAbsent, Reason: "device_not_found"}
	}
	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		return Readiness{API: APIDown, Device: DeviceUnknown, Reason: "authentication_failed"}
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return Readiness{API: APIUp, Device: DeviceDegraded, Reason: "device_status_error"}
	}
	var body struct {
		Results struct {
			Connected bool `json:"is_connected"`
			LoggedIn  bool `json:"is_logged_in"`
		} `json:"results"`
	}
	if json.Unmarshal(responseBody, &body) != nil {
		return Readiness{API: APIUp, Device: DeviceDegraded, Reason: "invalid_response"}
	}
	if body.Results.Connected && body.Results.LoggedIn {
		return Readiness{API: APIUp, Device: DeviceReady, Status: "CONNECTED"}
	}
	return Readiness{API: APIUp, Device: DeviceDisconnected, Status: "DISCONNECTED", Reason: "device_not_ready"}
}

func readinessTransportError(ctx context.Context, err error) Readiness {
	reason := "unavailable"
	if errors.Is(err, context.DeadlineExceeded) || errors.Is(ctx.Err(), context.DeadlineExceeded) {
		reason = "timeout"
	}
	return Readiness{API: APIDown, Device: DeviceUnknown, Reason: reason}
}

func (c *Client) SendMessage(ctx context.Context, toPhone, text string) (string, error) {
	phone, quarantined, reason := NormalizeSenderPhone(toPhone)
	if quarantined {
		return "", fmt.Errorf("%w: invalid phone %s: %s", ErrValidation, MaskPhone(toPhone), reason)
	}
	text = strings.TrimSpace(text)
	if text == "" {
		return "", fmt.Errorf("%w: empty message text", ErrValidation)
	}
	payload, _ := json.Marshal(map[string]string{"phone": strings.TrimPrefix(phone, "+") + "@s.whatsapp.net", "message": text})
	resp, err := c.request(ctx, http.MethodPost, c.baseURL+"/send/message", bytes.NewReader(payload))
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return "", ErrTimeout
		}
		return "", fmt.Errorf("%w: %v", ErrProvider, err)
	}
	defer resp.Body.Close()
	responseBody, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	switch {
	case resp.StatusCode == http.StatusBadRequest || resp.StatusCode == http.StatusUnprocessableEntity:
		return "", fmt.Errorf("%w: status %d", ErrValidation, resp.StatusCode)
	case resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden:
		return "", ErrAuthentication
	case resp.StatusCode == http.StatusNotFound || responseMentionsDeviceAbsent(responseBody):
		return "", ErrDeviceAbsent
	case responseMentionsDeviceNotReady(responseBody):
		return "", ErrDeviceNotReady
	case resp.StatusCode >= 500:
		return "", fmt.Errorf("%w: status %d", ErrProvider, resp.StatusCode)
	case resp.StatusCode < 200 || resp.StatusCode >= 300:
		return "", fmt.Errorf("%w: unexpected status %d", ErrProvider, resp.StatusCode)
	}
	var result struct {
		Results struct {
			MessageID string `json:"message_id"`
		} `json:"results"`
	}
	if json.Unmarshal(responseBody, &result) != nil || strings.TrimSpace(result.Results.MessageID) == "" {
		return "", fmt.Errorf("%w: missing message id", ErrProvider)
	}
	return result.Results.MessageID, nil
}

func responseMentionsDeviceAbsent(body []byte) bool {
	message := strings.ToLower(string(body))
	return strings.Contains(message, "device") && strings.Contains(message, "not found")
}

func responseMentionsDeviceNotReady(body []byte) bool {
	message := strings.ToLower(string(body))
	return strings.Contains(message, "not connected") || strings.Contains(message, "not logged in")
}
