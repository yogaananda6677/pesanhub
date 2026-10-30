package hermes

import (
	"context"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/catalog"
)

func TestConversationStore_ContextMessages(t *testing.T) {
	ctx := context.Background()
	store := NewMemoryConversationStore()
	phone := "+6281234567890"
	cycle1 := "cycle-101"
	cycle2 := "cycle-102"

	// Record turn 1 messages for cycle 1
	err := store.RecordContextMessage(ctx, ConversationContextMessage{
		CustomerPhone: phone,
		CycleID:       cycle1,
		Role:          "customer",
		MessageText:   "yang terangbulan 2 toping berapa",
		CreatedAt:     time.Now().Add(-10 * time.Minute),
	})
	if err != nil {
		t.Fatalf("failed to record customer message: %v", err)
	}

	err = store.RecordContextMessage(ctx, ConversationContextMessage{
		CustomerPhone: phone,
		CycleID:       cycle1,
		Role:          "assistant",
		MessageText:   "Untuk Terang Bulan 2 Toping: Biasa Rp 20.000, Besar Rp 25.000 kak. Mau yang mana? ~AI Jenggirat",
		CreatedAt:     time.Now().Add(-9 * time.Minute),
	})
	if err != nil {
		t.Fatalf("failed to record assistant message: %v", err)
	}

	// Record turn 2 customer message for cycle 1
	err = store.RecordContextMessage(ctx, ConversationContextMessage{
		CustomerPhone: phone,
		CycleID:       cycle1,
		Role:          "customer",
		MessageText:   "yang biasa kak",
		CreatedAt:     time.Now().Add(-8 * time.Minute),
	})
	if err != nil {
		t.Fatalf("failed to record turn 2 customer message: %v", err)
	}

	// Record message for cycle 2 (different order cycle)
	err = store.RecordContextMessage(ctx, ConversationContextMessage{
		CustomerPhone: phone,
		CycleID:       cycle2,
		Role:          "customer",
		MessageText:   "halo pesanan baru",
		CreatedAt:     time.Now(),
	})
	if err != nil {
		t.Fatalf("failed to record cycle 2 message: %v", err)
	}

	// Verify querying cycle 1 only returns cycle 1 messages
	c1Messages, err := store.GetRecentContextMessages(ctx, phone, cycle1, 10)
	if err != nil {
		t.Fatalf("failed to get cycle 1 messages: %v", err)
	}
	if len(c1Messages) != 3 {
		t.Fatalf("expected 3 messages for cycle 1, got %d", len(c1Messages))
	}
	if c1Messages[0].MessageText != "yang terangbulan 2 toping berapa" {
		t.Errorf("expected first message to be turn 1 customer, got %q", c1Messages[0].MessageText)
	}
	if c1Messages[2].MessageText != "yang biasa kak" {
		t.Errorf("expected third message to be turn 2 customer, got %q", c1Messages[2].MessageText)
	}

	// Test limit
	limited, err := store.GetRecentContextMessages(ctx, phone, cycle1, 2)
	if err != nil {
		t.Fatalf("failed to get limited messages: %v", err)
	}
	if len(limited) != 2 {
		t.Fatalf("expected 2 messages with limit 2, got %d", len(limited))
	}
	if limited[0].Role != "assistant" || limited[1].Role != "customer" {
		t.Errorf("expected last 2 messages (assistant, customer), got (%s, %s)", limited[0].Role, limited[1].Role)
	}

	// Test clear cycle 1
	err = store.ClearCycleContext(ctx, phone, cycle1)
	if err != nil {
		t.Fatalf("failed to clear cycle 1: %v", err)
	}
	clearedMessages, err := store.GetRecentContextMessages(ctx, phone, cycle1, 10)
	if err != nil {
		t.Fatalf("failed to query cleared cycle: %v", err)
	}
	if len(clearedMessages) != 0 {
		t.Errorf("expected 0 messages after clear, got %d", len(clearedMessages))
	}

	// Cycle 2 should remain untouched
	c2Messages, err := store.GetRecentContextMessages(ctx, phone, cycle2, 10)
	if err != nil {
		t.Fatalf("failed to get cycle 2: %v", err)
	}
	if len(c2Messages) != 1 {
		t.Errorf("expected cycle 2 to have 1 message, got %d", len(c2Messages))
	}
}

