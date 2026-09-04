package waha

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestInboundStoreIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set; skipping PostgreSQL integration test")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	store := NewStore(db)
	now := time.Now().UTC().Truncate(time.Microsecond)
	phone := "+6281234567890"

	msg := &InboundMessage{
		ID:                newID(),
		ProviderMessageID: "wamid-integration-" + newID(),
		WebhookRequestID:  "req-integ-1",
		Session:           "default",
		EventType:         "message",
		FromRaw:           "6281234567890@c.us",
		PhoneE164:         &phone,
		SenderName:        "Integ Customer",
		MessageBody:       "Halo dari integration test",
		PayloadRedacted:   []byte(`{"body":"Halo dari integration test"}`),
		Status:            StatusReceived,
		ReceivedAt:        now,
		CreatedAt:         now,
		UpdatedAt:         now,
	}

	// 1. Initial insert
	stored, isDuplicate, err := store.StoreInbound(ctx, msg)
	if err != nil {
		t.Fatalf("StoreInbound failed: %v", err)
	}
	if isDuplicate {
		t.Fatal("expected isDuplicate=false on first insert")
	}
	if stored.ID != msg.ID {
		t.Fatalf("expected ID %s, got %s", msg.ID, stored.ID)
	}
	if stored.PhoneE164 == nil || *stored.PhoneE164 != phone {
		t.Fatalf("expected PhoneE164 %s, got %v", phone, stored.PhoneE164)
	}

	// 2. Duplicate insert with same provider_message_id
	duplicateMsg := &InboundMessage{
		ID:                newID(),
		ProviderMessageID: msg.ProviderMessageID,
		WebhookRequestID:  "req-integ-2",
		Session:           "default",
		EventType:         "message",
		FromRaw:           "6281234567890@c.us",
		PhoneE164:         &phone,
		SenderName:        "Integ Customer",
		MessageBody:       "Pesan duplikat",
		PayloadRedacted:   []byte(`{"body":"Pesan duplikat"}`),
		Status:            StatusReceived,
		ReceivedAt:        now,
		CreatedAt:         now,
		UpdatedAt:         now,
	}

	gotExisting, isDup, err := store.StoreInbound(ctx, duplicateMsg)
	if err != nil {
		t.Fatalf("StoreInbound duplicate failed: %v", err)
	}
	if !isDup {
		t.Fatal("expected isDuplicate=true on second insert with same provider_message_id")
	}
	if gotExisting.ID != msg.ID {
		t.Fatalf("expected existing record ID %s, got %s", msg.ID, gotExisting.ID)
	}

	// 3. GetByProviderMessageID
	found, err := store.GetByProviderMessageID(ctx, msg.ProviderMessageID)
	if err != nil {
		t.Fatalf("GetByProviderMessageID failed: %v", err)
	}
	if found.ID != msg.ID {
		t.Fatalf("expected ID %s, got %s", msg.ID, found.ID)
	}

	// 4. Store Quarantined Message
	quarantinedMsg := &InboundMessage{
		ID:                newID(),
		ProviderMessageID: "wamid-quarantine-" + newID(),
		WebhookRequestID:  "req-integ-3",
		Session:           "default",
		EventType:         "message",
		FromRaw:           "120363025412345678@g.us",
		PhoneE164:         nil,
		SenderName:        "Grup WA",
		MessageBody:       "Pesan dari grup",
		PayloadRedacted:   []byte(`{"body":"Pesan dari grup"}`),
		Status:            StatusQuarantined,
		QuarantineReason:  "group_message_not_supported",
		ReceivedAt:        now,
		CreatedAt:         now,
		UpdatedAt:         now,
	}

	storedQ, isDupQ, err := store.StoreInbound(ctx, quarantinedMsg)
	if err != nil {
		t.Fatalf("StoreInbound quarantine failed: %v", err)
	}
	if isDupQ {
		t.Fatal("expected isDuplicate=false for quarantined msg")
	}
	if storedQ.Status != StatusQuarantined {
		t.Fatalf("expected status QUARANTINED, got %s", storedQ.Status)
	}
	if storedQ.PhoneE164 != nil {
		t.Fatalf("expected nil PhoneE164 for group, got %v", *storedQ.PhoneE164)
	}
}
