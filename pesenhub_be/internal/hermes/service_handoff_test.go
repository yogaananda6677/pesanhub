package hermes

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func TestService_ProcessTurn_ZeroAutoReplyDuringHandoff(t *testing.T) {
	ctx := context.Background()
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()
	runStore := NewMemoryStore()
	mockLLM := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items: []RawExtractedItem{
				{MenuName: "Nasi Goreng Spesial", Quantity: 1, Confidence: 0.95},
			},
			Confidence: 0.95,
		},
	}

	svc := NewService(Config{
		Client:            mockLLM,
		CatalogProvider:   provider,
		Store:             runStore,
		ConversationStore: convStore,
	})

	session := "session-zero-reply"
	phone := "+6281234567890"

	// 1. Manually pause automation by staff
	_, err := svc.PauseConversation(ctx, session, phone, "staff_yoga", "STAFF", "manual customer takeover", "corr-pause")
	if err != nil {
		t.Fatalf("failed to pause conversation: %v", err)
	}

	// 2. Customer sends message while paused
	inboundID := "msg-while-paused-1"
	resp, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:          session,
		SenderPhone:      phone,
		MessageText:      "Halo bot, apa kabar?",
		InboundMessageID: &inboundID,
	})
	if err != nil {
		t.Fatalf("expected nil error on paused conversation, got %v", err)
	}

	// 3. Verify zero auto-reply
	if resp.ReplyText != "" {
		t.Fatalf("expected empty reply text during takeover, got %q", resp.ReplyText)
	}
	if resp.HandledByAgent {
		t.Fatalf("expected HandledByAgent=false during takeover")
	}
	if !resp.AutomationPaused {
		t.Fatalf("expected AutomationPaused=true")
	}
	if !resp.RequiresHandoff {
		t.Fatalf("expected RequiresHandoff=true")
	}
	if resp.State.LastInboundMessageID == nil || *resp.State.LastInboundMessageID != inboundID {
		t.Fatalf("expected LastInboundMessageID to be recorded for staff")
	}
}

func TestService_ProcessTurn_ComplaintTrigger(t *testing.T) {
	ctx := context.Background()
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()
	runStore := NewMemoryStore()

	svc := NewService(Config{
		Client:            &MockLLMClient{},
		CatalogProvider:   provider,
		Store:             runStore,
		ConversationStore: convStore,
	})

	session := "session-complaint"
	phone := "+6281234567891"

	// Customer sends an angry complaint
	resp, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:     session,
		SenderPhone: phone,
		MessageText: "Kecewa sekali pelayanan buruk dan salah pesanan!",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !resp.RequiresHandoff {
		t.Fatalf("expected RequiresHandoff=true")
	}
	if resp.State.HandoffStatus != HandoffStatusPending {
		t.Errorf("expected HandoffStatus=PENDING, got %s", resp.State.HandoffStatus)
	}
	if resp.State.HandoffPriority != HandoffPriorityUrgent {
		t.Errorf("expected HandoffPriority=URGENT for complaint, got %s", resp.State.HandoffPriority)
	}
	if !strings.Contains(resp.ReplyText, "staf") {
		t.Errorf("expected reply mentioning staff, got %q", resp.ReplyText)
	}

	// Subsequent message while in handoff must not generate auto-reply
	resp2, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:     session,
		SenderPhone: phone,
		MessageText: "Woy respon dong",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp2.ReplyText != "" {
		t.Fatalf("expected zero auto-reply after complaint handoff, got %q", resp2.ReplyText)
	}
}

func TestService_ProcessTurn_HumanRequestTrigger(t *testing.T) {
	ctx := context.Background()
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()

	svc := NewService(Config{
		Client:            &MockLLMClient{},
		CatalogProvider:   provider,
		ConversationStore: convStore,
	})

	session := "session-human-req"
	phone := "+6281234567892"

	resp, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:     session,
		SenderPhone: phone,
		MessageText: "Tolong mau bicara sama admin atau manusia ya",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !resp.RequiresHandoff {
		t.Fatalf("expected RequiresHandoff=true")
	}
	if resp.State.HandoffPriority != HandoffPriorityHigh {
		t.Errorf("expected HandoffPriority=HIGH for human request, got %s", resp.State.HandoffPriority)
	}
	if !strings.Contains(resp.ReplyText, "staf") {
		t.Errorf("expected polite reply, got %q", resp.ReplyText)
	}
}

