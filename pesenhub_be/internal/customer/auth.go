package customer

import (
	"crypto/subtle"
	"net/http"
	"strings"
)

func Authenticate(staffToken, kdsToken string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := bearerToken(r.Header.Get("Authorization"))
		if token == "" && r.URL.Path == "/api/v1/ws/orders" && r.URL.Query().Has("token") {
			token = r.URL.Query().Get("token")
		}
		principal := Principal{}
		switch {
		case constantTimeTokenEqual(token, staffToken):
			principal = Principal{Subject: "staff-api", Role: "STAFF"}
		case constantTimeTokenEqual(token, kdsToken):
			principal = Principal{Subject: "kds-api", Role: "KDS"}
		}
		if principal.Subject != "" {
			r = r.WithContext(WithPrincipal(r.Context(), principal))
		}
		next.ServeHTTP(w, r)
	})
}

func bearerToken(value string) string {
	scheme, token, ok := strings.Cut(value, " ")
	if !ok || !strings.EqualFold(scheme, "Bearer") || token == "" || strings.ContainsAny(token, " \t\r\n") {
		return ""
	}
	return token
}

func constantTimeTokenEqual(provided, expected string) bool {
	if provided == "" || expected == "" || len(provided) != len(expected) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(provided), []byte(expected)) == 1
}
