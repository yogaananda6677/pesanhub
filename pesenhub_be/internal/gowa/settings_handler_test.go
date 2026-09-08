package gowa

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestSettingsHandler_GetSettings_GatewayDown(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	client := New(server.URL, "user", "pass", "dev1", time.Second)
	handler := NewSettingsHandler(client)

	req := httptest.NewRequest("GET", "/api/v1/settings/whatsapp", nil)
	rr := httptest.NewRecorder()
	handler.GetSettings(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}

	var resp struct {
		Data WhatsAppSettings `json:"data"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode json: %v", err)
	}

	if resp.Data.IsConnected {
		t.Errorf("expected is_connected to be false")
	}
	if resp.Data.Status != "GATEWAY_DOWN" {
		t.Errorf("expected status GATEWAY_DOWN, got %s", resp.Data.Status)
	}
}

func TestSettingsHandler_GetSettings_Connected(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/health":
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("OK"))
		case "/devices/dev1/status":
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"results":{"device_id":"dev1","is_connected":true,"is_logged_in":true}}`))
		case "/devices":
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"results":[{"id":"dev1","state":"logged_in","jid":"6281350624134@s.whatsapp.net"}]}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()

	client := New(server.URL, "user", "pass", "dev1", time.Second)
	handler := NewSettingsHandler(client)

	req := httptest.NewRequest("GET", "/api/v1/settings/whatsapp", nil)
	rr := httptest.NewRecorder()
	handler.GetSettings(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}

	var resp struct {
		Data WhatsAppSettings `json:"data"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode json: %v", err)
	}

	if !resp.Data.IsConnected {
		t.Errorf("expected is_connected to be true")
	}
	if resp.Data.Status != "CONNECTED" {
		t.Errorf("expected status CONNECTED, got %s", resp.Data.Status)
	}
	if !strings.Contains(resp.Data.PhoneMasked, "*") {
		t.Errorf("expected masked phone with asterisks, got %s", resp.Data.PhoneMasked)
	}
}

func TestSettingsHandler_PairDevice(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/devices":
			if r.Method == http.MethodGet {
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte(`{"results":[]}`))
			} else if r.Method == http.MethodPost {
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte(`{"code":"SUCCESS","results":{"id":"dev1","state":"disconnected"}}`))
			}
		case "/devices/dev1/login":
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"code":"SUCCESS","results":{"device_id":"dev1","qr_duration":30,"qr_link":"http://localhost:3000/statics/qrcode/test.png"}}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()

	client := New(server.URL, "user", "pass", "dev1", time.Second)
	handler := NewSettingsHandler(client)

	req := httptest.NewRequest("POST", "/api/v1/settings/whatsapp/pair", strings.NewReader(`{"device_id":"dev1"}`))
	rr := httptest.NewRecorder()
	handler.PairDevice(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}

	var resp struct {
		Data map[string]any `json:"data"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode json: %v", err)
	}

	if resp.Data["status"] != "WAITING_QR_SCAN" {
		t.Errorf("expected status WAITING_QR_SCAN, got %v", resp.Data["status"])
	}
	if resp.Data["qr_duration"] != float64(30) {
		t.Errorf("expected qr_duration 30, got %v", resp.Data["qr_duration"])
	}
}

func TestSettingsHandler_DisconnectDevice(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/devices/dev1" && r.Method == http.MethodDelete {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"code":"SUCCESS"}`))
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	client := New(server.URL, "user", "pass", "dev1", time.Second)
	handler := NewSettingsHandler(client)

	req := httptest.NewRequest("POST", "/api/v1/settings/whatsapp/disconnect", strings.NewReader(`{"device_id":"dev1"}`))
	rr := httptest.NewRecorder()
	handler.DisconnectDevice(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}

	var resp struct {
		Data map[string]any `json:"data"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode json: %v", err)
	}

	if resp.Data["status"] != "DISCONNECTED" {
		t.Errorf("expected status DISCONNECTED, got %v", resp.Data["status"])
	}
}

func TestSettingsHandler_ProxyQRImage(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/statics/qrcode/test.png" {
			w.Header().Set("Content-Type", "image/png")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("fake-png-bytes"))
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	client := New(server.URL, "user", "pass", "dev1", time.Second)
	handler := NewSettingsHandler(client)

	req := httptest.NewRequest("GET", "/api/v1/settings/whatsapp/qr-image?url=/statics/qrcode/test.png", nil)
	rr := httptest.NewRecorder()
	handler.ProxyQRImage(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}
	if rr.Header().Get("Content-Type") != "image/png" {
		t.Errorf("expected Content-Type image/png, got %s", rr.Header().Get("Content-Type"))
	}
	if rr.Body.String() != "fake-png-bytes" {
		t.Errorf("expected body fake-png-bytes, got %s", rr.Body.String())
	}
}
