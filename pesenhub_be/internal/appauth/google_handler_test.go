package appauth

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/customer"
)

type fakeGoogleVerifier struct {
	identity GoogleIdentity
	nonce    string
	calls    int
}

func (v *fakeGoogleVerifier) Verify(_ context.Context, token, nonce string) (GoogleIdentity, error) {
	v.calls++
	if token != "valid-google-token" || nonce != v.nonce {
		return GoogleIdentity{}, context.Canceled
	}
	return v.identity, nil
}

type fakeIdentityStore struct {
	user       User
	sessions   map[string]string
	revoked    map[string]bool
	upsertCall int
}

func (s *fakeIdentityStore) UpsertGoogleIdentity(_ context.Context, identity GoogleIdentity) (User, error) {
	s.upsertCall++
	return s.user, nil
}
func (s *fakeIdentityStore) UserByID(_ context.Context, id string) (User, error) { return s.user, nil }
func (s *fakeIdentityStore) UserByEmail(_ context.Context, email string) (User, error) {
	return s.user, nil
}
func (s *fakeIdentityStore) UpdateDisplayName(_ context.Context, id, displayName string) error {
	s.user.DisplayName = displayName
	return nil
}
func (s *fakeIdentityStore) EnsureUser(_ context.Context, email, displayName, role string) (User, error) {
	return User{
		ID:          s.user.ID,
		EmailMasked: email,
		DisplayName: displayName,
		Role:        Role(role),
		Status:      StatusApproved,
	}, nil
}
func (s *fakeIdentityStore) CreateSession(_ context.Context, id, userID string, _ time.Time) error {
	s.sessions[id] = userID
	return nil
}
func (s *fakeIdentityStore) RevokeSession(_ context.Context, id, userID string) error {
	if s.sessions[id] == userID {
		s.revoked[id] = true
	}
	return nil
}
func (s *fakeIdentityStore) ValidateSession(_ context.Context, id, userID string) (string, string, string, bool) {
	var bID string
	if s.user.BranchID != nil {
		bID = *s.user.BranchID
	}
	return string(s.user.Role), string(s.user.Status), bID, s.sessions[id] == userID && !s.revoked[id]
}

func TestGoogleLoginCreatesPendingSessionAndConsumesNonce(t *testing.T) {
	user := User{ID: "a1000000-0000-4000-8000-000000000001", EmailMasked: "ow***@example.test", DisplayName: "Owner", Role: RoleOwner, Status: StatusPending}
	store := &fakeIdentityStore{user: user, sessions: map[string]string{}, revoked: map[string]bool{}}
	sessions, err := NewSessionManager("test-session-secret-at-least-32-characters", time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	sessions.SetValidator(store)
	verifier := &fakeGoogleVerifier{identity: GoogleIdentity{Subject: "google-subject", Email: "owner@example.test", DisplayName: "Owner", EmailVerified: true}}
	handler, err := NewGoogleHandler(verifier, store, sessions)
	if err != nil {
		t.Fatal(err)
	}

	challengeResponse := httptest.NewRecorder()
	handler.Challenge(challengeResponse, httptest.NewRequest(http.MethodPost, "/api/v1/auth/google/challenge", nil))
	if challengeResponse.Code != http.StatusCreated || challengeResponse.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("challenge status=%d headers=%v", challengeResponse.Code, challengeResponse.Header())
	}
	var challenge map[string]any
	if err := json.Unmarshal(challengeResponse.Body.Bytes(), &challenge); err != nil {
		t.Fatal(err)
	}
	verifier.nonce, _ = challenge["nonce"].(string)

	body := `{"id_token":"valid-google-token","nonce":"` + verifier.nonce + `"}`
	loginResponse := httptest.NewRecorder()
	handler.Login(loginResponse, httptest.NewRequest(http.MethodPost, "/api/v1/auth/google", strings.NewReader(body)))
	if loginResponse.Code != http.StatusOK {
		t.Fatalf("login status=%d body=%s", loginResponse.Code, loginResponse.Body.String())
	}
	var session SessionResponse
	if err := json.Unmarshal(loginResponse.Body.Bytes(), &session); err != nil {
		t.Fatal(err)
	}
	principal, ok := sessions.Verify(context.Background(), session.AccessToken)
	if !ok || principal.Role != string(StatusPending) || customer.CanOperateOutlet(principal) {
		t.Fatalf("pending session unlocked outlet: principal=%#v ok=%v", principal, ok)
	}
	if store.upsertCall != 1 || verifier.calls != 1 {
		t.Fatalf("calls upsert=%d verifier=%d", store.upsertCall, verifier.calls)
	}

	replay := httptest.NewRecorder()
	handler.Login(replay, httptest.NewRequest(http.MethodPost, "/api/v1/auth/google", strings.NewReader(body)))
	if replay.Code != http.StatusBadRequest || verifier.calls != 1 {
		t.Fatalf("replayed nonce status=%d verifier calls=%d", replay.Code, verifier.calls)
	}
}

