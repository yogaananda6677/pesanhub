package health

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type fakeDB struct{ err error }

func (f fakeDB) Ping(context.Context) error { return f.err }

type fakeWAHA struct{ err error }

func (f fakeWAHA) Check(context.Context) error { return f.err }

func TestLive(t *testing.T) {
	rr := httptest.NewRecorder()
	New("pesenhub-api", fakeDB{}, fakeWAHA{}).Live(rr, httptest.NewRequest(http.MethodGet, "/health/live", nil))
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), `"status":"live"`) {
		t.Fatalf("response: %d %s", rr.Code, rr.Body.String())
	}
}
func TestReady(t *testing.T) {
	rr := httptest.NewRecorder()
	New("pesenhub-api", fakeDB{}, fakeWAHA{}).Ready(rr, httptest.NewRequest(http.MethodGet, "/health/ready", nil))
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), `"status":"ready"`) {
		t.Fatalf("response: %d %s", rr.Code, rr.Body.String())
	}
}
func TestReadyDatabaseDown(t *testing.T) {
	rr := httptest.NewRecorder()
	New("pesenhub-api", fakeDB{errors.New("secret database detail")}, fakeWAHA{}).Ready(rr, httptest.NewRequest(http.MethodGet, "/health/ready", nil))
	if rr.Code != 503 || strings.Contains(rr.Body.String(), "secret") || !strings.Contains(rr.Body.String(), `"database":"down"`) {
		t.Fatalf("response: %d %s", rr.Code, rr.Body.String())
	}
}
func TestReadyWAHADegraded(t *testing.T) {
	rr := httptest.NewRecorder()
	New("pesenhub-api", fakeDB{}, fakeWAHA{errors.New("down")}).Ready(rr, httptest.NewRequest(http.MethodGet, "/health/ready", nil))
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), `"status":"degraded"`) {
		t.Fatalf("response: %d %s", rr.Code, rr.Body.String())
	}
}
