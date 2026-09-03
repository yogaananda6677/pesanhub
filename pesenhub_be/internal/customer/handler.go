package customer

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

type principalKey struct{}

var errMalformedJSON = errors.New("malformed JSON body")

func WithPrincipal(ctx context.Context, principal Principal) context.Context {
	return context.WithValue(ctx, principalKey{}, principal)
}
func PrincipalFromRequest(r *http.Request) Principal {
	p, _ := r.Context().Value(principalKey{}).(Principal)
	return p
}

type Handler struct{ service *Service }

func NewHandler(service *Service) *Handler { return &Handler{service: service} }

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Phone       string          `json:"phone"`
		DisplayName string          `json:"display_name"`
		Preferences json.RawMessage `json:"preferences"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeCustomerError(w, r, err)
		return
	}
	p, created, err := h.service.Create(r.Context(), CreateInput{Phone: body.Phone, DisplayName: body.DisplayName, Preferences: body.Preferences, IdempotencyKey: r.Header.Get("Idempotency-Key")})
	if err != nil {
		writeCustomerError(w, r, err)
		return
	}
	status := http.StatusOK
	if created {
		status = http.StatusCreated
		w.Header().Set("Location", "/api/v1/customers/"+p.ID)
	}
	httpapi.WriteJSON(w, status, p)
}

func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DisplayName string          `json:"display_name"`
		Preferences json.RawMessage `json:"preferences"`
		Version     int64           `json:"version"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeCustomerError(w, r, err)
		return
	}
	p, err := h.service.Update(r.Context(), PrincipalFromRequest(r), r.PathValue("id"), UpdateInput{DisplayName: body.DisplayName, Preferences: body.Preferences, ExpectedVersion: body.Version})
	if err != nil {
		writeCustomerError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, p)
}

func (h *Handler) History(w http.ResponseWriter, r *http.Request) {
	items, err := h.service.History(r.Context(), PrincipalFromRequest(r), r.PathValue("id"))
	if err != nil {
		writeCustomerError(w, r, err)
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": items})
}

func decodeJSON(r *http.Request, target any) error {
	decoder := json.NewDecoder(io.LimitReader(r.Body, (1<<20)+1))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return errMalformedJSON
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errMalformedJSON
	}
	return nil
}

func writeCustomerError(w http.ResponseWriter, r *http.Request, err error) {
	status, code, message, details := http.StatusInternalServerError, "INTERNAL_ERROR", "An unexpected error occurred.", []httpapi.FieldError(nil)
	switch {
	case errors.Is(err, errMalformedJSON):
		status, code, message = http.StatusBadRequest, "MALFORMED_JSON", "Request body must contain one valid JSON object."
	case errors.Is(err, ErrInvalidProfile):
		status, code, message = http.StatusUnprocessableEntity, "VALIDATION_FAILED", "Customer profile validation failed."
	case errors.Is(err, ErrPhoneCollision):
		status, code, message = http.StatusConflict, "PHONE_PROFILE_CONFLICT", "Phone number requires explicit profile resolution."
	case errors.Is(err, ErrUnauthenticated):
		status, code, message = http.StatusUnauthorized, "UNAUTHENTICATED", "Authentication is required."
	case errors.Is(err, ErrUnauthorized):
		status, code, message = http.StatusForbidden, "FORBIDDEN", "Customer access is not allowed."
	case errors.Is(err, ErrVersionConflict):
		status, code, message = http.StatusConflict, "VERSION_CONFLICT", "Customer profile was modified by another request."
	}
	httpapi.WriteError(w, status, code, message, httpserver.RequestID(r.Context()), details)
}

func ValidIdempotencyKey(value string) bool {
	return len(value) >= 1 && len(value) <= 128 && strings.TrimSpace(value) == value && !strings.ContainsAny(value, "\t\r\n ")
}
