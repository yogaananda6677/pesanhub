package gowa

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"net/url"
	"strings"
	"sync"
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

type MediaSender interface {
	Sender
	SendImage(ctx context.Context, toPhone, caption string, imageData []byte, filename string) (string, error)
	SendFile(ctx context.Context, toPhone, caption string, fileData []byte, filename string) (string, error)
}

type DeviceInfo struct {
	ID          string `json:"id"`
	DisplayName string `json:"display_name"`
	State       string `json:"state"`
	JID         string `json:"jid"`
	CreatedAt   string `json:"created_at"`
}

type QRLoginResult struct {
	DeviceID   string `json:"device_id"`
	QRDuration int    `json:"qr_duration"`
	QRLink     string `json:"qr_link"`
}

type CodeLoginResult struct {
	DeviceID string `json:"device_id"`
	PairCode string `json:"pair_code"`
}

type DeviceStatusResult struct {
	DeviceID    string `json:"device_id"`
	IsConnected bool   `json:"is_connected"`
	IsLoggedIn  bool   `json:"is_logged_in"`
}

type Client struct {
	baseURL, username, password string
	deviceIDMu                  sync.RWMutex
	deviceID                    string
	http                        *http.Client
}

func New(baseURL, username, password, deviceID string, timeout time.Duration) *Client {
	return &Client{
		baseURL:  strings.TrimRight(baseURL, "/"),
		username: username,
		password: password,
		deviceID: deviceID,
		http:     &http.Client{Timeout: timeout},
	}
}

func (c *Client) DeviceID() string {
	c.deviceIDMu.RLock()
	defer c.deviceIDMu.RUnlock()
	return c.deviceID
}

func (c *Client) SetDeviceID(id string) {
	c.deviceIDMu.Lock()
	defer c.deviceIDMu.Unlock()
	c.deviceID = id
}

func (c *Client) BaseURL() string {
	return c.baseURL
}