func TestBuildExtractionPrompt_ContextAndPriceGrounding(t *testing.T) {
	pCtx := PromptContext{
		CustomerName:        "Yoga",
		CatalogPrices:       "• Terang Bulan: Terang Bulan 2 Toping - Biasa (Rp 20000) | Terang Bulan 2 Toping - Besar (Rp 25000)\n• Martabak Telur: Martabak Telur Spesial Biasa (Rp 25000)",
		ConversationHistory: "Pelanggan: yang terangbulan 2 toping berapa\nAsisten: Untuk Terang Bulan 2 Toping: Biasa Rp 20.000, Besar Rp 25.000 kak. Mau ukuran biasa atau besar? ~AI Jenggirat",
	}

	sys, user := BuildExtractionPromptWithFullContext("yang biasa kak", pCtx)

	// Verify System Prompt contains grounding & referential rules
	if !strings.Contains(sys, "PRICE INQUIRIES & PRICING") {
		t.Errorf("expected Rule 2 'PRICE INQUIRIES & PRICING' in system prompt")
	}
	if !strings.Contains(sys, "CONVERSATION CONTEXT & REFERENTIAL RESOLUTION") {
		t.Errorf("expected Rule 12 'CONVERSATION CONTEXT & REFERENTIAL RESOLUTION' in system prompt")
	}

	// Verify User Prompt contains catalog prices and conversation history
	if !strings.Contains(user, "Official Catalog Menu & Prices:") {
		t.Errorf("expected 'Official Catalog Menu & Prices:' in user prompt")
	}
	if !strings.Contains(user, "Terang Bulan 2 Toping - Biasa (Rp 20000)") {
		t.Errorf("expected catalog price details in user prompt")
	}
	if !strings.Contains(user, "Recent Conversation Context (Current Order Cycle):") {
		t.Errorf("expected 'Recent Conversation Context (Current Order Cycle):' in user prompt")
	}
	if !strings.Contains(user, "Pelanggan: yang terangbulan 2 toping berapa") {
		t.Errorf("expected previous turn customer question in user prompt")
	}
	if !strings.Contains(user, "Asisten: Untuk Terang Bulan 2 Toping") {
		t.Errorf("expected previous turn assistant reply in user prompt")
	}
	if !strings.Contains(user, "Known Customer Name: Yoga") {
		t.Errorf("expected customer name in user prompt")
	}
}

func TestProcessTurn_MultiTurnContextRetention(t *testing.T) {
	ctx := context.Background()
	phone := "+6281333444555"

	memStore := NewMemoryConversationStore()
	mockClient := &MockLLMClient{
		Response: &RawExtractedOrder{
			Confidence: 0.95,
			ReplyText:  "Untuk Terang Bulan 2 Toping harganya Rp 20.000 untuk Biasa dan Rp 25.000 untuk Besar kak. Mau yang mana?",
		},
	}

	catProvider := &mockCatalogProvider{
		categories: []catalog.Category{
			{
				Name:   "Terang Bulan",
				Active: true,
				Menus: []catalog.Menu{
					{Name: "Terang Bulan 2 Toping - Biasa", PriceAmount: 20000, Available: true},
					{Name: "Terang Bulan 2 Toping - Besar", PriceAmount: 25000, Available: true},
				},
			},
		},
	}

	svc := NewService(Config{
		Client:            mockClient,
		ConversationStore: memStore,
		CatalogProvider:   catProvider,
	})

	// Turn 1: Customer asks price
	resp1, err := svc.ProcessTurn(ctx, TurnRequest{
		SenderPhone: phone,
		MessageText: "yang terangbulan 2 toping berapa",
	})
	if err != nil {
		t.Fatalf("Turn 1 failed: %v", err)
	}
	if !strings.HasSuffix(resp1.ReplyText, "~AI Jenggirat") {
		t.Errorf("Turn 1 expected signature ~AI Jenggirat, got: %s", resp1.ReplyText)
	}
	cycleID := resp1.State.CycleID
	if cycleID == "" {
		t.Fatalf("Turn 1 expected active CycleID, got empty")
	}

	// Verify Turn 1 messages are stored in context
	msgs, err := memStore.GetRecentContextMessages(ctx, phone, cycleID, 10)
	if err != nil || len(msgs) != 2 {
		t.Fatalf("expected 2 context messages recorded for Turn 1, got %d (err: %v)", len(msgs), err)
	}
	if msgs[0].Role != "customer" || msgs[0].MessageText != "yang terangbulan 2 toping berapa" {
		t.Errorf("unexpected first message: %+v", msgs[0])
	}
	if msgs[1].Role != "assistant" || !strings.Contains(msgs[1].MessageText, "Terang Bulan 2 Toping") {
		t.Errorf("unexpected second message: %+v", msgs[1])
	}

	// Turn 2: Customer gives referential answer "yang biasa kak"
	mockClient.Response = &RawExtractedOrder{
		Confidence: 0.95,
		ReplyText:  "Siap kak, Terang Bulan 2 Toping ukuran Biasa sudah dicatat. Mau toping apa saja?",
	}

	resp2, err := svc.ProcessTurn(ctx, TurnRequest{
		SenderPhone: phone,
		MessageText: "yang biasa kak",
	})
	if err != nil {
		t.Fatalf("Turn 2 failed: %v", err)
	}
	if resp2.State.CycleID != cycleID {
		t.Errorf("expected same CycleID %s for Turn 2, got %s", cycleID, resp2.State.CycleID)
	}

	// Verify Turn 2 prompt sent to LLM had the Turn 1 conversation context!
	if !strings.Contains(mockClient.LastUserPrompt, "Recent Conversation Context (Current Order Cycle):") {
		t.Errorf("expected LLM user prompt to contain conversation context, got:\n%s", mockClient.LastUserPrompt)
	}
	if !strings.Contains(mockClient.LastUserPrompt, "yang terangbulan 2 toping berapa") {
		t.Errorf("expected prompt to contain Turn 1 customer question, got:\n%s", mockClient.LastUserPrompt)
	}
	if !strings.Contains(mockClient.LastUserPrompt, "Official Catalog Menu & Prices:") {
		t.Errorf("expected prompt to contain catalog prices, got:\n%s", mockClient.LastUserPrompt)
	}

	// Verify context store now has 4 messages for this cycle
	msgsAfterTurn2, err := memStore.GetRecentContextMessages(ctx, phone, cycleID, 10)
	if err != nil || len(msgsAfterTurn2) != 4 {
		t.Fatalf("expected 4 context messages recorded after Turn 2, got %d", len(msgsAfterTurn2))
	}
}

