package appauth

import (
	"context"
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
	Session string `json:"sid"`
}

type SessionValidator interface {
	ValidateSession(context.Context, string, string) (role, status string, ok bool)
}

type SessionManager struct {
	secret    []byte
	ttl       time.Duration
	now       func() time.Time
	validator SessionValidator
}

func (m *SessionManager) SetValidator(validator SessionValidator) { m.validator = validator }

func NewSessionManager(secret string, ttl time.Duration) (*SessionManager, error) {
	if len(secret) < 32 || ttl <= 0 || ttl > 24*time.Hour {
		return nil, errors.New("invalid session configuration")
	}
	return &SessionManager{secret: []byte(secret), ttl: ttl, now: time.Now}, nil
}

func (m *SessionManager) Issue(subject, role string) (string, time.Time, error) {
	token, _, expires, err := m.IssuePersistent(subject, role)
	return token, expires, err
}

func (m *SessionManager) IssuePersistent(subject, role string) (string, string, time.Time, error) {
	now := m.now().UTC()
	var random [16]byte
	if _, err := rand.Read(random[:]); err != nil {
		return "", "", time.Time{}, err
	}
	expires := now.Add(m.ttl)
	if role != "STAFF" && role != "OWNER" && role != "SUPERADMIN" {
		return "", "", time.Time{}, errors.New("invalid session role")
	}
	sessionID := base64.RawURLEncoding.EncodeToString(random[:])
	payload, err := json.Marshal(claims{
		Subject: subject,
		Role:    role,
		Issued:  now.Unix(),
		Expires: expires.Unix(),
		Nonce:   sessionID,
		Session: sessionID,
	})
	if err != nil {
		return "", "", time.Time{}, err
	}
	encoded := base64.RawURLEncoding.EncodeToString(payload)
	return encoded + "." + m.signature(encoded), sessionID, expires, nil
}

// Verify implements customer.TokenVerifier and resolves the current database
// role/status so revocation and approval changes apply to every request.
func (m *SessionManager) Verify(ctx context.Context, token string) (customer.Principal, bool) {
	encoded, signature, ok := strings.Cut(token, ".")
	if !ok || encoded == "" || signature == "" || !hmac.Equal([]byte(signature), []byte(m.signature(encoded))) {
		return customer.Principal{}, false
	}
	payload, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		return customer.Principal{}, false
	}
	var value claims
	if json.Unmarshal(payload, &value) != nil || value.Subject == "" || value.Nonce == "" || value.Session == "" ||
		(value.Role != "STAFF" && value.Role != "OWNER" && value.Role != "SUPERADMIN") {
		return customer.Principal{}, false
	}
	now := m.now().UTC().Unix()
	if value.Expires <= now || value.Issued > now+30 || value.Expires-value.Issued > int64(m.ttl/time.Second)+1 {
		return customer.Principal{}, false
	}
	role := value.Role
	if m.validator != nil {
		currentRole, status, valid := m.validator.ValidateSession(ctx, value.Session, value.Subject)
		if !valid {
			return customer.Principal{}, false
		}
		if status != string(StatusApproved) {
			role = status
		} else {
			role = currentRole
		}
	}
	return customer.Principal{Subject: value.Subject, Role: role, SessionID: value.Session}, true
}

func (m *SessionManager) signature(payload string) string {
	mac := hmac.New(sha256.New, m.secret)
	_, _ = mac.Write([]byte(payload))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
