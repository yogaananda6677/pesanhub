package health

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"pesenhub/backend/internal/waha"
)

type fakeDB struct{ err error }

func (f fakeDB) Ping(context.Context) error { return f.err }

type fakeWAHA struct{ result waha.Readiness }

func (f fakeWAHA) Readiness(context.Context) waha.Readiness { return f.result }
func readyWAHA() fakeWAHA {
	return fakeWAHA{waha.Readiness{API: waha.APIUp, Session: waha.SessionReady}}
}

func TestLive(t *testing.T) {
	rr := httptest.NewRecorder()
	New("pesenhub-api", fakeDB{}, readyWAHA()).Live(rr, httptest.NewRequest(http.MethodGet, "/health/live", nil))
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), `"status":"live"`) {
		t.Fatalf("response: %d %s", rr.Code, rr.Body.String())
	}
}
func TestReady(t *testing.T) {
	rr := httptest.NewRecorder()
	New("pesenhub-api", fakeDB{}, readyWAHA()).Ready(rr, httptest.NewRequest(http.MethodGet, "/health/ready", nil))
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), `"status":"ready"`) {
		t.Fatalf("response: %d %s", rr.Code, rr.Body.String())
	}
}
func TestReadyDatabaseDown(t *testing.T) {
	rr := httptest.NewRecorder()
	New("pesenhub-api", fakeDB{errors.New("secret database detail")}, readyWAHA()).Ready(rr, httptest.NewRequest(http.MethodGet, "/health/ready", nil))
	if rr.Code != 503 || strings.Contains(rr.Body.String(), "secret") || !strings.Contains(rr.Body.String(), `"database":"down"`) {
		t.Fatalf("response: %d %s", rr.Code, rr.Body.String())
	}
}
func TestReadyDistinguishesWAHASessionFromAPIFailure(t *testing.T) {
	tests := []struct {
		name   string
		result waha.Readiness
		want   string
	}{
		{"absent session", waha.Readiness{API: waha.APIUp, Session: waha.SessionAbsent}, `"waha_session":"absent"`},
		{"disconnected session", waha.Readiness{API: waha.APIUp, Session: waha.SessionDisconnected}, `"waha_session":"disconnected"`},
		{"API failure", waha.Readiness{API: waha.APIDown, Session: waha.SessionUnknown, Reason: "timeout"}, `"waha_reason":"timeout"`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rr := httptest.NewRecorder()
			New("pesenhub-api", fakeDB{}, fakeWAHA{tt.result}).Ready(rr, httptest.NewRequest(http.MethodGet, "/health/ready", nil))
			if rr.Code != 200 || !strings.Contains(rr.Body.String(), `"status":"degraded"`) || !strings.Contains(rr.Body.String(), tt.want) {
				t.Fatalf("response: %d %s", rr.Code, rr.Body.String())
			}
		})
	}
}
