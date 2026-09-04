package waha

import (
	"context"
	"encoding/json"
	"errors"
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
