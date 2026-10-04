package superadmin

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"pesenhub/backend/internal/appauth"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/gowa"
)

type mockStore struct {
	users            []UserSummary
	invitations      []Invitation
	audits           []AuditEntry
	traffic          TrafficMetrics
	createInvErr     error
	revokeInvErr     error
	updateStatusErr  error
	revokeSessErr    error
	listUsersErr     error
	getUserErr       error
	user             *UserSummary
	employeeRoleFunc func(ctx context.Context, id string) (string, error)
}

func (m *mockStore) GetUser(ctx context.Context, userID string) (*UserSummary, error) {
	if m.getUserErr != nil {
		return nil, m.getUserErr
	}
	if m.user != nil {
		return m.user, nil
	}
	for _, u := range m.users {
		if u.ID == userID {
			return &u, nil
		}
	}
	return nil, ErrUserNotFound
}

func (m *mockStore) ListUsers(ctx context.Context, filterStatus Status, search string, limit, offset int) ([]UserSummary, error) {
	if m.listUsersErr != nil {
		return nil, m.listUsersErr
	}
	return m.users, nil
}

func (m *mockStore) ListInvitations(ctx context.Context, limit, offset int) ([]Invitation, error) {
	return m.invitations, nil
}

func (m *mockStore) CreateInvitation(ctx context.Context, actorID, email, outletName, branchID string, expiry time.Duration) (Invitation, error) {
	if m.createInvErr != nil {
		return Invitation{}, m.createInvErr
	}
	return Invitation{
		ID:          "inv-123",
		EmailMasked: MaskEmail(email),
		OutletName:  outletName,
		Role:        RoleCashier,
		Status:      "PENDING",
		InvitedBy:   actorID,
		CreatedAt:   time.Now().UTC(),
		ExpiresAt:   time.Now().UTC().Add(expiry),
	}, nil
}

func TestAdminCanInviteCashierButOtherRolesCannot(t *testing.T) {
	handler := NewHandler(NewService(&mockStore{}, nil, nil, nil))
	for _, role := range []string{"", "CASHIER", "STAFF", "SUPERADMIN"} {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/admin/cashiers/invitations", bytes.NewBufferString(`{"email":"cashier@example.com"}`))
		req = withPrincipal(req, role)
		rec := httptest.NewRecorder()
		handler.InviteCashier(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Fatalf("role %q: expected 403, got %d", role, rec.Code)
		}
	}
	// Admin without branch_id is rejected with 400
	reqMissingBranch := httptest.NewRequest(http.MethodPost, "/api/v1/admin/cashiers/invitations", bytes.NewBufferString(`{"email":"cashier@example.com"}`))
	reqMissingBranch = withPrincipal(reqMissingBranch, "ADMIN")
	recMissingBranch := httptest.NewRecorder()
	handler.InviteCashier(recMissingBranch, reqMissingBranch)
	if recMissingBranch.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invitation without branch, got %d", recMissingBranch.Code)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/v1/admin/cashiers/invitations", bytes.NewBufferString(`{"email":"cashier@example.com","branch_id":"b0000000-0000-0000-0000-000000000001"}`))
	req = withPrincipal(req, "ADMIN")
	rec := httptest.NewRecorder()
	handler.InviteCashier(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var invitation Invitation
	if err := json.Unmarshal(rec.Body.Bytes(), &invitation); err != nil || invitation.Role != RoleCashier {
		t.Fatalf("invitation=%#v err=%v", invitation, err)
	}
}

