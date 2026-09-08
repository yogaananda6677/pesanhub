package hermes

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"pesenhub/backend/internal/customer"
)

func setupTestHandler() (*Handler, *Service, *MemoryConversationStore) {
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	convStore := NewMemoryConversationStore()
	runStore := NewMemoryStore()
	svc := NewService(Config{
		Client:            &MockLLMClient{},
		CatalogProvider:   provider,
		Store:             runStore,
		ConversationStore: convStore,
	})
	handler := NewHandler(svc)
	return handler, svc, convStore
}

func TestHandler_Authorization(t *testing.T) {
	handler, _, _ := setupTestHandler()

	// 1. Request without staff credentials -> 403
	req := httptest.NewRequest("GET", "/api/v1/agent/handoffs", nil)
	rr := httptest.NewRecorder()
	handler.ListHandoffs(rr, req)

	if rr.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden for unauthorized request, got %d", rr.Code)
	}

	// 2. Request with customer role -> 403
	req2 := httptest.NewRequest("GET", "/api/v1/agent/handoffs", nil)
	ctx := customer.WithPrincipal(req2.Context(), customer.Principal{Subject: "cust_1", Role: "CUSTOMER"})
	rr2 := httptest.NewRecorder()
	handler.ListHandoffs(rr2, req2.WithContext(ctx))

	if rr2.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden for customer role, got %d", rr2.Code)
	}

	// 3. Request with STAFF role in header -> 200
	req3 := httptest.NewRequest("GET", "/api/v1/agent/handoffs", nil)
	req3.Header.Set("X-Staff-ID", "staff_yoga")
	req3.Header.Set("X-Staff-Role", "STAFF")
	rr3 := httptest.NewRecorder()
	handler.ListHandoffs(rr3, req3)

	if rr3.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for STAFF credentials in headers, got %d: %s", rr3.Code, rr3.Body.String())
	}
}

func TestHandler_PauseResumeAssignResolveFlow(t *testing.T) {
	handler, svc, convStore := setupTestHandler()
	ctx := context.Background()

	session := "default"
	phone := "+6281999999999"

	// Create an initial active conversation
	_, _ = convStore.GetOrCreate(ctx, session, phone, "init-corr")

	// 1. Pause
	pauseBody := map[string]any{
		"session":        session,
		"customer_phone": phone,
		"reason":         "staf takeover for special request",
	}
	bodyBytes, _ := json.Marshal(pauseBody)
	reqPause := httptest.NewRequest("POST", "/api/v1/agent/conversations/pause", bytes.NewReader(bodyBytes))
	reqPause.Header.Set("X-Staff-ID", "staff_1")
	reqPause.Header.Set("X-Staff-Role", "STAFF")
	rrPause := httptest.NewRecorder()
	handler.Pause(rrPause, reqPause)

	if rrPause.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on pause, got %d: %s", rrPause.Code, rrPause.Body.String())
	}

	var pauseResp struct {
		Data ConversationState `json:"data"`
	}
	_ = json.Unmarshal(rrPause.Body.Bytes(), &pauseResp)
	if !pauseResp.Data.IsPaused {
		t.Errorf("expected IsPaused=true")
	}
	if pauseResp.Data.Status != ConversationPaused {
		t.Errorf("expected Status=PAUSED, got %s", pauseResp.Data.Status)
	}

	// 2. List Handoffs Queue
	reqList := httptest.NewRequest("GET", "/api/v1/agent/handoffs?status=PENDING", nil)
	reqList.Header.Set("X-Staff-ID", "staff_1")
	reqList.Header.Set("X-Staff-Role", "STAFF")
	rrList := httptest.NewRecorder()
	handler.ListHandoffs(rrList, reqList)

	if rrList.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on list handoffs, got %d", rrList.Code)
	}
	var listResp struct {
		Data []HandoffQueueItem `json:"data"`
		Meta map[string]any     `json:"meta"`
	}
	_ = json.Unmarshal(rrList.Body.Bytes(), &listResp)
	if len(listResp.Data) != 1 {
		t.Fatalf("expected 1 item in handoff queue, got %d", len(listResp.Data))
	}
	if listResp.Data[0].CustomerPhone != phone {
		t.Errorf("expected phone %s, got %s", phone, listResp.Data[0].CustomerPhone)
	}

	// 3. Assign
	assignBody := map[string]any{
		"session":        session,
		"customer_phone": phone,
		"assigned_to":    "staff_kasir_2",
	}
	assignBytes, _ := json.Marshal(assignBody)
	reqAssign := httptest.NewRequest("POST", "/api/v1/agent/conversations/assign", bytes.NewReader(assignBytes))
	reqAssign.Header.Set("X-Staff-ID", "staff_1")
	reqAssign.Header.Set("X-Staff-Role", "STAFF")
	rrAssign := httptest.NewRecorder()
	handler.Assign(rrAssign, reqAssign)

	if rrAssign.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on assign, got %d: %s", rrAssign.Code, rrAssign.Body.String())
	}

	// 4. Resolve
	resolveBody := map[string]any{
		"session":           session,
		"customer_phone":    phone,
		"resolution":        "handled manually, customer paid at cashier",
		"resume_automation": true,
	}
	resolveBytes, _ := json.Marshal(resolveBody)
	reqResolve := httptest.NewRequest("POST", "/api/v1/agent/conversations/resolve", bytes.NewReader(resolveBytes))
	reqResolve.Header.Set("X-Staff-ID", "staff_kasir_2")
	reqResolve.Header.Set("X-Staff-Role", "STAFF")
	rrResolve := httptest.NewRecorder()
	handler.Resolve(rrResolve, reqResolve)

	if rrResolve.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on resolve, got %d: %s", rrResolve.Code, rrResolve.Body.String())
	}

	var resolveResp struct {
		Data ConversationState `json:"data"`
	}
	_ = json.Unmarshal(rrResolve.Body.Bytes(), &resolveResp)
	if resolveResp.Data.HandoffStatus != HandoffStatusResolved {
		t.Errorf("expected HandoffStatus=RESOLVED, got %s", resolveResp.Data.HandoffStatus)
	}
	if resolveResp.Data.IsPaused {
		t.Errorf("expected IsPaused=false when resume_automation=true")
	}

	// 5. Get Audit Logs
	state, _ := convStore.GetOrCreate(ctx, session, phone, "test")
	reqAudit := httptest.NewRequest("GET", "/api/v1/agent/conversations/"+state.ID+"/audit-logs", nil)
	reqAudit.SetPathValue("id", state.ID)
	reqAudit.Header.Set("X-Staff-ID", "staff_1")
	reqAudit.Header.Set("X-Staff-Role", "STAFF")
	rrAudit := httptest.NewRecorder()
	handler.GetAuditLogs(rrAudit, reqAudit)

	if rrAudit.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on audit logs, got %d: %s", rrAudit.Code, rrAudit.Body.String())
	}

	var auditResp struct {
		Data []ConversationAuditEvent `json:"data"`
	}
	_ = json.Unmarshal(rrAudit.Body.Bytes(), &auditResp)
	if len(auditResp.Data) < 3 {
		t.Fatalf("expected at least 3 audit logs (PAUSED, ASSIGNED, RESOLVED), got %d", len(auditResp.Data))
	}

	_ = svc
}

