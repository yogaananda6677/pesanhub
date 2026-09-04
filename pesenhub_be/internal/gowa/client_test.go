package gowa

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestReadinessUsesGOWAHealthAndDeviceStatus(t *testing.T) {
	for _, tt := range []struct {
		name       string
		statusCode int
		body       string
		want       DeviceState
	}{
		{"ready", 200, `{"results":{"is_connected":true,"is_logged_in":true}}`, DeviceReady},
		{"disconnected", 200, `{"results":{"is_connected":false,"is_logged_in":true}}`, DeviceDisconnected},
		{"absent", 404, `{}`, DeviceAbsent},
		{"absent uses GOWA error envelope", 500, `{"code":"INTERNAL_SERVER_ERROR","message":"device pesenhub-dev not found"}`, DeviceAbsent},
		{"invalid", 200, `{`, DeviceDegraded},
	} {
		t.Run(tt.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/health" {
					w.WriteHeader(200)
					_, _ = w.Write([]byte("OK"))
					return
				}
				if r.URL.Path != "/devices/pesenhub-dev/status" {
					t.Fatalf("path=%s", r.URL.Path)
				}
				if r.Header.Get("X-Device-Id") != "pesenhub-dev" {
					t.Fatal("missing device header")
				}
				if r.Header.Get("Authorization") != "Basic "+base64.StdEncoding.EncodeToString([]byte("user:pass")) {
					t.Fatal("missing basic auth")
				}
				w.WriteHeader(tt.statusCode)
				_, _ = w.Write([]byte(tt.body))
			}))
			defer server.Close()
			got := New(server.URL, "user", "pass", "pesenhub-dev", time.Second).Readiness(context.Background())
			if got.API != APIUp || got.Device != tt.want {
				t.Fatalf("got=%+v", got)
			}
		})
	}
}

func TestReadinessHealthFailureAndTimeout(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" {
			http.Error(w, "down", 503)
			return
		}
		t.Fatal("device endpoint must not be called")
	}))
	defer server.Close()
	if got := New(server.URL, "u", "p", "d", time.Second).Readiness(context.Background()); got.API != APIDown {
		t.Fatalf("got=%+v", got)
	}
	slow := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { time.Sleep(100 * time.Millisecond) }))
	defer slow.Close()
	if got := New(slow.URL, "u", "p", "d", 10*time.Millisecond).Readiness(context.Background()); got.Reason != "timeout" {
		t.Fatalf("got=%+v", got)
	}
}

func TestSendMessageUsesOfficialGOWAContract(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/send/message" || r.Header.Get("X-Device-Id") != "pesenhub-dev" {
			t.Fatalf("request=%s device=%s", r.URL.Path, r.Header.Get("X-Device-Id"))
		}
		user, pass, ok := r.BasicAuth()
		if !ok || user != "user" || pass != "pass" {
			t.Fatal("invalid basic auth")
		}
		var body map[string]string
		if json.NewDecoder(r.Body).Decode(&body) != nil || body["phone"] != "628123456789@s.whatsapp.net" || body["message"] != "Halo" {
			t.Fatalf("body=%v", body)
		}
		_, _ = w.Write([]byte(`{"code":"SUCCESS","results":{"message_id":"3EB0ABC"}}`))
	}))
	defer server.Close()
	id, err := New(server.URL, "user", "pass", "pesenhub-dev", time.Second).SendMessage(context.Background(), "+628123456789", " Halo ")
	if err != nil || id != "3EB0ABC" {
		t.Fatalf("id=%q err=%v", id, err)
	}
}

func TestSendMessageErrors(t *testing.T) {
	if _, err := New("http://localhost", "u", "p", "d", time.Second).SendMessage(context.Background(), "+1", "x"); !errors.Is(err, ErrValidation) {
		t.Fatalf("err=%v", err)
	}
	for _, tt := range []struct {
		code int
		body string
		want error
	}{{400, "", ErrValidation}, {401, "", ErrAuthentication}, {404, "", ErrDeviceAbsent}, {500, "", ErrProvider},
		{500, `{"message":"device pesenhub-dev not found"}`, ErrDeviceAbsent},
		{500, `{"message":"device is not connected"}`, ErrDeviceNotReady}} {
		s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(tt.code)
			_, _ = w.Write([]byte(tt.body))
		}))
		_, err := New(s.URL, "u", "p", "d", time.Second).SendMessage(context.Background(), "+628123456789", "x")
		s.Close()
		if !errors.Is(err, tt.want) {
			t.Fatalf("code=%d err=%v", tt.code, err)
		}
	}
}
