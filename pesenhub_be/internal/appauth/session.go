package appauth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"pesenhub/backend/internal/customer"
)

type claims struct {
	Subject string `json:"sub"`
	Role    string `json:"role"`
	Issued  int64  `json:"iat"`
	Expires int64  `json:"exp"`
	Nonce   string `json:"nonce"`
}

type SessionManager struct {
	secret []byte
	ttl    time.Duration
	now    func() time.Time
}

func NewSessionManager(secret string, ttl time.Duration) (*SessionManager, error) {
	if len(secret) < 32 || ttl <= 0 || ttl > 24*time.Hour {
		return nil, errors.New("invalid session configuration")
	}
	return &SessionManager{secret: []byte(secret), ttl: ttl, now: time.Now}, nil
}

func (m *SessionManager) Issue(subject string) (string, time.Time, error) {
	now := m.now().UTC()
	var random [16]byte
	if _, err := rand.Read(random[:]); err != nil {
		return "", time.Time{}, err
	}
	expires := now.Add(m.ttl)
	payload, err := json.Marshal(claims{
		Subject: subject,
		Role:    "STAFF",
		Issued:  now.Unix(),
		Expires: expires.Unix(),
		Nonce:   base64.RawURLEncoding.EncodeToString(random[:]),
	})
	if err != nil {
		return "", time.Time{}, err
	}
	encoded := base64.RawURLEncoding.EncodeToString(payload)
	return encoded + "." + m.signature(encoded), expires, nil
}

// Verify implements customer.TokenVerifier. STAFF is an internal capability;
// the single-outlet app never exposes it as a selectable persona.
func (m *SessionManager) Verify(token string) (customer.Principal, bool) {
	encoded, signature, ok := strings.Cut(token, ".")
	if !ok || encoded == "" || signature == "" || !hmac.Equal([]byte(signature), []byte(m.signature(encoded))) {
		return customer.Principal{}, false
	}
	payload, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		return customer.Principal{}, false
	}
	var value claims
	if json.Unmarshal(payload, &value) != nil || value.Subject == "" || value.Role != "STAFF" || value.Nonce == "" {
		return customer.Principal{}, false
	}
	now := m.now().UTC().Unix()
	if value.Expires <= now || value.Issued > now+30 || value.Expires-value.Issued > int64(m.ttl/time.Second)+1 {
		return customer.Principal{}, false
	}
	return customer.Principal{Subject: value.Subject, Role: value.Role}, true
}

func (m *SessionManager) signature(payload string) string {
	mac := hmac.New(sha256.New, m.secret)
	_, _ = mac.Write([]byte(payload))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