func TestApprovedSessionLogoutRevokesImmediately(t *testing.T) {
	user := User{ID: "a1000000-0000-4000-8000-000000000001", EmailMasked: "ow***@example.test", DisplayName: "Owner", Role: RoleOwner, Status: StatusApproved}
	store := &fakeIdentityStore{user: user, sessions: map[string]string{}, revoked: map[string]bool{}}
	sessions, _ := NewSessionManager("test-session-secret-at-least-32-characters", time.Hour)
	sessions.SetValidator(store)
	token, sid, expires, err := sessions.IssuePersistent(user.ID, string(user.Role))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.CreateSession(context.Background(), sid, user.ID, expires); err != nil {
		t.Fatal(err)
	}
	handler, _ := NewGoogleHandler(&fakeGoogleVerifier{}, store, sessions)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/auth/logout", handler.Logout)
	wrapped := customer.Authenticate("staff-service-token-at-least-32-characters", "kds-service-token-at-least-32-charactersxx", sessions, mux)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/logout", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	wrapped.ServeHTTP(response, req)
	if response.Code != http.StatusNoContent {
		t.Fatalf("logout status=%d body=%s", response.Code, response.Body.String())
	}
	if _, ok := sessions.Verify(context.Background(), token); ok {
		t.Fatal("revoked session remained valid")
	}
}

func TestChallengeIsSingleUseAndBounded(t *testing.T) {
	store := newChallengeStore(time.Minute)
	nonce, err := store.Issue()
	if err != nil || len(nonce) < 32 {
		t.Fatalf("nonce=%q err=%v", nonce, err)
	}
	if !store.Consume(nonce) || store.Consume(nonce) {
		t.Fatal("challenge was not exactly single use")
	}
}

func TestPasswordLoginCashierAndAdmin(t *testing.T) {
	user := User{ID: "a1000000-0000-4000-8000-000000000001", EmailMasked: "ka***@example.test", DisplayName: "Kasir Jenggirat", Role: RoleCashier, Status: StatusApproved}
	store := &fakeIdentityStore{user: user, sessions: map[string]string{}, revoked: map[string]bool{}}
	sessions, _ := NewSessionManager("test-session-secret-at-least-32-characters", time.Hour)
	sessions.SetValidator(store)
	handler, _ := NewGoogleHandler(&fakeGoogleVerifier{}, store, sessions)
	handler.SetPasswordAuth(PasswordAuthConfig{
		AdminUsername:   "admin",
		AdminPassword:   "admin123",
		CashierUsername: "kasir",
		CashierPassword: "kasir123",
	})

	// 1. Success Cashier Login
	cashierBody := `{"username":"kasir","password":"kasir123"}`
	resp := httptest.NewRecorder()
	handler.LoginPassword(resp, httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(cashierBody)))
	if resp.Code != http.StatusOK {
		t.Fatalf("cashier login failed status=%d body=%s", resp.Code, resp.Body.String())
	}
	var sess SessionResponse
	if err := json.Unmarshal(resp.Body.Bytes(), &sess); err != nil {
		t.Fatal(err)
	}
	if sess.AccessToken == "" || sess.User.Role != RoleCashier {
		t.Fatalf("unexpected cashier session: %#v", sess)
	}

	// 2. Success Admin Login
	adminBody := `{"username":"admin","password":"admin123"}`
	respAdmin := httptest.NewRecorder()
	handler.LoginPassword(respAdmin, httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(adminBody)))
	if respAdmin.Code != http.StatusOK {
		t.Fatalf("admin login failed status=%d body=%s", respAdmin.Code, respAdmin.Body.String())
	}
	var adminSess SessionResponse
	if err := json.Unmarshal(respAdmin.Body.Bytes(), &adminSess); err != nil {
		t.Fatal(err)
	}
	if adminSess.AccessToken == "" || adminSess.User.Role != RoleAdmin {
		t.Fatalf("unexpected admin session: %#v", adminSess)
	}

	// 3. Failed Login (Wrong Password)
	wrongBody := `{"username":"kasir","password":"wrongpassword"}`
	respWrong := httptest.NewRecorder()
	handler.LoginPassword(respWrong, httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(wrongBody)))
	if respWrong.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for wrong password, got %d", respWrong.Code)
	}

	// 4. Failed Login (Empty credentials)
	emptyBody := `{"username":"","password":""}`
	respEmpty := httptest.NewRecorder()
	handler.LoginPassword(respEmpty, httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(emptyBody)))
	if respEmpty.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for empty credentials, got %d", respEmpty.Code)
	}
}
