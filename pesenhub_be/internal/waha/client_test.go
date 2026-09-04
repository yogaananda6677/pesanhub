package waha

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestReadinessMappings(t *testing.T) {
	tests := []struct {
		name, body string
		code       int
		api        APIState
		session    SessionState
	}{
		{"working", `{"status":"WORKING"}`, 200, APIUp, SessionReady},
		{"stopped", `{"status":"STOPPED"}`, 200, APIUp, SessionDisconnected},
		{"scan QR", `{"status":"SCAN_QR_CODE"}`, 200, APIUp, SessionDisconnected},
		{"absent", `{}`, 404, APIUp, SessionAbsent},
		{"invalid response", `{}`, 200, APIUp, SessionDegraded},
		{"API failure", `{}`, 500, APIDown, SessionUnknown},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Header.Get("X-Api-Key") != "secret" {
					t.Error("missing API key")
				}
				if r.URL.Path != "/api/sessions/default" {
					t.Errorf("path = %s", r.URL.Path)
				}
				w.WriteHeader(tt.code)
				_, _ = w.Write([]byte(tt.body))
			}))
			defer server.Close()
			got := New(server.URL, "secret", "default", time.Second).Readiness(context.Background())
			if got.API != tt.api || got.Session != tt.session {
				t.Fatalf("readiness = %+v", got)
			}
		})
	}
}

func TestReadinessTimeoutIsBoundedAndSanitized(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { time.Sleep(200 * time.Millisecond) }))
	defer server.Close()
	started := time.Now()
	got := New(server.URL, "do-not-leak", "default", 20*time.Millisecond).Readiness(context.Background())
	if got.API != APIDown || got.Reason != "timeout" {
		t.Fatalf("readiness = %+v", got)
	}
	if time.Since(started) > 150*time.Millisecond {
		t.Fatal("readiness exceeded timeout bound")
	}
}

func TestSendMessage_Success(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Api-Key") != "secret-key" {
			t.Errorf("expected secret-key, got %s", r.Header.Get("X-Api-Key"))
		}
		if r.Header.Get("Content-Type") != "application/json" {
			t.Errorf("expected application/json, got %s", r.Header.Get("Content-Type"))
		}
		if r.URL.Path != "/api/sendText" {
			t.Errorf("expected /api/sendText, got %s", r.URL.Path)
		}

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"id": "wamid.success.123"}`))
	}))
	defer server.Close()

	client := New(server.URL, "secret-key", "default", time.Second)
	msgID, err := client.SendMessage(context.Background(), "+628123456789", "Halo pelanggan")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if msgID != "wamid.success.123" {
		t.Fatalf("expected wamid.success.123, got %s", msgID)
	}
}

func TestSendMessage_NestedSerializedID(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"id": {"_serialized": "true_628123456789@c.us_3EB0ABC"}}`))
	}))
	defer server.Close()

	client := New(server.URL, "secret", "default", time.Second)
	msgID, err := client.SendMessage(context.Background(), "+628123456789", "Test nested")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if msgID != "true_628123456789@c.us_3EB0ABC" {
		t.Fatalf("expected serialized ID, got %s", msgID)
	}
}

func TestSendMessage_ValidationErrors(t *testing.T) {
	client := New("http://localhost:3000", "secret", "default", time.Second)

	// Invalid / non-Indonesian phone
	_, err := client.SendMessage(context.Background(), "+1234567890", "Test")
	if err == nil || !errors.Is(err, ErrValidation) {
		t.Fatalf("expected ErrValidation for invalid phone, got: %v", err)
	}

	// Empty text
	_, err = client.SendMessage(context.Background(), "+628123456789", "   ")
	if err == nil || !errors.Is(err, ErrValidation) {
		t.Fatalf("expected ErrValidation for empty text, got: %v", err)
	}
}

func TestSendMessage_ErrorStatuses(t *testing.T) {
	tests := []struct {
		name        string
		statusCode  int
		expectedErr error
	}{
		{"validation", http.StatusBadRequest, ErrValidation},
		{"unauthorized", http.StatusUnauthorized, ErrAuthentication},
		{"forbidden", http.StatusForbidden, ErrAuthentication},
		{"session absent", http.StatusNotFound, ErrSessionAbsent},
		{"provider failure", http.StatusInternalServerError, ErrProvider},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(tt.statusCode)
			}))
			defer server.Close()

			client := New(server.URL, "secret", "default", time.Second)
			_, err := client.SendMessage(context.Background(), "+628123456789", "Test")
			if err == nil || !errors.Is(err, tt.expectedErr) {
				t.Fatalf("expected error %v, got %v", tt.expectedErr, err)
			}
		})
	}
}

func TestSendMessage_Timeout(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(100 * time.Millisecond)
	}))
	defer server.Close()

	client := New(server.URL, "secret", "default", 15*time.Millisecond)
	_, err := client.SendMessage(context.Background(), "+628123456789", "Test timeout")
	if err == nil || !errors.Is(err, ErrTimeout) {
		t.Fatalf("expected ErrTimeout, got %v", err)
	}
}