func TestUpdateCashierBranchAuthorization(t *testing.T) {
	handler := NewHandler(NewService(&mockStore{}, nil, nil, nil))
	targetUserID := "user-cashier-1"
	newBranchID := "b0000000-0000-0000-0000-000000000002"

	// 1. Unauthenticated or non-admin roles are rejected with 403
	for _, role := range []string{"", "CASHIER", "STAFF"} {
		req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/cashiers/"+targetUserID+"/branch", bytes.NewBufferString(`{"branch_id":"`+newBranchID+`"}`))
		req.SetPathValue("id", targetUserID)
		req = withPrincipal(req, role)
		rec := httptest.NewRecorder()
		handler.UpdateCashierBranch(rec, req)
		if role == "" && rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 for unauthenticated, got %d", rec.Code)
		} else if role != "" && rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403 for role %s, got %d", role, rec.Code)
		}
	}

	// 2. Cashier cannot transfer themselves even if trying to act
	reqSelf := httptest.NewRequest(http.MethodPut, "/api/v1/admin/cashiers/"+targetUserID+"/branch", bytes.NewBufferString(`{"branch_id":"`+newBranchID+`"}`))
	reqSelf.SetPathValue("id", targetUserID)
	reqSelf = reqSelf.WithContext(customer.WithPrincipal(reqSelf.Context(), customer.Principal{
		Subject: targetUserID,
		Role:    "CASHIER",
	}))
	recSelf := httptest.NewRecorder()
	handler.UpdateCashierBranch(recSelf, reqSelf)
	if recSelf.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when cashier tries to move themselves, got %d", recSelf.Code)
	}

	// 3. Admin can transfer cashier
	reqAdmin := httptest.NewRequest(http.MethodPut, "/api/v1/admin/cashiers/"+targetUserID+"/branch", bytes.NewBufferString(`{"branch_id":"`+newBranchID+`"}`))
	reqAdmin.SetPathValue("id", targetUserID)
	reqAdmin = withPrincipal(reqAdmin, "ADMIN")
	recAdmin := httptest.NewRecorder()
	handler.UpdateCashierBranch(recAdmin, reqAdmin)
	if recAdmin.Code != http.StatusOK {
		t.Fatalf("expected 200 for admin, got %d: %s", recAdmin.Code, recAdmin.Body.String())
	}
}

func (m *mockStore) RevokeInvitation(ctx context.Context, invitationID string) error {
	return m.revokeInvErr
}

func (m *mockStore) UpdateUserStatus(ctx context.Context, actorID, targetUserID string, targetStatus Status, reason, requestID string) error {
	return m.updateStatusErr
}

func (m *mockStore) UpdateUserBranch(ctx context.Context, actorID, targetUserID, branchID, reason, requestID string) error {
	return nil
}

func (m *mockStore) RevokeUserSessions(ctx context.Context, targetUserID string) error {
	return m.revokeSessErr
}

func (m *mockStore) ListAudits(ctx context.Context, targetUserID string, limit, offset int) ([]AuditEntry, error) {
	return m.audits, nil
}

func (m *mockStore) GetTrafficMetrics(ctx context.Context, timeRange string) (TrafficMetrics, error) {
	return m.traffic, nil
}

func (m *mockStore) ListEmployees(ctx context.Context, search string) ([]EmployeeSummary, error) {
	return []EmployeeSummary{}, nil
}

func (m *mockStore) GetEmployeeRole(ctx context.Context, id string) (string, error) {
	if m.employeeRoleFunc != nil {
		return m.employeeRoleFunc(ctx, id)
	}
	return "CASHIER", nil
}

func (m *mockStore) CreateEmployee(ctx context.Context, actorID, email, displayName, role, branchID, password string) (EmployeeSummary, error) {
	return EmployeeSummary{ID: "emp-123", Email: email, DisplayName: displayName, Role: role, Status: "APPROVED"}, nil
}

func (m *mockStore) UpdateEmployee(ctx context.Context, targetUserID string, displayName, role, status, branchID *string) (EmployeeSummary, error) {
	return EmployeeSummary{ID: targetUserID, Status: "UPDATED"}, nil
}

func (m *mockStore) DeleteEmployee(ctx context.Context, targetUserID string) error {
	return nil
}

type mockDB struct {
	pingErr error
}

func (m *mockDB) Ping(ctx context.Context) error {
	return m.pingErr
}

type mockGOWA struct {
	readiness gowa.Readiness
}

func (m *mockGOWA) Readiness(ctx context.Context) gowa.Readiness {
	return m.readiness
}

type mockWSCounter struct {
	count int
}

func (m *mockWSCounter) ClientCount() int {
	return m.count
}