func TestHandler_GetStatus(t *testing.T) {
	handler, _, _ := setupTestHandler()

	req := httptest.NewRequest("GET", "/api/v1/agent/status", nil)
	rr := httptest.NewRecorder()
	handler.GetStatus(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rr.Code, rr.Body.String())
	}

	var resp struct {
		Data map[string]any `json:"data"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if resp.Data["status"] != "READY" {
		t.Errorf("expected status READY, got %v", resp.Data["status"])
	}
	if resp.Data["agent"] != "Hermes" {
		t.Errorf("expected agent Hermes, got %v", resp.Data["agent"])
	}
}

func TestHandler_Turn(t *testing.T) {
	handler, _, _ := setupTestHandler()

	body := map[string]string{
		"session":        "default",
		"customer_phone": "+6281234567890",
		"message_text":   "halo mau pesan",
	}
	bodyBytes, _ := json.Marshal(body)

	// 1. Unauthorized request
	reqUnauth := httptest.NewRequest("POST", "/api/v1/agent/turn", bytes.NewReader(bodyBytes))
	rrUnauth := httptest.NewRecorder()
	handler.Turn(rrUnauth, reqUnauth)
	if rrUnauth.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden, got %d", rrUnauth.Code)
	}

	// 2. Authorized request
	reqAuth := httptest.NewRequest("POST", "/api/v1/agent/turn", bytes.NewReader(bodyBytes))
	reqAuth.Header.Set("X-Staff-ID", "staff_1")
	reqAuth.Header.Set("X-Staff-Role", "STAFF")
	rrAuth := httptest.NewRecorder()
	handler.Turn(rrAuth, reqAuth)

	if rrAuth.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rrAuth.Code, rrAuth.Body.String())
	}

	var resp struct {
		Data TurnResponse `json:"data"`
	}
	if err := json.Unmarshal(rrAuth.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to unmarshal turn response: %v", err)
	}
	if resp.Data.State == nil {
		t.Fatalf("expected state not to be nil")
	}
}

