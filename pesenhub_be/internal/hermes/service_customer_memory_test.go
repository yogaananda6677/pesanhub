package hermes

import (
	"context"
	"strings"
	"testing"

	"pesenhub/backend/internal/customer"
)

type mockCustomerMemory struct {
	profiles map[string]*customer.Profile
}

func newMockCustomerMemory() *mockCustomerMemory {
	return &mockCustomerMemory{profiles: make(map[string]*customer.Profile)}
}

func (m *mockCustomerMemory) GetByPhone(ctx context.Context, phone string) (*customer.Profile, error) {
	if p, ok := m.profiles[phone]; ok {
		return p, nil
	}
	return nil, nil
}

func (m *mockCustomerMemory) UpsertName(ctx context.Context, phone, name string) (*customer.Profile, error) {
	p := &customer.Profile{
		PhoneE164:   phone,
		DisplayName: name,
	}
	m.profiles[phone] = p
	return p, nil
}

func TestService_ProcessTurn_CustomerMemoryAndNaturalConversation(t *testing.T) {
	mockClient := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items: []RawExtractedItem{
				{
					MenuName:   "Nasi Goreng Spesial",
					Quantity:   1,
					Modifiers:  []string{"Pedas"},
					Confidence: 0.95,
				},
			},
			FulfillmentType: "PICKUP",
			PaymentMethod:   "QRIS",
			Confidence:      0.95,
		},
	}

	orderCreator := &mockOrderCreator{}

	mem := newMockCustomerMemory()
	svc := NewService(Config{
		Client:            mockClient,
		CatalogProvider:   &mockCatalogProvider{categories: sampleCatalog()},
		OrderCreator:      orderCreator,
		CustomerMemory:    mem,
		ConversationStore: NewMemoryConversationStore(),
	})

	ctx := context.Background()
	phone := "+6281234567890"

	// Turn 1: Customer introduces themselves naturally in the message
	turn1, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "Halo saya Yoga, mau pesan Nasi Goreng Spesial 1 pedas ya",
	})
	if err != nil {
		t.Fatalf("turn 1 failed: %v", err)
	}

	// Verify state and memory captured customer name
	if turn1.State.CustomerName != "Yoga" {
		t.Errorf("expected state customer name 'Yoga', got '%s'", turn1.State.CustomerName)
	}
	if p := mem.profiles[phone]; p == nil || p.DisplayName != "Yoga" {
		t.Errorf("expected customer memory to have name 'Yoga', got %+v", p)
	}

	// Verify summary addresses customer naturally by name and does NOT contain robotic commands
	if !strings.Contains(turn1.ReplyText, "kak Yoga") {
		t.Errorf("expected reply to address customer as 'kak Yoga', got:\n%s", turn1.ReplyText)
	}
	if strings.Contains(turn1.ReplyText, "(Ketik Ya untuk konfirmasi, atau Batal untuk membatalkan)") {
		t.Errorf("reply must not contain rigid robotic instructions, got:\n%s", turn1.ReplyText)
	}

	// Turn 2: Customer confirms using natural Indonesian slang / casual phrase
	turn2, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "iya pas kak, siap bungkus",
	})
	if err != nil {
		t.Fatalf("turn 2 failed: %v", err)
	}

	if turn2.State.Status != ConversationCompleted {
		t.Fatalf("expected status COMPLETED, got %s", turn2.State.Status)
	}

	// Verify order was created with customer's real name instead of "Pelanggan WhatsApp"
	if len(orderCreator.calls) != 1 {
		t.Fatalf("expected 1 order created, got %d", len(orderCreator.calls))
	}
	if orderCreator.calls[0].CustomerName != "Yoga" {
		t.Errorf("expected order customer name 'Yoga', got '%s'", orderCreator.calls[0].CustomerName)
	}

	// Verify success message personalizes with customer name
	if !strings.Contains(turn2.ReplyText, "kak Yoga") {
		t.Errorf("expected success message to address customer as 'kak Yoga', got:\n%s", turn2.ReplyText)
	}

	// Turn 3: Customer says thank you
	turn3, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:     "default",
		SenderPhone: phone,
		MessageText: "makasih ya kak",
	})
	if err != nil {
		t.Fatalf("turn 3 failed: %v", err)
	}
	if !strings.Contains(turn3.ReplyText, "kak Yoga") {
		t.Errorf("expected completed thank you reply to include 'kak Yoga', got:\n%s", turn3.ReplyText)
	}
}