func withPrincipal(req *http.Request, role string) *http.Request {
	if role == "" {
		return req
	}
	return req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{
		Subject: "user-" + role,
		Role:    role,
	}))
}

func TestSuperadminRBAC(t *testing.T) {
	store := &mockStore{}
	service := NewService(store, &mockDB{}, nil, nil)
	handler := NewHandler(service)

	endpoints := []struct {
		name    string
		method  string
		path    string
		handler http.HandlerFunc
	}{
		{"HealthSnapshot", "GET", "/api/v1/superadmin/health/snapshot", handler.HealthSnapshot},
		{"TrafficTelemetry", "GET", "/api/v1/superadmin/telemetry/traffic", handler.TrafficTelemetry},
		{"ListUsers", "GET", "/api/v1/superadmin/users", handler.ListUsers},
		{"ListInvitations", "GET", "/api/v1/superadmin/users/invitations", handler.ListInvitations},
		{"Invite", "POST", "/api/v1/superadmin/users/invite", handler.Invite},
		{"ListAudits", "GET", "/api/v1/superadmin/audits", handler.ListAudits},
	}

	disallowedRoles := []string{"", "STAFF", "OWNER", "KDS", "CUSTOMER"}

	for _, ep := range endpoints {
		for _, role := range disallowedRoles {
			t.Run(ep.name+"_Disallowed_"+role, func(t *testing.T) {
				req := httptest.NewRequest(ep.method, ep.path, nil)
				req = withPrincipal(req, role)
				rec := httptest.NewRecorder()

				ep.handler(rec, req)

				if rec.Code != http.StatusForbidden {
					t.Fatalf("expected 403 Forbidden for role %q, got %d", role, rec.Code)
				}
			})
		}

		t.Run(ep.name+"_Allowed_SUPERADMIN", func(t *testing.T) {
			var body []byte
			if ep.method == "POST" {
				body = []byte(`{"email":"test@example.com"}`)
			}
			req := httptest.NewRequest(ep.method, ep.path, bytes.NewReader(body))
			req = withPrincipal(req, "SUPERADMIN")
			rec := httptest.NewRecorder()

			ep.handler(rec, req)

			if rec.Code == http.StatusForbidden {
				t.Fatalf("expected SUPERADMIN to be authorized, got 403")
			}
		})
	}
}

func TestHealthSnapshot(t *testing.T) {
	store := &mockStore{}
	db := &mockDB{}
	gw := &mockGOWA{
		readiness: gowa.Readiness{API: gowa.APIUp, Device: gowa.DeviceReady},
	}
	wsCounter := &mockWSCounter{count: 4}
	svc := NewService(store, db, gw, wsCounter)
	h := NewHandler(svc)

	req := httptest.NewRequest("GET", "/api/v1/superadmin/health/snapshot", nil)
	req = withPrincipal(req, "SUPERADMIN")
	rec := httptest.NewRecorder()

	h.HealthSnapshot(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}

	var snapshot SystemHealthSnapshot
	if err := json.Unmarshal(rec.Body.Bytes(), &snapshot); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if snapshot.OverallStatus != HealthHealthy {
		t.Errorf("expected overall_status healthy, got %s", snapshot.OverallStatus)
	}
	if len(snapshot.Components) != 6 {
		t.Errorf("expected 6 components, got %d", len(snapshot.Components))
	}
}

