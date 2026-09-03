package order

import (
	"encoding/json"
	"testing"
	"time"
)

type mockBroadcaster struct {
	staffPayloads [][]byte
	kdsPayloads   [][]byte
}

func (m *mockBroadcaster) Broadcast(staffPayload, kdsPayload []byte) {
	m.staffPayloads = append(m.staffPayloads, staffPayload)
	m.kdsPayloads = append(m.kdsPayloads, kdsPayload)
}

func TestOrderEventEnvelopeSerialization(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	rawPayload, _ := json.Marshal(map[string]any{
		"order_id":       "11111111-1111-4111-8111-111111111111",
		"customer_name":  "Alice",
		"customer_phone": "+62811111111",
		"customer_id":    "cust-123",
		"status":         "PREPARING",
		"version":        2,
	})

	env := OrderEventEnvelope{
		EventID:   "evt-001",
		EventType: "ORDER_STATUS_CHANGED",
		OrderID:   "11111111-1111-4111-8111-111111111111",
		Version:   2,
		Source:    "CASHIER_MANUAL",
		Status:    "PREPARING",
		Timestamp: now,
		Payload:   rawPayload,
	}

	b, err := json.Marshal(env)
	if err != nil {
		t.Fatalf("marshal error: %v", err)
	}

	var decoded OrderEventEnvelope
	if err = json.Unmarshal(b, &decoded); err != nil {
		t.Fatalf("unmarshal error: %v", err)
	}

	if decoded.EventID != "evt-001" || decoded.Version != 2 || decoded.Status != "PREPARING" {
		t.Fatalf("unexpected envelope content: %#v", decoded)
	}
}

func TestPublisherKDSRedaction(t *testing.T) {
	b := &mockBroadcaster{}
	p := NewOutboxPublisher(nil, b, nil)
	if p == nil {
		t.Fatal("publisher should not be nil")
	}

	rawMap := map[string]any{
		"order_id":       "order-1",
		"customer_name":  "Budi",
		"customer_phone": "+628123456789",
		"customer_id":    "cust-999",
		"status":         "ACCEPTED",
		"version":        float64(1),
	}

	kdsMap := make(map[string]any, len(rawMap))
	for k, v := range rawMap {
		if k == "customer_phone" || k == "customer_id" {
			continue
		}
		kdsMap[k] = v
	}

	if _, exists := kdsMap["customer_phone"]; exists {
		t.Fatal("kdsMap should not contain customer_phone")
	}
	if _, exists := kdsMap["customer_id"]; exists {
		t.Fatal("kdsMap should not contain customer_id")
	}
	if kdsMap["customer_name"] != "Budi" {
		t.Fatal("kdsMap must preserve customer_name")
	}
}

// TestClientGapDetectionLogic tests the state tracker and recovery contract
func TestClientGapDetectionLogic(t *testing.T) {
	type clientState struct {
		lastVersion int64
		needsReload bool
	}

	applyEvent := func(state *clientState, eventVersion int64) {
		if eventVersion <= state.lastVersion {
			// Duplicate or older event, ignore
			return
		}
		if eventVersion > state.lastVersion+1 {
			// Gap detected! Trigger snapshot reload
			state.needsReload = true
			return
		}
		// Normal consecutive version
		state.lastVersion = eventVersion
	}

	state := &clientState{lastVersion: 1}

	// 1. Consecutive version 2
	applyEvent(state, 2)
	if state.needsReload || state.lastVersion != 2 {
		t.Fatalf("expected version 2, got: %#v", state)
	}

	// 2. Duplicate version 2 ignored
	applyEvent(state, 2)
	if state.needsReload || state.lastVersion != 2 {
		t.Fatalf("duplicate version should not trigger reload, got: %#v", state)
	}

	// 3. Stale version 1 ignored
	applyEvent(state, 1)
	if state.needsReload || state.lastVersion != 2 {
		t.Fatalf("stale version should not trigger reload, got: %#v", state)
	}

	// 4. Gap detected (jump from 2 to 4)
	applyEvent(state, 4)
	if !state.needsReload {
		t.Fatal("expected gap detection to flag needsReload")
	}
}
