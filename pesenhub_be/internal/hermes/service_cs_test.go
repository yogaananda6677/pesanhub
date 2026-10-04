package hermes

import (
	"context"
	"strings"
	"testing"

	"pesenhub/backend/internal/order"
)

type mockOrderReader struct {
	orderByID     map[string]order.OrderDetail
	latestByPhone map[string]order.OrderDetail
}

func (m *mockOrderReader) GetByID(ctx context.Context, orderID string) (order.OrderDetail, error) {
	if m.orderByID != nil {
		if ord, ok := m.orderByID[orderID]; ok {
			return ord, nil
		}
	}
	return order.OrderDetail{}, order.ErrNotFound
}

func (m *mockOrderReader) GetLatestByPhone(ctx context.Context, phone string) (order.OrderDetail, error) {
	if m.latestByPhone != nil {
		if ord, ok := m.latestByPhone[phone]; ok {
			return ord, nil
		}
	}
	return order.OrderDetail{}, order.ErrNotFound
}

func TestProcessTurn_OrderStatusInquiry_WithActiveOrder(t *testing.T) {
	phone := "+6281234567890"
	reader := &mockOrderReader{
		latestByPhone: map[string]order.OrderDetail{
			phone: {
				ID:                  "ord-1",
				OrderNumber:         "BWX-001",
				Status:              "PREPARING",
				PublicTrackingToken: "track-bwx-001",
				Items: []order.OrderItemDetail{
					{Name: "Martabak Daging Sapi", Quantity: 1},
				},
			},
		},
	}

	catProvider := &mockCatalogProvider{categories: sampleCatalog()}
	svc := NewService(Config{
		Client:          &MockLLMClient{},
		CatalogProvider: catProvider,
		OrderReader:     reader,
	})

	resp, err := svc.ProcessTurn(context.Background(), TurnRequest{
		SenderPhone:  phone,
		MessageText:  "udah jadi belum?",
		CustomerName: "Yoga",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !resp.HandledByAgent {
		t.Errorf("expected HandledByAgent = true")
	}
	if !strings.Contains(resp.ReplyText, "BWX-001") {
		t.Errorf("expected order number in reply, got: %s", resp.ReplyText)
	}
	if !strings.Contains(resp.ReplyText, "Sedang Dimasak / Disiapkan") {
		t.Errorf("expected preparing status in reply, got: %s", resp.ReplyText)
	}
	if !strings.Contains(resp.ReplyText, "kak Yoga") {
		t.Errorf("expected customer name in reply, got: %s", resp.ReplyText)
	}
	if !strings.Contains(resp.ReplyText, "track-bwx-001") {
		t.Errorf("expected tracking token in reply, got: %s", resp.ReplyText)
	}
}

func TestProcessTurn_OrderStatusInquiry_NoActiveOrder(t *testing.T) {
	phone := "+6281999999999"
	reader := &mockOrderReader{}
	catProvider := &mockCatalogProvider{categories: sampleCatalog()}

	svc := NewService(Config{
		Client:          &MockLLMClient{},
		CatalogProvider: catProvider,
		OrderReader:     reader,
	})

	resp, err := svc.ProcessTurn(context.Background(), TurnRequest{
		SenderPhone:  phone,
		MessageText:  "status pesanan saya gimana kak?",
		CustomerName: "Budi",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !resp.HandledByAgent {
		t.Errorf("expected HandledByAgent = true")
	}
	if !strings.Contains(resp.ReplyText, "belum ada pesanan aktif") {
		t.Errorf("expected no active order message, got: %s", resp.ReplyText)
	}
	if !strings.Contains(resp.ReplyText, "kak Budi") {
		t.Errorf("expected customer name in reply, got: %s", resp.ReplyText)
	}
}

func TestProcessTurn_CatalogInquiry(t *testing.T) {
	phone := "+6281234567890"
	catProvider := &mockCatalogProvider{categories: sampleCatalog()}

	svc := NewService(Config{
		Client:          &MockLLMClient{},
		CatalogProvider: catProvider,
	})

	resp, err := svc.ProcessTurn(context.Background(), TurnRequest{
		SenderPhone:  phone,
		MessageText:  "halo saya mau order minta katalognya dong kak",
		CustomerName: "Yoga",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !resp.HandledByAgent {
		t.Errorf("expected HandledByAgent = true")
	}
	// Verify it does NOT return the static empty items fallback greeting
	if strings.Contains(resp.ReplyText, "Saya Asisten Jenggirat AI") {
		t.Fatalf("reply still returned the generic fallback greeting instead of the live catalog!")
	}
	if !strings.Contains(resp.ReplyText, "daftar menu") {
		t.Errorf("expected catalog header in reply, got: %s", resp.ReplyText)
	}
	if !strings.Contains(resp.ReplyText, "Nasi Goreng Spesial") {
		t.Errorf("expected menu item from catalog in reply, got: %s", resp.ReplyText)
	}
}

func TestProcessTurn_RecommendationInquiry(t *testing.T) {
	phone := "+6281234567890"
	catProvider := &mockCatalogProvider{categories: sampleCatalog()}

	svc := NewService(Config{
		Client:          &MockLLMClient{},
		CatalogProvider: catProvider,
	})

	resp, err := svc.ProcessTurn(context.Background(), TurnRequest{
		SenderPhone:  phone,
		MessageText:  "rekomendasi menu paling enak apa ya kak?",
		CustomerName: "Siti",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !resp.HandledByAgent {
		t.Errorf("expected HandledByAgent = true")
	}
	if !strings.Contains(resp.ReplyText, "Terang Bulan Manis Coklat Keju") {
		t.Errorf("expected recommendation in reply, got: %s", resp.ReplyText)
	}
	if !strings.Contains(resp.ReplyText, "kak Siti") {
		t.Errorf("expected customer name in reply, got: %s", resp.ReplyText)
	}
}

func TestProcessTurn_StoreInfoInquiry(t *testing.T) {
	phone := "+6281234567890"
	catProvider := &mockCatalogProvider{categories: sampleCatalog()}

	svc := NewService(Config{
		Client:          &MockLLMClient{},
		CatalogProvider: catProvider,
	})

	resp, err := svc.ProcessTurn(context.Background(), TurnRequest{
		SenderPhone: phone,
		MessageText: "buka jam berapa kak?",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !resp.HandledByAgent {
		t.Errorf("expected HandledByAgent = true")
	}
	if !strings.Contains(resp.ReplyText, "16:00 - 23:00 WIB") {
		t.Errorf("expected store hours in reply, got: %s", resp.ReplyText)
	}
}

func TestProcessTurn_CatalogInquiry_WithMediaAttachments(t *testing.T) {
	phone := "+6281234567890"
	catProvider := &mockCatalogProvider{categories: sampleCatalog()}

	svc := NewService(Config{
		Client:          &MockLLMClient{},
		CatalogProvider: catProvider,
	})

	resp, err := svc.ProcessTurn(context.Background(), TurnRequest{
		SenderPhone:  phone,
		MessageText:  "minta katalognya dong kak",
		CustomerName: "Yoga",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(resp.MediaAttachments) != 2 {
		t.Fatalf("expected 2 media attachments, got %d", len(resp.MediaAttachments))
	}

	att1 := resp.MediaAttachments[0]
	if att1.Type != "image" || att1.Filename != "menu-martabak-telur.jpg" {
		t.Errorf("unexpected att1: %+v", att1)
	}
	if len(att1.Data) == 0 {
		t.Errorf("expected att1 data to not be empty")
	}

	att2 := resp.MediaAttachments[1]
	if att2.Type != "image" || att2.Filename != "menu-terang-bulan.png" {
		t.Errorf("unexpected att2: %+v", att2)
	}
	if len(att2.Data) == 0 {
		t.Errorf("expected att2 data to not be empty")
	}
}

func TestProcessTurn_ReceiptInquiry_WithPDF(t *testing.T) {
	phone := "+6281234567890"
	reader := &mockOrderReader{
		latestByPhone: map[string]order.OrderDetail{
			phone: {
				ID:                  "ord-1",
				OrderNumber:         "BWX-001",
				Status:              "PREPARING",
				PublicTrackingToken: "track-bwx-001",
				TotalAmount:         45000,
				Items: []order.OrderItemDetail{
					{Name: "Cut Pizza All In One", Quantity: 1, LineTotalAmount: 45000},
				},
			},
		},
	}

	svc := NewService(Config{
		Client:          &MockLLMClient{},
		CatalogProvider: &mockCatalogProvider{categories: sampleCatalog()},
		OrderReader:     reader,
	})

	resp, err := svc.ProcessTurn(context.Background(), TurnRequest{
		SenderPhone:  phone,
		MessageText:  "minta struknya dong kak",
		CustomerName: "Yoga",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !resp.HandledByAgent {
		t.Errorf("expected HandledByAgent = true")
	}
	if len(resp.MediaAttachments) != 1 {
		t.Fatalf("expected 1 receipt media attachment, got %d", len(resp.MediaAttachments))
	}

	receiptAtt := resp.MediaAttachments[0]
	if receiptAtt.Type != "document" {
		t.Errorf("expected attachment type 'document', got %s", receiptAtt.Type)
	}
	if receiptAtt.Filename != "struk-BWX-001.pdf" {
		t.Errorf("expected filename 'struk-BWX-001.pdf', got %s", receiptAtt.Filename)
	}
	if len(receiptAtt.Data) == 0 {
		t.Errorf("expected non-empty receipt PDF data")
	}
}

func TestProcessTurn_AIConversationalReplyWithInjectedContext(t *testing.T) {
	phone := "+6281234567890"
	reader := &mockOrderReader{
		latestByPhone: map[string]order.OrderDetail{
			phone: {
				ID:                  "ord-99",
				OrderNumber:         "BWX-099",
				Status:              "PREPARING",
				PublicTrackingToken: "track-bwx-099",
				Items: []order.OrderItemDetail{
					{Name: "Martabak Daging Sapi Spesial", Quantity: 1},
				},
			},
		},
	}

	mockClient := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items:      []RawExtractedItem{},
			Confidence: 0.5,
			ReplyText:  "Halo kak Yoga! Pesanan kakak #BWX-099 (1x Martabak Daging Sapi Spesial) sedang dimasak di dapur ya kak! Pantau terus di https://pesanhub.id/track/track-bwx-099 😊",
		},
	}

	svc := NewService(Config{
		Client:          mockClient,
		CatalogProvider: &mockCatalogProvider{categories: sampleCatalog()},
		OrderReader:     reader,
	})

	resp, err := svc.ProcessTurn(context.Background(), TurnRequest{
		SenderPhone:  phone,
		MessageText:  "posisi pesanan saya gimana kak?",
		CustomerName: "Yoga",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !resp.HandledByAgent {
		t.Errorf("expected HandledByAgent = true")
	}
	// Verify LLM prompt received dynamic injected context
	if !strings.Contains(mockClient.LastUserPrompt, "Known Customer Name: Yoga") {
		t.Errorf("expected customer name in injected context, got prompt: %s", mockClient.LastUserPrompt)
	}
	if !strings.Contains(mockClient.LastUserPrompt, "BWX-099") {
		t.Errorf("expected active order number in injected context, got prompt: %s", mockClient.LastUserPrompt)
	}
	if !strings.Contains(mockClient.LastUserPrompt, "Outlet Operational Context") {
		t.Errorf("expected outlet operational context in injected prompt, got: %s", mockClient.LastUserPrompt)
	}

	// Verify reply text matches the AI natural response
	if resp.ReplyText != mockClient.Response.ReplyText {
		t.Errorf("expected reply %q, got %q", mockClient.Response.ReplyText, resp.ReplyText)
	}
	// Must NOT contain store location
	if strings.Contains(resp.ReplyText, "Jl. Ahmad Yani") {
		t.Errorf("order status question must NOT return store address!")
	}
}

func TestProcessTurn_PosisiPesananDoesNotMatchOutletLocation(t *testing.T) {
	phone := "+6281234567890"
	reader := &mockOrderReader{
		latestByPhone: map[string]order.OrderDetail{
			phone: {
				ID:                  "ord-1",
				OrderNumber:         "BWX-001",
				Status:              "PREPARING",
				PublicTrackingToken: "track-bwx-001",
				Items: []order.OrderItemDetail{
					{Name: "Martabak Daging Sapi", Quantity: 1},
				},
			},
		},
	}

	// Mock LLM returns empty reply_text so fallback executes
	mockClient := &MockLLMClient{}

	svc := NewService(Config{
		Client:          mockClient,
		CatalogProvider: &mockCatalogProvider{categories: sampleCatalog()},
		OrderReader:     reader,
	})

	// Test case reported by user: "posisi pesanan saya gimana"
	resp, err := svc.ProcessTurn(context.Background(), TurnRequest{
		SenderPhone:  phone,
		MessageText:  "posisi pesanan saya gimana",
		CustomerName: "Yoga",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !resp.HandledByAgent {
		t.Errorf("expected HandledByAgent = true")
	}
	if !strings.Contains(resp.ReplyText, "BWX-001") {
		t.Errorf("expected order status in reply, got: %s", resp.ReplyText)
	}
	// Verify it does NOT mistake "posisi pesanan" as outlet location
	if strings.Contains(resp.ReplyText, "Jl. Ahmad Yani") || strings.Contains(resp.ReplyText, "Google Maps") {
		t.Fatalf("order status inquiry was wrongly routed to outlet location! Reply: %s", resp.ReplyText)
	}
}

func TestProcessTurn_OutletLocationInquiryReturnsLocation(t *testing.T) {
	phone := "+6281234567890"
	mockClient := &MockLLMClient{}

	svc := NewService(Config{
		Client:          mockClient,
		CatalogProvider: &mockCatalogProvider{categories: sampleCatalog()},
	})

	resp, err := svc.ProcessTurn(context.Background(), TurnRequest{
		SenderPhone:  phone,
		MessageText:  "posisi outlet di mana kak?",
		CustomerName: "Yoga",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !resp.HandledByAgent {
		t.Errorf("expected HandledByAgent = true")
	}
	if !strings.Contains(resp.ReplyText, "Jl. Ahmad Yani No. 45") {
		t.Errorf("expected outlet location in reply, got: %s", resp.ReplyText)
	}
	if !strings.Contains(resp.ReplyText, "Google Maps") {
		t.Errorf("expected maps link in reply, got: %s", resp.ReplyText)
	}
}