func TestUserManagementEndpoints(t *testing.T) {
	store := &mockStore{
		users: []UserSummary{
			{ID: "u1", EmailMasked: "ow***@example.com", Role: RoleOwner, Status: StatusPending},
		},
		invitations: []Invitation{
			{ID: "inv1", EmailMasked: "ne***@example.com", Status: "PENDING"},
		},
	}
	svc := NewService(store, nil, nil, nil)
	h := NewHandler(svc)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/superadmin/users", h.ListUsers)
	mux.HandleFunc("GET /api/v1/superadmin/users/invitations", h.ListInvitations)
	mux.HandleFunc("POST /api/v1/superadmin/users/invite", h.Invite)
	mux.HandleFunc("DELETE /api/v1/superadmin/users/invitations/{id}", h.RevokeInvitation)
	mux.HandleFunc("POST /api/v1/superadmin/users/{id}/approve", h.Approve)
	mux.HandleFunc("POST /api/v1/superadmin/users/{id}/reject", h.Reject)
	mux.HandleFunc("POST /api/v1/superadmin/users/{id}/suspend", h.Suspend)
	mux.HandleFunc("POST /api/v1/superadmin/users/{id}/reactivate", h.Reactivate)
	mux.HandleFunc("POST /api/v1/superadmin/users/{id}/revoke-sessions", h.RevokeSessions)

	t.Run("ListUsers", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/api/v1/superadmin/users?status=PENDING_APPROVAL", nil)
		req = withPrincipal(req, "SUPERADMIN")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
	})

	t.Run("Invite_Success", func(t *testing.T) {
		body := `{"email": "partner@business.com", "outlet_name": "Cabang Baru"}`
		req := httptest.NewRequest("POST", "/api/v1/superadmin/users/invite", bytes.NewBufferString(body))
		req = withPrincipal(req, "SUPERADMIN")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("expected 201 Created, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Invite_InvalidEmail", func(t *testing.T) {
		body := `{"email": "invalid-email"}`
		req := httptest.NewRequest("POST", "/api/v1/superadmin/users/invite", bytes.NewBufferString(body))
		req = withPrincipal(req, "SUPERADMIN")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)

		if rec.Code != http.StatusUnprocessableEntity {
			t.Fatalf("expected 422, got %d", rec.Code)
		}
	})

	t.Run("Invite_DuplicateConflict", func(t *testing.T) {
		store.createInvErr = ErrUserAlreadyExists
		defer func() { store.createInvErr = nil }()

		body := `{"email": "existing@business.com"}`
		req := httptest.NewRequest("POST", "/api/v1/superadmin/users/invite", bytes.NewBufferString(body))
		req = withPrincipal(req, "SUPERADMIN")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)

		if rec.Code != http.StatusConflict {
			t.Fatalf("expected 409 Conflict, got %d", rec.Code)
		}
	})

	t.Run("RevokeInvitation_Success", func(t *testing.T) {
		req := httptest.NewRequest("DELETE", "/api/v1/superadmin/users/invitations/inv1", nil)
		req = withPrincipal(req, "SUPERADMIN")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
	})

	t.Run("Approve_Success", func(t *testing.T) {
		body := `{"reason": "Document verified"}`
		req := httptest.NewRequest("POST", "/api/v1/superadmin/users/u1/approve", bytes.NewBufferString(body))
		req = withPrincipal(req, "SUPERADMIN")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Reject_Success", func(t *testing.T) {
		body := `{"reason": "Invalid document"}`
		req := httptest.NewRequest("POST", "/api/v1/superadmin/users/u1/reject", bytes.NewBufferString(body))
		req = withPrincipal(req, "SUPERADMIN")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Suspend_Success", func(t *testing.T) {
		body := `{"reason": "Policy violation"}`
		req := httptest.NewRequest("POST", "/api/v1/superadmin/users/u1/suspend", bytes.NewBufferString(body))
		req = withPrincipal(req, "SUPERADMIN")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("RevokeSessions_Success", func(t *testing.T) {
		req := httptest.NewRequest("POST", "/api/v1/superadmin/users/u1/revoke-sessions", nil)
		req = withPrincipal(req, "SUPERADMIN")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
	})

	t.Run("Approve_NotFound", func(t *testing.T) {
		store.updateStatusErr = ErrUserNotFound
		defer func() { store.updateStatusErr = nil }()

		req := httptest.NewRequest("POST", "/api/v1/superadmin/users/not-found/approve", nil)
		req = withPrincipal(req, "SUPERADMIN")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)

		if rec.Code != http.StatusNotFound {
			t.Fatalf("expected 404, got %d", rec.Code)
		}
	})

	t.Run("Approve_InvalidTransition", func(t *testing.T) {
		store.updateStatusErr = ErrInvalidStatusAction
		defer func() { store.updateStatusErr = nil }()

		req := httptest.NewRequest("POST", "/api/v1/superadmin/users/u1/approve", nil)
		req = withPrincipal(req, "SUPERADMIN")
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)

		if rec.Code != http.StatusConflict {
			t.Fatalf("expected 409, got %d", rec.Code)
		}
	})
}

