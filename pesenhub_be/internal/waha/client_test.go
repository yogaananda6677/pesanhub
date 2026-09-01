package waha

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestCheck(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Api-Key") != "secret" {
			t.Error("missing API key")
		}
		if r.URL.Path != "/api/sessions/default" {
			t.Errorf("path = %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()
	if err := New(server.URL, "secret", "default", time.Second).Check(context.Background()); err != nil {
		t.Fatal(err)
	}
}

func TestCheckSanitizesError(t *testing.T) {
	c := New("http://127.0.0.1:1", "do-not-leak", "default", 20*time.Millisecond)
	err := c.Check(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	if contains(err.Error(), "do-not-leak") {
		t.Fatal("API key leaked")
	}
}
func contains(s, part string) bool {
	for i := 0; i+len(part) <= len(s); i++ {
		if s[i:i+len(part)] == part {
			return true
		}
	}
	return false
}
