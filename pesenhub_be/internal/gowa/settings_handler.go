package gowa

import (
	"encoding/json"
	"net/http"
	"net/url"
	"strings"

	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

// WhatsAppSettings represents the public settings payload for WhatsApp integration.
type WhatsAppSettings struct {
	IsConnected   bool   `json:"is_connected"`
	Status        string `json:"status"`        // CONNECTED, DISCONNECTED, GATEWAY_DOWN
	GatewayState  string `json:"gateway_state"` // UP, DOWN
	DeviceID      string `json:"device_id"`
	PhoneMasked   string `json:"phone_masked"`
	JID           string `json:"jid,omitempty"`
	PrivacyNotice string `json:"privacy_notice"`
}

// SettingsHandler handles settings and device pairing requests for WhatsApp GOWA.
type SettingsHandler struct {
	client *Client
}

// NewSettingsHandler constructs a new SettingsHandler.
func NewSettingsHandler(client *Client) *SettingsHandler {
	return &SettingsHandler{client: client}
}

// GetSettings returns current WhatsApp gateway readiness and active device connection.
func (h *SettingsHandler) GetSettings(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	readiness := h.client.Readiness(ctx)

	const defaultPrivacyNotice = "Nomor telepon dan data transaksi pelanggan disanitasi dengan enkripsi dan PII masking otomatis sebelum disimpan."

	if readiness.API != APIUp {
		httpapi.WriteJSON(w, http.StatusOK, map[string]any{
			"data": WhatsAppSettings{
				IsConnected:   false,
				Status:        "GATEWAY_DOWN",
				GatewayState:  string(readiness.API),
				DeviceID:      h.client.DeviceID(),
				PhoneMasked:   "-",
				PrivacyNotice: defaultPrivacyNotice,
			},
		})
		return
	}

	activeDevice, err := h.client.ResolveActiveDevice(ctx)
	if err != nil || activeDevice == nil {
		httpapi.WriteJSON(w, http.StatusOK, map[string]any{
			"data": WhatsAppSettings{
				IsConnected:   false,
				Status:        "DISCONNECTED",
				GatewayState:  string(readiness.API),
				DeviceID:      h.client.DeviceID(),
				PhoneMasked:   "-",
				PrivacyNotice: defaultPrivacyNotice,
			},
		})
		return
	}

	isConnected := activeDevice.State == "logged_in" || activeDevice.State == "connected"
	status := "DISCONNECTED"
	if isConnected {
		status = "CONNECTED"
	}

	phoneMasked := "-"
	if activeDevice.JID != "" {
		phone := strings.Split(activeDevice.JID, "@")[0]
		phone = strings.Split(phone, ":")[0]
		if phone != "" {
			phoneMasked = MaskPhone("+" + phone)
		}
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"data": WhatsAppSettings{
			IsConnected:   isConnected,
			Status:        status,
			GatewayState:  string(readiness.API),
			DeviceID:      activeDevice.ID,
			PhoneMasked:   phoneMasked,
			JID:           activeDevice.JID,
			PrivacyNotice: defaultPrivacyNotice,
		},
	})
}

// PairDevice initiates pairing by ensuring device registration and fetching login QR code.
func (h *SettingsHandler) PairDevice(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	var body struct {
		DeviceID string `json:"device_id"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)

	deviceID := strings.TrimSpace(body.DeviceID)
	if deviceID == "" {
		deviceID = h.client.DeviceID()
	}
	if deviceID == "" {
		deviceID = "pesenhub-dev"
	}

	reqID := httpserver.RequestID(ctx)

	// 1. Ensure device exists in GOWA
	if err := h.client.EnsureDevice(ctx, deviceID); err != nil {
		httpapi.WriteError(w, http.StatusBadGateway, "FAILED_ENSURE_DEVICE", "Failed to register WhatsApp device with gateway: "+err.Error(), reqID, nil)
		return
	}

	// 2. Fetch login QR code
	loginRes, err := h.client.GetDeviceLoginQR(ctx, deviceID)
	if err != nil {
		httpapi.WriteError(w, http.StatusBadGateway, "FAILED_GET_QR", "Failed to retrieve login QR code: "+err.Error(), reqID, nil)
		return
	}

	if loginRes.QRDuration == 0 && loginRes.QRLink == "" {
		// Already logged in
		h.client.SetDeviceID(deviceID)
		httpapi.WriteJSON(w, http.StatusOK, map[string]any{
			"data": map[string]any{
				"is_already_logged_in": true,
				"status":               "CONNECTED",
				"device_id":            deviceID,
			},
		})
		return
	}

	proxyURL := "/api/v1/settings/whatsapp/qr-image?url=" + url.QueryEscape(loginRes.QRLink)

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"data": map[string]any{
			"is_already_logged_in": false,
			"status":               "WAITING_QR_SCAN",
			"device_id":            deviceID,
			"qr_duration":          loginRes.QRDuration,
			"qr_link":              loginRes.QRLink,
			"qr_proxy_url":         proxyURL,
		},
	})
}

// DisconnectDevice logs out and deletes the device from GOWA.
func (h *SettingsHandler) DisconnectDevice(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	var body struct {
		DeviceID string `json:"device_id"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)

	deviceID := strings.TrimSpace(body.DeviceID)
	if deviceID == "" {
		active, _ := h.client.ResolveActiveDevice(ctx)
		if active != nil {
			deviceID = active.ID
		} else {
			deviceID = h.client.DeviceID()
		}
	}

	if deviceID != "" {
		_ = h.client.DeleteDevice(ctx, deviceID)
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"data": map[string]any{
			"status":    "DISCONNECTED",
			"device_id": deviceID,
			"message":   "WhatsApp device successfully disconnected.",
		},
	})
}

// ProxyQRImage fetches the QR image from GOWA securely and streams it back to the client.
func (h *SettingsHandler) ProxyQRImage(w http.ResponseWriter, r *http.Request) {
	targetURL := strings.TrimSpace(r.URL.Query().Get("url"))
	if targetURL == "" {
		http.Error(w, "missing url parameter", http.StatusBadRequest)
		return
	}

	// Security validation: URL must belong to the configured GOWA base URL or /statics path
	parsedBase, err := url.Parse(h.client.BaseURL())
	if err != nil {
		http.Error(w, "invalid base url configuration", http.StatusInternalServerError)
		return
	}
	parsedTarget, err := url.Parse(targetURL)
	if err != nil {
		http.Error(w, "invalid target url", http.StatusBadRequest)
		return
	}

	// If host is specified, ensure it matches GOWA host or localhost
	if parsedTarget.Host != "" && parsedTarget.Host != parsedBase.Host && parsedTarget.Host != "localhost:3000" && parsedTarget.Host != "127.0.0.1:3000" && parsedTarget.Host != "gowa:3000" {
		http.Error(w, "forbidden target url host", http.StatusForbidden)
		return
	}

	// Ensure the path is requesting qrcode static image
	if !strings.HasPrefix(parsedTarget.Path, "/statics/qrcode/") && !strings.Contains(parsedTarget.Path, "qrcode") {
		http.Error(w, "forbidden image path", http.StatusForbidden)
		return
	}

	// Build full target URL using configured GOWA base
	fullURL := h.client.BaseURL() + parsedTarget.Path
	if parsedTarget.RawQuery != "" {
		fullURL += "?" + parsedTarget.RawQuery
	}

	data, contentType, err := h.client.FetchImage(r.Context(), fullURL)
	if err != nil {
		http.Error(w, "failed to load qr image: "+err.Error(), http.StatusBadGateway)
		return
	}

	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}