func TestTrafficTelemetryEndpoint(t *testing.T) {
	store := &mockStore{
		traffic: TrafficMetrics{
			TimeRange:       "24h",
			TotalRequests:   1000,
			SuccessRequests: 990,
			SuccessRate:     99.0,
			LatencyP50Ms:    15,
			LatencyP95Ms:    45,
		},
	}
	svc := NewService(store, nil, nil, nil)
	h := NewHandler(svc)

	req := httptest.NewRequest("GET", "/api/v1/superadmin/telemetry/traffic?range=24h", nil)
	req = withPrincipal(req, "SUPERADMIN")
	rec := httptest.NewRecorder()

	h.TrafficTelemetry(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", rec.Code)
	}

	var metrics TrafficMetrics
	if err := json.Unmarshal(rec.Body.Bytes(), &metrics); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if metrics.TotalRequests != 1000 || metrics.SuccessRate != 99.0 {
		t.Errorf("unexpected metrics values: %+v", metrics)
	}
}

func TestAuditsEndpoint(t *testing.T) {
	store := &mockStore{
		audits: []AuditEntry{
			{
				ID:                    "a1",
				UserID:                "u1",
				TargetUserMaskedEmail: "ow***@example.com",
				ToStatus:              "APPROVED",
				CreatedAt:             time.Now().UTC(),
			},
		},
	}
	svc := NewService(store, nil, nil, nil)
	h := NewHandler(svc)

	req := httptest.NewRequest("GET", "/api/v1/superadmin/audits", nil)
	req = withPrincipal(req, "SUPERADMIN")
	rec := httptest.NewRecorder()

	h.ListAudits(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", rec.Code)
	}
}

type mockAuthStore struct {
	user        appauth.User
	ensureErr   error
	createErr   error
	createdSess map[string]string
}

func (m *mockAuthStore) EnsureSuperadmin(ctx context.Context, defaultEmail, defaultName string) (appauth.User, error) {
	if m.ensureErr != nil {
		return appauth.User{}, m.ensureErr
	}
	return m.user, nil
}

func (m *mockAuthStore) CreateSession(ctx context.Context, sessionID, userID string, expiresAt time.Time) error {
	if m.createErr != nil {
		return m.createErr
	}
	if m.createdSess == nil {
		m.createdSess = make(map[string]string)
	}
	m.createdSess[sessionID] = userID
	return nil
}

type mockSessionIssuer struct {
	token     string
	sessionID string
	expiresAt time.Time
	err       error
}

func (m *mockSessionIssuer) IssuePersistent(subject, role string) (string, string, time.Time, error) {
	if m.err != nil {
		return "", "", time.Time{}, m.err
	}
	return m.token, m.sessionID, m.expiresAt, nil
}

