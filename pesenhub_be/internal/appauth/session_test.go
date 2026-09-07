package appauth

import (
	"context"
	"strings"
	"testing"
	"time"
)

func TestSessionIssueVerifyTamperAndExpiry(t *testing.T) {
	manager, err := NewSessionManager("test-session-secret-at-least-32-characters", 8*time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 9, 6, 8, 0, 0, 0, time.UTC)
	manager.now = func() time.Time { return now }
	token, expiresAt, err := manager.Issue("outlet-app", "STAFF")
	if err != nil {
		t.Fatal(err)
	}
	principal, ok := manager.Verify(context.Background(), token)
	if !ok || principal.Subject != "outlet-app" || principal.Role != "STAFF" {
		t.Fatalf("unexpected principal: %#v, ok=%v", principal, ok)
	}
	if !expiresAt.Equal(now.Add(8 * time.Hour)) {
		t.Fatalf("expires_at=%v", expiresAt)
	}
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		t.Fatal("token format is invalid")
	}
	if _, ok := manager.Verify(context.Background(), parts[0]+".tampered"); ok {
		t.Fatal("tampered signature accepted")
	}
	manager.now = func() time.Time { return expiresAt }
	if _, ok := manager.Verify(context.Background(), token); ok {
		t.Fatal("expired token accepted")
	}
}

func TestSessionConfigurationIsBounded(t *testing.T) {
	if _, err := NewSessionManager("short", time.Hour); err == nil {
		t.Fatal("weak secret accepted")
	}
	if _, err := NewSessionManager("test-session-secret-at-least-32-characters", 25*time.Hour); err == nil {
		t.Fatal("excessive TTL accepted")
	}
}