func TestService_ProcessTurn_OutOfScopeTrigger(t *testing.T) {
	ctx := context.Background()
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()

	svc := NewService(Config{
		Client:            &MockLLMClient{},
		CatalogProvider:   provider,
		ConversationStore: convStore,
	})

	session := "session-oos"
	phone := "+6281234567893"

	resp, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:     session,
		SenderPhone: phone,
		MessageText: "Halo apakah ada lowongan kerja di resto ini?",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !resp.RequiresHandoff {
		t.Fatalf("expected RequiresHandoff=true")
	}
	if resp.State.HandoffPriority != HandoffPriorityLow {
		t.Errorf("expected HandoffPriority=LOW for out-of-scope inquiry, got %s", resp.State.HandoffPriority)
	}
	if !strings.Contains(resp.ReplyText, "makanan dan minuman") {
		t.Errorf("expected polite domain rejection, got %q", resp.ReplyText)
	}
}

func TestService_ProcessTurn_RepeatedToolFailureDeterministicThreshold(t *testing.T) {
	ctx := context.Background()
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()
	runStore := NewMemoryStore()

	failingLLM := &MockLLMClient{
		Err: errors.New("simulated llm timeout error"),
	}

	svc := NewService(Config{
		Client:            failingLLM,
		CatalogProvider:   provider,
		Store:             runStore,
		ConversationStore: convStore,
	})

	session := "session-tool-fail"
	phone := "+6281234567894"

	// Failure 1
	_, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:     session,
		SenderPhone: phone,
		MessageText: "Pesan nasgor 1",
	})
	if err == nil {
		t.Fatalf("expected error on attempt 1")
	}
	state1, _ := convStore.GetOrCreate(ctx, session, phone, "c1")
	if state1.ToolFailureCount != 1 {
		t.Fatalf("expected ToolFailureCount=1, got %d", state1.ToolFailureCount)
	}

	// Failure 2
	_, err = svc.ProcessTurn(ctx, TurnRequest{
		Session:     session,
		SenderPhone: phone,
		MessageText: "Pesan nasgor 1",
	})
	if err == nil {
		t.Fatalf("expected error on attempt 2")
	}
	state2, _ := convStore.GetOrCreate(ctx, session, phone, "c2")
	if state2.ToolFailureCount != 2 {
		t.Fatalf("expected ToolFailureCount=2, got %d", state2.ToolFailureCount)
	}

	// Failure 3 (Threshold reached! Deterministic handoff triggered)
	resp3, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:     session,
		SenderPhone: phone,
		MessageText: "Pesan nasgor 1",
	})
	if err != nil {
		t.Fatalf("expected handoff response instead of raw error on reaching threshold, got %v", err)
	}
	if !resp3.RequiresHandoff {
		t.Fatalf("expected RequiresHandoff=true on repeated tool failure threshold")
	}
	if resp3.State.Status != ConversationHandoff {
		t.Fatalf("expected Status=HANDOFF, got %s", resp3.State.Status)
	}
	if resp3.State.HandoffStatus != HandoffStatusPending {
		t.Fatalf("expected HandoffStatus=PENDING, got %s", resp3.State.HandoffStatus)
	}
	if resp3.State.HandoffPriority != HandoffPriorityHigh {
		t.Fatalf("expected HandoffPriority=HIGH, got %s", resp3.State.HandoffPriority)
	}
	if !strings.Contains(resp3.ReplyText, "gangguan teknis") {
		t.Errorf("expected technical apology, got %q", resp3.ReplyText)
	}
}

