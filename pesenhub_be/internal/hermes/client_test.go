package hermes

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestAgentClientCallsHermesAPI(t *testing.T) {
	var gotPath, gotAuth, gotSessionID, gotSessionKey string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotAuth = r.Header.Get("Authorization")
		gotSessionID = r.Header.Get("X-Hermes-Session-Id")
		gotSessionKey = r.Header.Get("X-Hermes-Session-Key")
		var request chatCompletionRequest
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		if request.Model != "hermes-agent" || len(request.Messages) != 2 {
			t.Fatalf("unexpected request: %+v", request)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"{\"items\":[],\"confidence\":0.2}"}}]}`))
	}))
	defer server.Close()

	client := NewAgentClient(server.URL+"/v1", "agent-secret", "hermes-agent", time.Second)
	ctx := WithAgentSession(context.Background(), "outlet-1", "+628123456789")
	result, err := client.ExtractOrder(ctx, "system", "user")
	if err != nil {
		t.Fatal(err)
	}
	if gotPath != "/v1/chat/completions" || gotAuth != "Bearer agent-secret" {
		t.Fatalf("path/auth = %q / %q", gotPath, gotAuth)
	}
	if !strings.HasPrefix(gotSessionID, "pesenhub-wa-") || !strings.HasPrefix(gotSessionKey, "agent:pesenhub:whatsapp:") {
		t.Fatalf("missing Hermes session scope: %q / %q", gotSessionID, gotSessionKey)
	}
	if strings.Contains(gotSessionID, "628123456789") || result.Confidence != 0.2 {
		t.Fatalf("phone leaked or result invalid: session=%q result=%+v", gotSessionID, result)
	}
}

func TestAgentClientAddsV1ToRootBaseURL(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("path = %q", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"items\":[],\"confidence\":0}"}}]}`))
	}))
	defer server.Close()

	_, err := NewAgentClient(server.URL, "key", "", time.Second).ExtractOrder(context.Background(), "system", "user")
	if err != nil {
		t.Fatal(err)
	}
}
