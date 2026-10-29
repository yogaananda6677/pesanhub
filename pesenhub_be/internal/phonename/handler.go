package phonename

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

type Handler struct {
	store *Store
}

func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	list, err := h.store.List(r.Context())
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	if list == nil {
		list = []PhoneName{}
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"data": list})
}

func (h *Handler) Set(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	var in SetPhoneNameInput
	if err := decodeJSON(r, &in); err != nil {
		h.writeError(w, r, errors.New("invalid request body"))
		return
	}

	item, err := h.store.Set(r.Context(), in)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, item)
}

func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	principal := customer.PrincipalFromRequest(r)
	if !customer.CanOperateOutlet(principal) {
		h.writeError(w, r, customer.ErrUnauthorized)
		return
	}

	phone := r.PathValue("phone")
	if strings.TrimSpace(phone) == "" {
		h.writeError(w, r, errors.New("phone parameter required"))
		return
	}

	if err := h.store.Delete(r.Context(), phone); err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"status": "deleted"})
}

func (h *Handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	status := http.StatusInternalServerError
	code := "INTERNAL_ERROR"
	if errors.Is(err, customer.ErrUnauthorized) {
		status = http.StatusForbidden
		code = "FORBIDDEN"
	}
	httpapi.WriteError(w, status, code, err.Error(), httpserver.RequestID(r.Context()), nil)
}

func decodeJSON(r *http.Request, dst any) error {
	defer r.Body.Close()
	dec := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	dec.DisallowUnknownFields()
	return dec.Decode(dst)
}