func (c *Client) request(ctx context.Context, method, endpoint string, body io.Reader) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, method, endpoint, body)
	if err != nil {
		return nil, err
	}
	if c.username != "" || c.password != "" {
		req.SetBasicAuth(c.username, c.password)
	}
	if devID := c.DeviceID(); devID != "" {
		req.Header.Set("X-Device-Id", devID)
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
	devID := c.DeviceID()
	resp, err = c.request(ctx, http.MethodGet, c.baseURL+"/devices/"+url.PathEscape(devID)+"/status", nil)
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
		return "", fmt.Errorf("%w: status %d (body: %s)", ErrValidation, resp.StatusCode, strings.TrimSpace(string(responseBody)))
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

// SendChatPresence sends a typing indicator ("start") or stops it ("stop") for a given WhatsApp recipient.
func (c *Client) SendChatPresence(ctx context.Context, toPhone, action string) error {
	phone, quarantined, reason := NormalizeSenderPhone(toPhone)
	if quarantined {
		return fmt.Errorf("%w: invalid phone %s: %s", ErrValidation, MaskPhone(toPhone), reason)
	}
	action = strings.ToLower(strings.TrimSpace(action))
	if action != "start" && action != "stop" {
		return fmt.Errorf("%w: invalid action %s, must be start or stop", ErrValidation, action)
	}
	cleanPhone := strings.TrimPrefix(phone, "+")
	payload, _ := json.Marshal(map[string]string{
		"phone":  cleanPhone,
		"action": action,
	})
	resp, err := c.request(ctx, http.MethodPost, c.baseURL+"/send/chat-presence", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return nil
}

// SendImage sends an image file with an optional caption to a WhatsApp number.
func (c *Client) SendImage(ctx context.Context, toPhone, caption string, imageData []byte, filename string) (string, error) {
	if len(imageData) == 0 {
		return "", fmt.Errorf("%w: empty image data", ErrValidation)
	}
	if filename == "" {
		filename = "image.jpg"
	}
	return c.sendMedia(ctx, "/send/image", toPhone, caption, imageData, filename, "image")
}

// SendFile sends a document or file with an optional caption to a WhatsApp number.
func (c *Client) SendFile(ctx context.Context, toPhone, caption string, fileData []byte, filename string) (string, error) {
	if len(fileData) == 0 {
		return "", fmt.Errorf("%w: empty file data", ErrValidation)
	}
	if filename == "" {
		filename = "document.pdf"
	}
	return c.sendMedia(ctx, "/send/file", toPhone, caption, fileData, filename, "file")
}

func (c *Client) sendMedia(ctx context.Context, endpoint, toPhone, caption string, fileData []byte, filename, formFieldName string) (string, error) {
	phone, quarantined, reason := NormalizeSenderPhone(toPhone)
	if quarantined {
		return "", fmt.Errorf("%w: invalid phone %s: %s", ErrValidation, MaskPhone(toPhone), reason)
	}

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	targetJID := strings.TrimPrefix(phone, "+") + "@s.whatsapp.net"
	if err := writer.WriteField("phone", targetJID); err != nil {
		return "", fmt.Errorf("failed to write phone field: %w", err)
	}

	if caption != "" {
		if err := writer.WriteField("caption", caption); err != nil {
			return "", fmt.Errorf("failed to write caption field: %w", err)
		}
	}

	h := make(textproto.MIMEHeader)
	h.Set("Content-Disposition", fmt.Sprintf(`form-data; name="%s"; filename="%s"`, formFieldName, filename))
	contentType := "application/octet-stream"
	lowerName := strings.ToLower(filename)
	if strings.HasSuffix(lowerName, ".jpg") || strings.HasSuffix(lowerName, ".jpeg") {
		contentType = "image/jpeg"
	} else if strings.HasSuffix(lowerName, ".png") {
		contentType = "image/png"
	} else if strings.HasSuffix(lowerName, ".pdf") {
		contentType = "application/pdf"
	}
	h.Set("Content-Type", contentType)

	part, err := writer.CreatePart(h)
	if err != nil {
		return "", fmt.Errorf("failed to create form file: %w", err)
	}
	if _, err := part.Write(fileData); err != nil {
		return "", fmt.Errorf("failed to write file data: %w", err)
	}

	if err := writer.Close(); err != nil {
		return "", fmt.Errorf("failed to close multipart writer: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+endpoint, body)
	if err != nil {
		return "", err
	}
	if c.username != "" || c.password != "" {
		req.SetBasicAuth(c.username, c.password)
	}
	if devID := c.DeviceID(); devID != "" {
		req.Header.Set("X-Device-Id", devID)
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := c.http.Do(req)
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
		return "sent", nil
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

func (c *Client) ListDevices(ctx context.Context) ([]DeviceInfo, error) {
	resp, err := c.request(ctx, http.MethodGet, c.baseURL+"/devices", nil)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%w: status %d", ErrProvider, resp.StatusCode)
	}
	var res struct {
		Results []DeviceInfo `json:"results"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&res); err != nil {
		return nil, err
	}
	return res.Results, nil
}

func (c *Client) GetDeviceStatus(ctx context.Context, deviceID string) (*DeviceStatusResult, error) {
	resp, err := c.request(ctx, http.MethodGet, c.baseURL+"/devices/"+url.PathEscape(deviceID)+"/status", nil)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%w: status %d", ErrProvider, resp.StatusCode)
	}
	var res struct {
		Results DeviceStatusResult `json:"results"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&res); err != nil {
		return nil, err
	}
	return &res.Results, nil
}

func (c *Client) GetDeviceLoginQR(ctx context.Context, deviceID string) (*QRLoginResult, error) {
	resp, err := c.request(ctx, http.MethodGet, c.baseURL+"/devices/"+url.PathEscape(deviceID)+"/login", nil)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	bodyBytes, err := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if err != nil {
		return nil, err
	}
	var envelope struct {
		Code    string        `json:"code"`
		Message string        `json:"message"`
		Results QRLoginResult `json:"results"`
	}
	_ = json.Unmarshal(bodyBytes, &envelope)
	if envelope.Code == "ALREADY_LOGGED_IN" || strings.Contains(strings.ToLower(envelope.Message), "already logged in") {
		return &QRLoginResult{DeviceID: deviceID, QRDuration: 0, QRLink: ""}, nil
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%w: status %d (%s)", ErrProvider, resp.StatusCode, envelope.Message)
	}
	return &envelope.Results, nil
}

func (c *Client) GetDeviceLoginCode(ctx context.Context, deviceID, phone string) (*CodeLoginResult, error) {
	loginURL := fmt.Sprintf("%s/devices/%s/login/code?phone=%s", c.baseURL, url.PathEscape(deviceID), url.QueryEscape(phone))
	resp, err := c.request(ctx, http.MethodPost, loginURL, nil)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	bodyBytes, err := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if err != nil {
		return nil, err
	}
	var envelope struct {
		Code    string          `json:"code"`
		Message string          `json:"message"`
		Results CodeLoginResult `json:"results"`
	}
	_ = json.Unmarshal(bodyBytes, &envelope)
	if envelope.Code == "ALREADY_LOGGED_IN" || strings.Contains(strings.ToLower(envelope.Message), "already logged in") {
		return &CodeLoginResult{DeviceID: deviceID, PairCode: ""}, nil
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%w: status %d (%s)", ErrProvider, resp.StatusCode, envelope.Message)
	}
	return &envelope.Results, nil
}

func (c *Client) EnsureDevice(ctx context.Context, deviceID string) error {
	devices, err := c.ListDevices(ctx)
	if err == nil {
		for _, d := range devices {
			if d.ID == deviceID {
				return nil
			}
		}
	}
	payload, _ := json.Marshal(map[string]string{"device_id": deviceID})
	resp, err := c.request(ctx, http.MethodPost, c.baseURL+"/devices", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	if resp.StatusCode == http.StatusBadRequest {
		return nil
	}
	return fmt.Errorf("%w: failed to add device status %d", ErrProvider, resp.StatusCode)
}

func (c *Client) DeleteDevice(ctx context.Context, deviceID string) error {
	resp, err := c.request(ctx, http.MethodDelete, c.baseURL+"/devices/"+url.PathEscape(deviceID), nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("%w: failed to delete device status %d", ErrProvider, resp.StatusCode)
	}
	return nil
}

func (c *Client) FetchImage(ctx context.Context, imageURL string) ([]byte, string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, imageURL, nil)
	if err != nil {
		return nil, "", err
	}
	if c.username != "" || c.password != "" {
		req.SetBasicAuth(c.username, c.password)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, "", fmt.Errorf("unexpected status %d", resp.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return nil, "", err
	}
	contentType := resp.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "image/png"
	}
	return data, contentType, nil
}

func (c *Client) ResolveActiveDevice(ctx context.Context) (*DeviceInfo, error) {
	devices, err := c.ListDevices(ctx)
	if err != nil {
		return nil, err
	}
	devID := c.DeviceID()
	// 1. If current devID is logged in, return it
	for _, d := range devices {
		if devID != "" && d.ID == devID && (d.State == "logged_in" || d.State == "connected") {
			return &d, nil
		}
	}
	// 2. If any other device is logged in, use it and update devID
	for _, d := range devices {
		if d.State == "logged_in" || d.State == "connected" {
			c.SetDeviceID(d.ID)
			return &d, nil
		}
	}
	// 3. If current devID is present, return it even if disconnected
	for _, d := range devices {
		if devID != "" && d.ID == devID {
			return &d, nil
		}
	}
	// 4. If any device exists, return first
	if len(devices) > 0 {
		return &devices[0], nil
	}
	return nil, ErrDeviceAbsent
}
