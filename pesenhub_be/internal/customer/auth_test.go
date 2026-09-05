package customer

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAuthenticateMapsExactBearerAndWebSocketQueryTokens(t *testing.T) {
	const staff = "staff-test-token-at-least-32-characters"
	const kds = "kds-test-token-at-least-32-charactersxx"
	handler := Authenticate(staff, kds, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		principal := PrincipalFromRequest(r)
		w.Header().Set("X-Test-Role", principal.Role)
		w.WriteHeader(http.StatusNoContent)
	}))

	tests := []struct {
		name, authorization, query, role string
	}{
		{"staff bearer", "Bearer " + staff, "", "STAFF"},
		{"case insensitive scheme", "bearer " + kds, "", "KDS"},
		{"websocket query", "", "?token=" + kds, "KDS"},
		{"prefix rejected", "Bearer " + staff[:20], "", ""},
		{"unknown rejected", "Bearer unknown-token-that-is-long-enough-000", "", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/api/v1/ws/orders"+tt.query, nil)
			req.Header.Set("Authorization", tt.authorization)
			res := httptest.NewRecorder()
			handler.ServeHTTP(res, req)
			if got := res.Header().Get("X-Test-Role"); got != tt.role {
				t.Fatalf("role=%q want=%q", got, tt.role)
			}
		})
	}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/orders/queue?token="+staff, nil)
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	if got := res.Header().Get("X-Test-Role"); got != "" {
		t.Fatalf("REST query token must not authenticate, role=%q", got)
	}
}