func TestService_PauseAndResume_NoReplayOfOldMessages(t *testing.T) {
	ctx := context.Background()
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()
	runStore := NewMemoryStore()

	mockLLM := &MockLLMClient{
		Response: &RawExtractedOrder{
			Items: []RawExtractedItem{
				{MenuName: "Nasi Goreng Spesial", Quantity: 1, Modifiers: []string{"Pedas"}, Confidence: 0.95},
			},
			Confidence: 0.95,
		},
	}

	svc := NewService(Config{
		Client:            mockLLM,
		CatalogProvider:   provider,
		Store:             runStore,
		ConversationStore: convStore,
	})

	session := "session-resume-policy"
	phone := "+6281234567895"

	// 1. Staff pauses conversation
	_, err := svc.PauseConversation(ctx, session, phone, "staff_yoga", "STAFF", "takeover", "corr-1")
	if err != nil {
		t.Fatalf("failed to pause: %v", err)
	}

	// 2. Two messages arrive while paused
	respP1, _ := svc.ProcessTurn(ctx, TurnRequest{
		Session:     session,
		SenderPhone: phone,
		MessageText: "Pesan rahasia 1",
	})
	if respP1.ReplyText != "" {
		t.Fatalf("expected empty reply while paused")
	}

	respP2, _ := svc.ProcessTurn(ctx, TurnRequest{
		Session:     session,
		SenderPhone: phone,
		MessageText: "Pesan rahasia 2",
	})
	if respP2.ReplyText != "" {
		t.Fatalf("expected empty reply while paused")
	}

	if mockLLM.CallCount != 0 {
		t.Fatalf("expected 0 LLM calls while paused, got %d", mockLLM.CallCount)
	}

	// 3. Staff resumes conversation
	resumedState, err := svc.ResumeConversation(ctx, session, phone, "staff_yoga", "STAFF", "issue resolved", "corr-2")
	if err != nil {
		t.Fatalf("failed to resume: %v", err)
	}
	if resumedState.IsPaused {
		t.Fatalf("expected IsPaused=false after resume")
	}
	if resumedState.Status != ConversationCollecting {
		t.Fatalf("expected Status=COLLECTING after resume, got %s", resumedState.Status)
	}

	// Verify old messages were NOT replayed (LLM count is still 0!)
	if mockLLM.CallCount != 0 {
		t.Fatalf("old messages were unexpectedly replayed on resume! LLM call count=%d", mockLLM.CallCount)
	}

	// 4. New message arrives AFTER resume -> processed normally
	respAfter, err := svc.ProcessTurn(ctx, TurnRequest{
		Session:     session,
		SenderPhone: phone,
		MessageText: "Mau pesan Nasi Goreng Spesial 1 pedas ya kak",
	})
	if err != nil {
		t.Fatalf("unexpected error after resume: %v", err)
	}
	if mockLLM.CallCount != 1 {
		t.Fatalf("expected exactly 1 LLM call for the new message, got %d", mockLLM.CallCount)
	}
	if respAfter.ReplyText == "" {
		t.Fatalf("expected active reply after resume")
	}
}

