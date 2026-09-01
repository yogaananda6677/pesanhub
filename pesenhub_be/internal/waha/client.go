package waha

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"
)

type Checker interface{ Check(context.Context) error }

type Client struct {
	baseURL, apiKey, session string
	http                     *http.Client
}

func New(baseURL, apiKey, session string, timeout time.Duration) *Client {
	return &Client{strings.TrimRight(baseURL, "/"), apiKey, session, &http.Client{Timeout: timeout}}
}

func (c *Client) Check(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/api/sessions/"+c.session, nil)
	if err != nil {
		return fmt.Errorf("build status request: %w", err)
	}
	req.Header.Set("X-Api-Key", c.apiKey)
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("WAHA unavailable: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("WAHA returned HTTP %d", resp.StatusCode)
	}
	return nil
}
