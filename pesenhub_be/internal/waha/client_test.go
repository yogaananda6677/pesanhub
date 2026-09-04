package waha

import (
	"context"
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