func TestService_AssignAndResolve_AuditTrail(t *testing.T) {
	ctx := context.Background()
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()

	svc := NewService(Config{
		Client:            &MockLLMClient{},
		CatalogProvider:   provider,
		ConversationStore: convStore,
	})

	session := "session-audit"
	phone := "+6281234567896"

	// 1. Initial trigger handoff via complaint
	_, _ = svc.ProcessTurn(ctx, TurnRequest{
		Session:     session,
		SenderPhone: phone,
		MessageText: "Pelayanan sangat mengecewakan, saya komplain!",
	})

	state, _ := convStore.GetOrCreate(ctx, session, phone, "c")

	// 2. Staff pauses conversation
	_, err := svc.PauseConversation(ctx, session, phone, "staff_admin", "ADMIN", "customer escalation", "c-pause")
	if err != nil {
		t.Fatalf("failed to pause: %v", err)
	}

	// 3. Assign to staff_kasir_1
	assignedState, err := svc.AssignConversation(ctx, session, phone, "staff_admin", "ADMIN", "staff_kasir_1", "c-assign")
	if err != nil {
		t.Fatalf("failed to assign: %v", err)
	}
	if assignedState.HandoffStatus != HandoffStatusAssigned {
		t.Fatalf("expected HandoffStatus=ASSIGNED, got %s", assignedState.HandoffStatus)
	}
	if assignedState.AssignedTo == nil || *assignedState.AssignedTo != "staff_kasir_1" {
		t.Fatalf("expected AssignedTo=staff_kasir_1")
	}

	// 4. Resolve and resume automation
	resolvedState, err := svc.ResolveConversation(ctx, session, phone, "staff_kasir_1", "STAFF", "refund issued and customer satisfied", true, "c-resolve")
	if err != nil {
		t.Fatalf("failed to resolve: %v", err)
	}
	if resolvedState.HandoffStatus != HandoffStatusResolved {
		t.Fatalf("expected HandoffStatus=RESOLVED, got %s", resolvedState.HandoffStatus)
	}
	if resolvedState.IsPaused {
		t.Fatalf("expected IsPaused=false when resume_automation=true")
	}

	// 5. Query Audit Trail
	audits, err := svc.GetAuditLogs(ctx, state.ID)
	if err != nil {
		t.Fatalf("failed to get audit logs: %v", err)
	}
	if len(audits) < 4 {
		t.Fatalf("expected at least 4 audit events (TRIGGERED, PAUSED, ASSIGNED, RESOLVED), got %d", len(audits))
	}

	expectedActions := []string{HandoffActionTriggered, HandoffActionPaused, HandoffActionAssigned, HandoffActionResolved}
	for i, exp := range expectedActions {
		if audits[i].Action != exp {
			t.Errorf("audit[%d] expected action %q, got %q", i, exp, audits[i].Action)
		}
	}
}

func TestService_HandoffQueueFiltering(t *testing.T) {
	ctx := context.Background()
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()

	svc := NewService(Config{
		Client:            &MockLLMClient{},
		CatalogProvider:   provider,
		ConversationStore: convStore,
	})

	// Add 3 conversations with different handoff priorities
	// 1: Urgent (complaint)
	_, _ = svc.ProcessTurn(ctx, TurnRequest{
		Session:     "s1",
		SenderPhone: "+628111111111",
		MessageText: "Komplain pesanan salah!",
	})
	// 2: High (human request)
	_, _ = svc.ProcessTurn(ctx, TurnRequest{
		Session:     "s2",
		SenderPhone: "+628122222222",
		MessageText: "Mau bicara sama staf admin",
	})
	// 3: Low (out of scope)
	_, _ = svc.ProcessTurn(ctx, TurnRequest{
		Session:     "s3",
		SenderPhone: "+628133333333",
		MessageText: "Ada info lowongan kerja?",
	})

	// Query handoff queue
	items, total, err := svc.ListHandoffQueue(ctx, HandoffQueueFilter{})
	if err != nil {
		t.Fatalf("failed to list handoff queue: %v", err)
	}
	if total != 3 {
		t.Fatalf("expected 3 items in handoff queue, got %d", total)
	}

	// Check ordering: URGENT first, then HIGH, then LOW
	if items[0].HandoffPriority != HandoffPriorityUrgent {
		t.Errorf("expected first item to be URGENT, got %s", items[0].HandoffPriority)
	}
	if items[1].HandoffPriority != HandoffPriorityHigh {
		t.Errorf("expected second item to be HIGH, got %s", items[1].HandoffPriority)
	}
	if items[2].HandoffPriority != HandoffPriorityLow {
		t.Errorf("expected third item to be LOW, got %s", items[2].HandoffPriority)
	}

	// Filter by priority
	urgentItems, urgentTotal, err := svc.ListHandoffQueue(ctx, HandoffQueueFilter{Priority: HandoffPriorityUrgent})
	if err != nil {
		t.Fatalf("failed to filter by priority: %v", err)
	}
	if urgentTotal != 1 || len(urgentItems) != 1 {
		t.Fatalf("expected 1 urgent item, got %d", urgentTotal)
	}
	if urgentItems[0].CustomerPhone != "+628111111111" {
		t.Errorf("expected phone +628111111111, got %s", urgentItems[0].CustomerPhone)
	}
}
