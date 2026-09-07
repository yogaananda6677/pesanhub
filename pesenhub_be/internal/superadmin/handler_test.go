package superadmin

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/gowa"
)

type mockStore struct {
	users           []UserSummary
	invitations     []Invitation
	audits          []AuditEntry
	traffic         TrafficMetrics
	createInvErr    error
	revokeInvErr    error
	updateStatusErr error
	revokeSessErr   error
	listUsersErr    error
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

func (m *mockStore) CreateInvitation(ctx context.Context, actorID, email, outletName string, expiry time.Duration) (Invitation, error) {
	if m.createInvErr != nil {
		return Invitation{}, m.createInvErr
	}
	return Invitation{
		ID:          "inv-123",
		EmailMasked: MaskEmail(email),
		OutletName:  outletName,
		Status:      "PENDING",
		InvitedBy:   actorID,
		CreatedAt:   time.Now().UTC(),
		ExpiresAt:   time.Now().UTC().Add(expiry),
	}, nil
}

func (m *mockStore) RevokeInvitation(ctx context.Context, invitationID string) error {
	return m.revokeInvErr
}

func (m *mockStore) UpdateUserStatus(ctx context.Context, actorID, targetUserID string, targetStatus Status, reason, requestID string) error {
	return m.updateStatusErr
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
