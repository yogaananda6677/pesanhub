package health

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"pesenhub/backend/internal/waha"
)

type Database interface{ Ping(context.Context) error }
type Handler struct {
	service string
	db      Database
	waha    waha.Checker
}
type response struct {
	Status  string            `json:"status"`
	Service string            `json:"service"`
	Checks  map[string]string `json:"checks,omitempty"`
}

func New(service string, db Database, wc waha.Checker) *Handler { return &Handler{service, db, wc} }
func (h *Handler) Live(w http.ResponseWriter, _ *http.Request) {
	write(w, http.StatusOK, response{"live", h.service, nil})
}
func (h *Handler) Ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	checks := map[string]string{"database": "up", "waha_api": "up", "waha_session": "ready"}
	status, code := "ready", http.StatusOK
	if h.db == nil || h.db.Ping(ctx) != nil {
		checks["database"], status, code = "down", "not_ready", http.StatusServiceUnavailable
	}
	result := waha.Readiness{API: waha.APIDown, Session: waha.SessionUnknown}
	if h.waha != nil {
		result = h.waha.Readiness(ctx)
	}
	checks["waha_api"] = string(result.API)
	checks["waha_session"] = string(result.Session)
	if result.Reason != "" {
		checks["waha_reason"] = result.Reason
	}
	if result.Session != waha.SessionReady {
		if status == "ready" {
			status = "degraded"
		}
	}
	write(w, code, response{status, h.service, checks})
}
func write(w http.ResponseWriter, code int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(value)
}
