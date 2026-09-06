package appauth

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"
	"pesenhub/backend/internal/customer"
)

func newTestHandler(t *testing.T) *Handler {
	t.Helper()
	hash, err := bcrypt.GenerateFromPassword([]byte("correct horse battery staple"), bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	sessions, err := NewSessionManager("test-session-secret-at-least-32-characters", time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	handler, err := NewHandler("outlet", string(hash), sessions)
	if err != nil {
		t.Fatal(err)
	}
	return handler
}

func TestLoginIssuesUsableSessionWithoutRoleField(t *testing.T) {
	handler := newTestHandler(t)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(`{"username":"outlet","password":"correct horse battery staple"}`))
	res := httptest.NewRecorder()
	handler.Login(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", res.Code, res.Body.String())
	}
	var response LoginResponse
	if err := json.Unmarshal(res.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if response.TokenType != "Bearer" || response.AccessToken == "" || response.ExpiresAt.IsZero() {
		t.Fatalf("invalid login response: %#v", response)
	}
	if strings.Contains(res.Body.String(), "STAFF") || strings.Contains(res.Body.String(), "role") {
		t.Fatal("internal capability leaked to app response")
	}
	if _, ok := handler.sessions.Verify(response.AccessToken); !ok {
		t.Fatal("issued session could not be verified")
	}
}

func TestLoginUsesGenericFailureAndRateLimit(t *testing.T) {
	handler := newTestHandler(t)
	for attempt := 1; attempt <= 6; attempt++ {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(`{"username":"unknown","password":"wrong"}`))
		req.RemoteAddr = "192.0.2.1:4321"
		res := httptest.NewRecorder()
		handler.Login(res, req)
		if attempt <= 5 {
			if res.Code != http.StatusUnauthorized || !strings.Contains(res.Body.String(), "Username or password is incorrect") {
				t.Fatalf("attempt=%d status=%d body=%s", attempt, res.Code, res.Body.String())
			}
		} else if res.Code != http.StatusTooManyRequests || res.Header().Get("Retry-After") != "60" {
			t.Fatalf("rate limit status=%d headers=%v", res.Code, res.Header())
		}
	}
}

func TestLoginRejectsUnknownAndOversizedBodies(t *testing.T) {
	handler := newTestHandler(t)
	for _, body := range []string{
		`{"username":"outlet","password":"x","role":"OWNER"}`,
		`{"username":"outlet","password":"` + strings.Repeat("x", 5000) + `"}`,
	} {
		res := httptest.NewRecorder()
		handler.Login(res, httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(body)))
		if res.Code != http.StatusBadRequest {
			t.Fatalf("status=%d body=%s", res.Code, res.Body.String())
		}
	}
}

func TestIssuedSessionAuthenticatesRESTAndWebSocketHandshake(t *testing.T) {
	login := newTestHandler(t)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/auth/login", login.Login)
	mux.HandleFunc("GET /api/v1/orders/queue", func(w http.ResponseWriter, r *http.Request) {
		if customer.PrincipalFromRequest(r).Role != "STAFF" {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})
	mux.HandleFunc("GET /api/v1/ws/orders", func(w http.ResponseWriter, r *http.Request) {
		if customer.PrincipalFromRequest(r).Role != "STAFF" {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})
	server := httptest.NewServer(customer.Authenticate(
		"staff-service-token-at-least-32-characters",
		"kds-service-token-at-least-32-charactersxx",
		login.sessions,
		mux,
	))
	defer server.Close()

	response, err := http.Post(server.URL+"/api/v1/auth/login", "application/json", strings.NewReader(`{"username":"outlet","password":"correct horse battery staple"}`))
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	var session LoginResponse
	if err := json.NewDecoder(response.Body).Decode(&session); err != nil {
		t.Fatal(err)
	}

	restRequest, _ := http.NewRequest(http.MethodGet, server.URL+"/api/v1/orders/queue", nil)
	restRequest.Header.Set("Authorization", "Bearer "+session.AccessToken)
	restResponse, err := http.DefaultClient.Do(restRequest)
	if err != nil {
		t.Fatal(err)
	}
	restResponse.Body.Close()
	if restResponse.StatusCode != http.StatusNoContent {
		t.Fatalf("REST status=%d", restResponse.StatusCode)
	}

	wsResponse, err := http.Get(server.URL + "/api/v1/ws/orders?token=" + session.AccessToken)
	if err != nil {
		t.Fatal(err)
	}
	wsResponse.Body.Close()
	if wsResponse.StatusCode != http.StatusNoContent {
		t.Fatalf("WebSocket handshake status=%d", wsResponse.StatusCode)
	}
}
