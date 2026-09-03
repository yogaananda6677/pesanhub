package httpserver

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net/http"
	"regexp"

	"pesenhub/backend/internal/httpapi"
)

type key struct{}

var validRequestID = regexp.MustCompile(`^[A-Za-z0-9._-]{1,128}$`)

func RequestID(ctx context.Context) string {
	id, _ := ctx.Value(key{}).(string)
	return id
}

func Middleware(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-ID")
		if !validRequestID.MatchString(id) {
			var b [12]byte
			_, _ = rand.Read(b[:])
			id = hex.EncodeToString(b[:])
		}
		w.Header().Set("X-Request-ID", id)
		defer func() {
			if recovered := recover(); recovered != nil {
				logger.Error("request panic recovered", "request_id", id)
				httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred.", id, nil)
			}
		}()
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), key{}, id)))
	})
}