func TestSuperadminLoginSuccess(t *testing.T) {
	h := NewHandler(nil)
	authStore := &mockAuthStore{
		user: appauth.User{
			ID:          "sa-uuid-1234",
			EmailMasked: "su***@pesenhub.id",
			DisplayName: "Superadmin",
			Role:        appauth.RoleSuperadmin,
			Status:      appauth.StatusApproved,
		},
	}
	sessIssuer := &mockSessionIssuer{
		token:     "valid-superadmin-session-token",
		sessionID: "sid-5678",
		expiresAt: time.Now().Add(8 * time.Hour),
	}
	h.SetAuth(AuthConfig{Username: "superadmin", Password: "superadmin-secret-password"}, authStore, sessIssuer)

	body := `{"username":"superadmin","password":"superadmin-secret-password"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/superadmin/login", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	h.Login(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if resp["access_token"] != "valid-superadmin-session-token" {
		t.Fatalf("unexpected token: %v", resp["access_token"])
	}
	userMap, ok := resp["user"].(map[string]any)
	if !ok || userMap["role"] != "SUPERADMIN" {
		t.Fatalf("unexpected user in response: %v", resp["user"])
	}
}

func TestSuperadminLoginInvalidCredentials(t *testing.T) {
	h := NewHandler(nil)
	h.SetAuth(AuthConfig{Username: "superadmin", Password: "correct-password"}, &mockAuthStore{}, &mockSessionIssuer{})

	cases := []struct {
		name     string
		username string
		password string
	}{
		{"wrong password", "superadmin", "wrong-password"},
		{"wrong username", "admin", "correct-password"},
		{"both wrong", "unknown", "unknown"},
		{"empty password", "superadmin", ""},
		{"empty username", "", "correct-password"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			body, _ := json.Marshal(map[string]string{"username": tc.username, "password": tc.password})
			req := httptest.NewRequest(http.MethodPost, "/api/v1/superadmin/login", bytes.NewReader(body))
			rec := httptest.NewRecorder()

			h.Login(rec, req)

			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("expected 401 Unauthorized, got %d: %s", rec.Code, rec.Body.String())
			}
		})
	}
}

func TestSuperadminLoginRateLimited(t *testing.T) {
	h := NewHandler(nil)
	h.SetAuth(AuthConfig{Username: "superadmin", Password: "secret"}, &mockAuthStore{}, &mockSessionIssuer{})

	for i := 0; i < 5; i++ {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/superadmin/login", bytes.NewBufferString(`{"username":"superadmin","password":"wrong"}`))
		req.RemoteAddr = "192.0.2.1:12345"
		rec := httptest.NewRecorder()
		h.Login(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("attempt %d: expected 401, got %d", i+1, rec.Code)
		}
	}

	// 6th attempt should be rate limited
	req := httptest.NewRequest(http.MethodPost, "/api/v1/superadmin/login", bytes.NewBufferString(`{"username":"superadmin","password":"wrong"}`))
	req.RemoteAddr = "192.0.2.1:12345"
	rec := httptest.NewRecorder()
	h.Login(rec, req)

	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429 Too Many Requests, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestSuperadminLoginInvalidBody(t *testing.T) {
	h := NewHandler(nil)
	h.SetAuth(AuthConfig{Username: "superadmin", Password: "secret"}, &mockAuthStore{}, &mockSessionIssuer{})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/superadmin/login", bytes.NewBufferString(`{invalid-json`))
	rec := httptest.NewRecorder()
	h.Login(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request, got %d", rec.Code)
	}
}

type mockWAInspector struct {
	readiness    gowa.Readiness
	deviceID     string
	activeDevice *gowa.DeviceInfo
	resolveErr   error
	devices      []gowa.DeviceInfo
	listErr      error
}

func (m *mockWAInspector) Readiness(ctx context.Context) gowa.Readiness {
	return m.readiness
}

func (m *mockWAInspector) DeviceID() string {
	return m.deviceID
}

func (m *mockWAInspector) ListDevices(ctx context.Context) ([]gowa.DeviceInfo, error) {
	if m.listErr != nil {
		return nil, m.listErr
	}
	return m.devices, nil
}

func (m *mockWAInspector) ResolveActiveDevice(ctx context.Context) (*gowa.DeviceInfo, error) {
	if m.resolveErr != nil {
		return nil, m.resolveErr
	}
	return m.activeDevice, nil
}

func TestUserWhatsAppStatusEndpoint(t *testing.T) {
	store := &mockStore{
		user: &UserSummary{
			ID:          "u-admin-1",
			DisplayName: "Admin Outlet",
			EmailMasked: "ad***@example.com",
			Role:        RoleAdmin,
			Status:      StatusApproved,
		},
	}
	wa := &mockWAInspector{
		readiness: gowa.Readiness{API: gowa.APIUp, Device: gowa.DeviceReady},
		deviceID:  "pesenhub-dev",
		activeDevice: &gowa.DeviceInfo{
			ID:    "pesenhub-dev",
			State: "logged_in",
			JID:   "628123456789@s.whatsapp.net",
		},
	}
	svc := NewService(store, nil, wa, nil)
	h := NewHandler(svc)

	// 1. Success connected
	req := httptest.NewRequest("GET", "/api/v1/superadmin/users/u-admin-1/whatsapp", nil)
	req.SetPathValue("id", "u-admin-1")
	req = withPrincipal(req, "SUPERADMIN")
	rec := httptest.NewRecorder()
	h.UserWhatsAppStatus(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}
	var res WhatsAppAccountStatus
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatalf("unmarshal error: %v", err)
	}
	if !res.IsConnected || res.Status != "CONNECTED" || res.PhoneMasked != "+6281****6789" {
		t.Fatalf("unexpected res: %+v", res)
	}

	// 2. Gateway down
	wa.readiness = gowa.Readiness{API: gowa.APIDown}
	req = httptest.NewRequest("GET", "/api/v1/superadmin/users/u-admin-1/whatsapp", nil)
	req.SetPathValue("id", "u-admin-1")
	req = withPrincipal(req, "SUPERADMIN")
	rec = httptest.NewRecorder()
	h.UserWhatsAppStatus(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", rec.Code)
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatalf("unmarshal error: %v", err)
	}
	if res.IsConnected || res.Status != "GATEWAY_DOWN" {
		t.Fatalf("expected GATEWAY_DOWN, got %+v", res)
	}

	// 3. User not found
	store.getUserErr = ErrUserNotFound
	req = httptest.NewRequest("GET", "/api/v1/superadmin/users/non-existent/whatsapp", nil)
	req.SetPathValue("id", "non-existent")
	req = withPrincipal(req, "SUPERADMIN")
	rec = httptest.NewRecorder()
	h.UserWhatsAppStatus(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 Not Found, got %d", rec.Code)
	}
}

func TestWhatsAppOverviewEndpoint(t *testing.T) {
	store := &mockStore{
		users: []UserSummary{
			{
				ID:          "u-admin-1",
				DisplayName: "Admin Outlet",
				EmailMasked: "ad***@example.com",
				Role:        RoleAdmin,
				Status:      StatusApproved,
			},
		},
		user: &UserSummary{
			ID:          "u-admin-1",
			DisplayName: "Admin Outlet",
			EmailMasked: "ad***@example.com",
			Role:        RoleAdmin,
			Status:      StatusApproved,
		},
	}
	wa := &mockWAInspector{
		readiness: gowa.Readiness{API: gowa.APIUp, Device: gowa.DeviceReady},
		deviceID:  "pesenhub-dev",
		activeDevice: &gowa.DeviceInfo{
			ID:    "pesenhub-dev",
			State: "logged_in",
			JID:   "628123456789@s.whatsapp.net",
		},
	}
	svc := NewService(store, nil, wa, nil)
	h := NewHandler(svc)

	req := httptest.NewRequest("GET", "/api/v1/superadmin/whatsapp/status", nil)
	req = withPrincipal(req, "SUPERADMIN")
	rec := httptest.NewRecorder()
	h.WhatsAppOverview(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Accounts []WhatsAppAccountStatus `json:"accounts"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal error: %v", err)
	}
	if len(resp.Accounts) != 1 || resp.Accounts[0].Status != "CONNECTED" {
		t.Fatalf("unexpected accounts: %+v", resp.Accounts)
	}
}