func TestProcessTurn_OrderCancelClearsCycleContext(t *testing.T) {
	ctx := context.Background()
	phone := "+6281777888999"

	memStore := NewMemoryConversationStore()
	mockClient := &MockLLMClient{
		Response: &RawExtractedOrder{
			Confidence: 0.95,
			Items: []RawExtractedItem{
				{MenuName: "Nasi Goreng Spesial", Quantity: 1, Modifiers: []string{"Pedas"}, Confidence: 0.95},
			},
		},
	}

	svc := NewService(Config{
		Client:            mockClient,
		ConversationStore: memStore,
		CatalogProvider:   &mockCatalogProvider{categories: sampleCatalog()},
	})

	// Turn 1: Customer creates draft order
	resp1, err := svc.ProcessTurn(ctx, TurnRequest{
		SenderPhone: phone,
		MessageText: "mau pesan nasi goreng spesial 1",
	})
	if err != nil {
		t.Fatalf("Turn 1 failed: %v", err)
	}
	cycle1 := resp1.State.CycleID
	if cycle1 == "" {
		t.Fatalf("expected CycleID on turn 1")
	}

	// Turn 2: Customer cancels order draft
	resp2, err := svc.ProcessTurn(ctx, TurnRequest{
		SenderPhone: phone,
		MessageText: "batalin aja kak",
	})
	if err != nil {
		t.Fatalf("Turn 2 failed: %v", err)
	}
	if !strings.Contains(resp2.ReplyText, "dibatalkan") {
		t.Errorf("expected cancellation message, got: %s", resp2.ReplyText)
	}

	// Verify cycle 1 context was cleared
	msgs, err := memStore.GetRecentContextMessages(ctx, phone, cycle1, 10)
	if err != nil || len(msgs) != 0 {
		t.Errorf("expected 0 messages in cycle 1 after cancel, got %d", len(msgs))
	}

	// Next turn should generate a fresh CycleID
	mockClient.Response = &RawExtractedOrder{
		Confidence: 0.95,
		ReplyText:  "Halo, selamat datang kembali!",
	}
	resp3, err := svc.ProcessTurn(ctx, TurnRequest{
		SenderPhone: phone,
		MessageText: "halo",
	})
	if err != nil {
		t.Fatalf("Turn 3 failed: %v", err)
	}
	if resp3.State.CycleID == cycle1 || resp3.State.CycleID == "" {
		t.Errorf("expected new fresh CycleID different from %s, got %s", cycle1, resp3.State.CycleID)
	}
}
