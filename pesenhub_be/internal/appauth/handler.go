package appauth

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

type LoginResponse struct {
	AccessToken string    `json:"access_token"`
	TokenType   string    `json:"token_type"`
	ExpiresAt   time.Time `json:"expires_at"`
}

type Handler struct {
	username     string
	passwordHash []byte
	sessions     *SessionManager
	limiter      *loginLimiter
}

func NewHandler(username, passwordHash string, sessions *SessionManager) (*Handler, error) {
	if strings.TrimSpace(username) == "" || sessions == nil {
		return nil, errors.New("invalid login configuration")
	}
	if _, err := bcrypt.Cost([]byte(passwordHash)); err != nil {
		return nil, errors.New("invalid login password hash")
	}
	return &Handler{
		username: username, passwordHash: []byte(passwordHash), sessions: sessions,
		limiter: newLoginLimiter(5, time.Minute),
	}, nil
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	requestID := httpserver.RequestID(r.Context())
	if !h.limiter.Allow(clientIP(r)) {
		w.Header().Set("Retry-After", "60")
		httpapi.WriteError(w, http.StatusTooManyRequests, "RATE_LIMITED", "Too many login attempts. Try again shortly.", requestID, nil)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if decoder.Decode(&body) != nil || decoder.Decode(&struct{}{}) != io.EOF || len(body.Username) > 128 || len(body.Password) > 1024 {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_REQUEST", "Login request is invalid.", requestID, nil)
		return
	}
	providedUsername := sha256.Sum256([]byte(body.Username))
	expectedUsername := sha256.Sum256([]byte(h.username))
	usernameOK := subtle.ConstantTimeCompare(providedUsername[:], expectedUsername[:]) == 1
	passwordOK := bcrypt.CompareHashAndPassword(h.passwordHash, []byte(body.Password)) == nil
	if !usernameOK || !passwordOK {
		httpapi.WriteError(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Username or password is incorrect.", requestID, nil)
		return
	}
	token, expiresAt, err := h.sessions.Issue("outlet-app")
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred.", requestID, nil)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, LoginResponse{AccessToken: token, TokenType: "Bearer", ExpiresAt: expiresAt})
}

type loginWindow struct {
	started time.Time
	count   int
}

type loginLimiter struct {
	mu     sync.Mutex
	items  map[string]loginWindow
	limit  int
	window time.Duration
	now    func() time.Time
}

func newLoginLimiter(limit int, window time.Duration) *loginLimiter {
	return &loginLimiter{items: make(map[string]loginWindow), limit: limit, window: window, now: time.Now}
}

func (l *loginLimiter) Allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	if len(l.items) >= 4096 {
		for candidate, window := range l.items {
			if now.Sub(window.started) >= l.window {
				delete(l.items, candidate)
			}
		}
		if _, known := l.items[key]; !known && len(l.items) >= 4096 {
			return false
		}
	}
	entry := l.items[key]
	if entry.started.IsZero() || now.Sub(entry.started) >= l.window {
		l.items[key] = loginWindow{started: now, count: 1}
		return true
	}
	entry.count++
	l.items[key] = entry
	return entry.count <= l.limit
}

func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil && host != "" {
		return host
	}
	return r.RemoteAddr
}
