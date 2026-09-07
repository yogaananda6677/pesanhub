package appauth

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

type GoogleIdentityVerifier interface {
	Verify(context.Context, string, string) (GoogleIdentity, error)
}

type GoogleHandler struct {
	verifier   GoogleIdentityVerifier
	store      IdentityStore
	sessions   *SessionManager
	challenges *challengeStore
}

func NewGoogleHandler(verifier GoogleIdentityVerifier, store IdentityStore, sessions *SessionManager) (*GoogleHandler, error) {
	if verifier == nil || store == nil || sessions == nil {
		return nil, errors.New("invalid Google authentication configuration")
	}
	return &GoogleHandler{verifier: verifier, store: store, sessions: sessions, challenges: newChallengeStore(5 * time.Minute)}, nil
}

func (h *GoogleHandler) Challenge(w http.ResponseWriter, r *http.Request) {
	nonce, err := h.challenges.Issue()
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred.", httpserver.RequestID(r.Context()), nil)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	httpapi.WriteJSON(w, http.StatusCreated, map[string]any{"nonce": nonce, "expires_in": 300})
}

func (h *GoogleHandler) Login(w http.ResponseWriter, r *http.Request) {
	requestID := httpserver.RequestID(r.Context())
	r.Body = http.MaxBytesReader(w, r.Body, 16<<10)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var body struct {
		IDToken string `json:"id_token"`
		Nonce   string `json:"nonce"`
	}
	if decoder.Decode(&body) != nil || decoder.Decode(&struct{}{}) != io.EOF || !h.challenges.Consume(body.Nonce) {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_AUTH_REQUEST", "Google login request is invalid or expired.", requestID, nil)
		return
	}
	identity, err := h.verifier.Verify(r.Context(), body.IDToken, body.Nonce)
	if err != nil || !identity.EmailVerified {
		httpapi.WriteError(w, http.StatusUnauthorized, "GOOGLE_AUTH_FAILED", "Google authentication could not be verified.", requestID, nil)
		return
	}
	user, err := h.store.UpsertGoogleIdentity(r.Context(), identity)
	if err != nil {
		status := http.StatusInternalServerError
		code, message := "INTERNAL_ERROR", "An unexpected error occurred."
		if errors.Is(err, ErrIdentityConflict) {
			status, code, message = http.StatusConflict, "IDENTITY_CONFLICT", "This Google identity cannot be linked automatically."
		}
		httpapi.WriteError(w, status, code, message, requestID, nil)
		return
	}
	token, sessionID, expiresAt, err := h.sessions.IssuePersistent(user.ID, string(user.Role))
	if err == nil {
		err = h.store.CreateSession(r.Context(), sessionID, user.ID, expiresAt)
	}
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred.", requestID, nil)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	httpapi.WriteJSON(w, http.StatusOK, SessionResponse{AccessToken: token, TokenType: "Bearer", ExpiresAt: expiresAt, User: user})
}

func (h *GoogleHandler) Me(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if principal.Subject == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHENTICATED", "Authentication is required.", httpserver.RequestID(r.Context()), nil)
		return
	}
	user, err := h.store.UserByID(r.Context(), principal.Subject)
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, pgx.ErrNoRows) {
			status = http.StatusUnauthorized
		}
		httpapi.WriteError(w, status, "UNAUTHENTICATED", "Authentication is required.", httpserver.RequestID(r.Context()), nil)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	httpapi.WriteJSON(w, http.StatusOK, user)
}

func (h *GoogleHandler) Logout(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if principal.Subject == "" || principal.SessionID == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHENTICATED", "Authentication is required.", httpserver.RequestID(r.Context()), nil)
		return
	}
	if err := h.store.RevokeSession(r.Context(), principal.SessionID, principal.Subject); err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred.", httpserver.RequestID(r.Context()), nil)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type challengeStore struct {
	mu      sync.Mutex
	ttl     time.Duration
	now     func() time.Time
	entries map[string]time.Time
}

func newChallengeStore(ttl time.Duration) *challengeStore {
	return &challengeStore{ttl: ttl, now: time.Now, entries: make(map[string]time.Time)}
}

func (s *challengeStore) Issue() (string, error) {
	var random [32]byte
	if _, err := rand.Read(random[:]); err != nil {
		return "", err
	}
	nonce := base64.RawURLEncoding.EncodeToString(random[:])
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cleanupLocked()
	if len(s.entries) >= 4096 {
		return "", errors.New("too many active authentication challenges")
	}
	s.entries[nonce] = s.now().Add(s.ttl)
	return nonce, nil
}

func (s *challengeStore) Consume(nonce string) bool {
	if len(strings.TrimSpace(nonce)) < 32 {
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	expires, ok := s.entries[nonce]
	delete(s.entries, nonce)
	return ok && s.now().Before(expires)
}

func (s *challengeStore) cleanupLocked() {
	now := s.now()
	for nonce, expires := range s.entries {
		if !now.Before(expires) {
			delete(s.entries, nonce)
		}
	}
}