func TestAdminCannotManageFellowAdminButCanManageCashier(t *testing.T) {
	store := &mockStore{
		employeeRoleFunc: func(ctx context.Context, id string) (string, error) {
			if id == "admin-target" {
				return "ADMIN", nil
			}
			return "CASHIER", nil
		},
	}
	svc := NewService(store, nil, nil, nil)
	h := NewHandler(svc)

	// 1. Admin trying to update fellow admin -> 403 Forbidden
	reqUpdateAdmin := httptest.NewRequest(http.MethodPatch, "/api/v1/admin/employees/admin-target", bytes.NewBufferString(`{"display_name":"New Name"}`))
	reqUpdateAdmin.SetPathValue("id", "admin-target")
	reqUpdateAdmin = reqUpdateAdmin.WithContext(customer.WithPrincipal(reqUpdateAdmin.Context(), customer.Principal{
		Subject: "admin-actor",
		Role:    "ADMIN",
	}))
	recUpdateAdmin := httptest.NewRecorder()
	h.UpdateEmployee(recUpdateAdmin, reqUpdateAdmin)
	if recUpdateAdmin.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when admin updates fellow admin, got %d: %s", recUpdateAdmin.Code, recUpdateAdmin.Body.String())
	}

	// 2. Admin updating cashier -> 200 OK
	reqUpdateCashier := httptest.NewRequest(http.MethodPatch, "/api/v1/admin/employees/cashier-target", bytes.NewBufferString(`{"display_name":"New Name"}`))
	reqUpdateCashier.SetPathValue("id", "cashier-target")
	reqUpdateCashier = reqUpdateCashier.WithContext(customer.WithPrincipal(reqUpdateCashier.Context(), customer.Principal{
		Subject: "admin-actor",
		Role:    "ADMIN",
	}))
	recUpdateCashier := httptest.NewRecorder()
	h.UpdateEmployee(recUpdateCashier, reqUpdateCashier)
	if recUpdateCashier.Code != http.StatusOK {
		t.Fatalf("expected 200 when admin updates cashier, got %d: %s", recUpdateCashier.Code, recUpdateCashier.Body.String())
	}

	// 3. Admin trying to delete fellow admin -> 403 Forbidden
	reqDeleteAdmin := httptest.NewRequest(http.MethodDelete, "/api/v1/admin/employees/admin-target", nil)
	reqDeleteAdmin.SetPathValue("id", "admin-target")
	reqDeleteAdmin = reqDeleteAdmin.WithContext(customer.WithPrincipal(reqDeleteAdmin.Context(), customer.Principal{
		Subject: "admin-actor",
		Role:    "ADMIN",
	}))
	recDeleteAdmin := httptest.NewRecorder()
	h.DeleteEmployee(recDeleteAdmin, reqDeleteAdmin)
	if recDeleteAdmin.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when admin deletes fellow admin, got %d", recDeleteAdmin.Code)
	}

	// 4. Admin deleting cashier -> 204 No Content
	reqDeleteCashier := httptest.NewRequest(http.MethodDelete, "/api/v1/admin/employees/cashier-target", nil)
	reqDeleteCashier.SetPathValue("id", "cashier-target")
	reqDeleteCashier = reqDeleteCashier.WithContext(customer.WithPrincipal(reqDeleteCashier.Context(), customer.Principal{
		Subject: "admin-actor",
		Role:    "ADMIN",
	}))
	recDeleteCashier := httptest.NewRecorder()
	h.DeleteEmployee(recDeleteCashier, reqDeleteCashier)
	if recDeleteCashier.Code != http.StatusNoContent {
		t.Fatalf("expected 204 when admin deletes cashier, got %d", recDeleteCashier.Code)
	}

	// 5. Admin trying to create another admin -> 403 Forbidden
	reqCreateAdmin := httptest.NewRequest(http.MethodPost, "/api/v1/admin/employees", bytes.NewBufferString(`{"email":"newadmin@test.com","role":"ADMIN"}`))
	reqCreateAdmin = reqCreateAdmin.WithContext(customer.WithPrincipal(reqCreateAdmin.Context(), customer.Principal{
		Subject: "admin-actor",
		Role:    "ADMIN",
	}))
	recCreateAdmin := httptest.NewRecorder()
	h.CreateEmployee(recCreateAdmin, reqCreateAdmin)
	if recCreateAdmin.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when admin tries to create admin, got %d", recCreateAdmin.Code)
	}

	// 6. Admin trying to update their own account via employee management -> 403 Forbidden
	reqSelf := httptest.NewRequest(http.MethodPatch, "/api/v1/admin/employees/admin-actor", bytes.NewBufferString(`{"display_name":"New Name"}`))
	reqSelf.SetPathValue("id", "admin-actor")
	reqSelf = reqSelf.WithContext(customer.WithPrincipal(reqSelf.Context(), customer.Principal{
		Subject: "admin-actor",
		Role:    "ADMIN",
	}))
	recSelf := httptest.NewRecorder()
	h.UpdateEmployee(recSelf, reqSelf)
	if recSelf.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when admin updates themselves, got %d", recSelf.Code)
	}
}
