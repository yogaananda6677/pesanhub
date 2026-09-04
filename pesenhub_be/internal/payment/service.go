package payment

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"
	"pesenhub/backend/internal/customer"
)

type CashStore interface {
	RecordCash(context.Context, string, CashInput, string, string, string, string) (Payment, bool, error)
}

type Service struct{ store CashStore }

func NewService(store CashStore) *Service { return &Service{store: store} }

func (s *Service) RecordCash(ctx context.Context, principal customer.Principal, orderID string, in CashInput, key, requestID string) (Payment, bool, error) {
	if principal.Subject == "" || principal.Role != "STAFF" {
		return Payment{}, false, customer.ErrUnauthorized
	}
	orderID = strings.TrimSpace(orderID)
	var id pgtype.UUID
	if id.Scan(orderID) != nil {
		return Payment{}, false, ErrOrderNotFound
	}
	if !validKey(key) {
		return Payment{}, false, &ValidationError{Field: "Idempotency-Key", Reason: "invalid"}
	}
	if in.Amount <= 0 {
		return Payment{}, false, &ValidationError{Field: "amount", Reason: "must_be_positive"}
	}
	payload, _ := json.Marshal(struct {
		OrderID string `json:"order_id"`
		Amount  int64  `json:"amount"`
	}{orderID, in.Amount})
	sum := sha256.Sum256(payload)
	return s.store.RecordCash(ctx, orderID, in, key, hex.EncodeToString(sum[:]), principal.Subject, requestID)
}

func validKey(key string) bool {
	if len(key) < 1 || len(key) > 128 || strings.TrimSpace(key) != key {
		return false
	}
	for _, r := range key {
		if r < 0x21 || r > 0x7e {
			return false
		}
	}
	return true
}
