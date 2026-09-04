package notification

import (
	"strings"
	"testing"
)

func TestFormatCurrency(t *testing.T) {
	tests := []struct {
		amount   int64
		expected string
	}{
		{0, "Rp 0"},
		{500, "Rp 500"},
		{1000, "Rp 1.000"},
		{25000, "Rp 25.000"},
		{1250000, "Rp 1.250.000"},
	}
	for _, tt := range tests {
		got := FormatCurrency(tt.amount)
		if got != tt.expected {
			t.Errorf("FormatCurrency(%d) = %s, expected %s", tt.amount, got, tt.expected)
		}
	}
}

func TestBuildTrackingURL(t *testing.T) {
	tests := []struct {
		baseURL  string
		token    string
		expected string
	}{
		{"", "trk_abc", "https://pesenhub.id/orders/track/trk_abc"},
		{"https://pesenhub.id/orders/track/", "trk_123", "https://pesenhub.id/orders/track/trk_123"},
		{"http://localhost:8080/track", "trk_456", "http://localhost:8080/track/trk_456"},
		{"https://pesenhub.id/orders/track", "", "https://pesenhub.id/orders/track"},
	}
	for _, tt := range tests {
		got := BuildTrackingURL(tt.baseURL, tt.token)
		if got != tt.expected {
			t.Errorf("BuildTrackingURL(%q, %q) = %s, expected %s", tt.baseURL, tt.token, got, tt.expected)
		}
	}
}

func TestRenderConfirmation(t *testing.T) {
	data := OrderNotificationData{
		OrderID:         "ord-1",
		OrderNumber:     "ORD-20260904-001",
		CustomerName:    "Budi Santoso",
		CustomerPhone:   "+6281234567890",
		TotalAmount:     44000,
		TrackingToken:   "trk_test_123",
		TrackingBaseURL: "https://pesenhub.id/orders/track",
		Items: []OrderItemSummary{
			{
				Name:      "Nasi Goreng Spesial",
				Quantity:  2,
				UnitPrice: 22000,
				LineTotal: 44000,
				Modifiers: []string{"Pedas Sedang", "Telur Dadar"},
				Notes:     "Jangan pakai acar",
			},
		},
	}

	rendered, err := RenderTemplate(TypeConfirmation, data)
	if err != nil {
		t.Fatalf("unexpected render error: %v", err)
	}

	if !strings.Contains(rendered, "Budi Santoso") {
		t.Error("rendered missing customer name")
	}
	if !strings.Contains(rendered, "ORD-20260904-001") {
		t.Error("rendered missing order number")
	}
	if !strings.Contains(rendered, "2x Nasi Goreng Spesial (Pedas Sedang, Telur Dadar) — Rp 44.000") {
		t.Errorf("rendered item breakdown unexpected: %s", rendered)
	}
	if !strings.Contains(rendered, "Catatan: Jangan pakai acar") {
		t.Error("rendered missing notes")
	}
	if !strings.Contains(rendered, "*Total Pembayaran:* Rp 44.000") {
		t.Error("rendered missing formatted total amount")
	}
	if !strings.Contains(rendered, "https://pesenhub.id/orders/track/trk_test_123") {
		t.Error("rendered missing tracking URL")
	}
}

func TestRenderAccepted(t *testing.T) {
	data := OrderNotificationData{
		OrderID:       "ord-1",
		OrderNumber:   "ORD-20260904-001",
		CustomerName:  "Budi Santoso",
		TrackingToken: "trk_test_123",
	}

	rendered, err := RenderTemplate(TypeAccepted, data)
	if err != nil {
		t.Fatalf("unexpected render error: %v", err)
	}

	if !strings.Contains(rendered, "ORD-20260904-001") {
		t.Error("rendered missing order number")
	}
	if !strings.Contains(rendered, "diterima oleh outlet dan sedang dipersiapkan di dapur") {
		t.Error("rendered missing accepted message")
	}
}

func TestRenderCompleted(t *testing.T) {
	data := OrderNotificationData{
		OrderID:      "ord-1",
		OrderNumber:  "ORD-20260904-001",
		CustomerName: "Budi Santoso",
	}

	rendered, err := RenderTemplate(TypeCompleted, data)
	if err != nil {
		t.Fatalf("unexpected render error: %v", err)
	}

	if !strings.Contains(rendered, "ORD-20260904-001") {
		t.Error("rendered missing order number")
	}
	if !strings.Contains(rendered, "SELESAI dan siap diambil di outlet") {
		t.Error("rendered missing completed message")
	}
}

func TestRenderUnsupportedType(t *testing.T) {
	_, err := RenderTemplate(NotificationType("UNKNOWN"), OrderNotificationData{})
	if err == nil {
		t.Fatal("expected error for unsupported notification type")
	}
}
