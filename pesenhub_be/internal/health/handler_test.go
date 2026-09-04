package health

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"pesenhub/backend/internal/gowa"
)

type fakeDB struct{ err error }

func (f fakeDB) Ping(context.Context) error { return f.err }

type fakeGOWA struct{ result gowa.Readiness }

func (f fakeGOWA) Readiness(context.Context) gowa.Readiness { return f.result }
func readyGOWA() fakeGOWA {
	return fakeGOWA{gowa.Readiness{API: gowa.APIUp, Device: gowa.DeviceReady}}
}

func TestLive(t *testing.T) {
	rr := httptest.NewRecorder()
	New("pesenhub-api", fakeDB{}, readyGOWA()).Live(rr, httptest.NewRequest(http.MethodGet, "/health/live", nil))
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), `"status":"live"`) {
		t.Fatalf("response: %d %s", rr.Code, rr.Body.String())
	}
}
func TestReady(t *testing.T) {
	rr := httptest.NewRecorder()
	New("pesenhub-api", fakeDB{}, readyGOWA()).Ready(rr, httptest.NewRequest(http.MethodGet, "/health/ready", nil))
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), `"status":"ready"`) {
		t.Fatalf("response: %d %s", rr.Code, rr.Body.String())
	}
}
func TestReadyDatabaseDown(t *testing.T) {
	rr := httptest.NewRecorder()
	New("pesenhub-api", fakeDB{errors.New("secret database detail")}, readyGOWA()).Ready(rr, httptest.NewRequest(http.MethodGet, "/health/ready", nil))
	if rr.Code != 503 || strings.Contains(rr.Body.String(), "secret") || !strings.Contains(rr.Body.String(), `"database":"down"`) {
		t.Fatalf("response: %d %s", rr.Code, rr.Body.String())
	}
}
func TestReadyDistinguishesGOWASessionFromAPIFailure(t *testing.T) {
	tests := []struct {
		name   string
		result gowa.Readiness
		want   string
	}{
		{"absent session", gowa.Readiness{API: gowa.APIUp, Device: gowa.DeviceAbsent}, `"gowa_device":"absent"`},
		{"disconnected session", gowa.Readiness{API: gowa.APIUp, Device: gowa.DeviceDisconnected}, `"gowa_device":"disconnected"`},
		{"API failure", gowa.Readiness{API: gowa.APIDown, Device: gowa.DeviceUnknown, Reason: "timeout"}, `"gowa_reason":"timeout"`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rr := httptest.NewRecorder()
			New("pesenhub-api", fakeDB{}, fakeGOWA{tt.result}).Ready(rr, httptest.NewRequest(http.MethodGet, "/health/ready", nil))
			if rr.Code != 200 || !strings.Contains(rr.Body.String(), `"status":"degraded"`) || !strings.Contains(rr.Body.String(), tt.want) {
				t.Fatalf("response: %d %s", rr.Code, rr.Body.String())
			}
		})
	}
}
