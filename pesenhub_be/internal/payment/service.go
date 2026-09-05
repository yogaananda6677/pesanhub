package payment

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"pesenhub/backend/internal/customer"
)

type CashStore interface {
	RecordCash(context.Context, string, CashInput, string, string, string, string) (Payment, bool, error)
}

type QRISStore interface {
	PrepareQRIS(context.Context, string, string, string, string, string) (Payment, bool, bool, error)
	CompleteQRIS(context.Context, Payment, QRISCharge, string, string) (Payment, error)
	FailQRIS(context.Context, Payment, string, bool, string, string) error
}

type Service struct {
	store     CashStore
	qrisStore QRISStore
	midtrans  MidtransGateway
}

func NewService(store CashStore) *Service { return &Service{store: store} }

func NewServiceWithMidtrans(store interface {
	CashStore
	QRISStore
}, gateway MidtransGateway) *Service {
	return &Service{store: store, qrisStore: store, midtrans: gateway}
}

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

func (s *Service) CreateQRIS(ctx context.Context, principal customer.Principal, orderID, key, requestID string) (Payment, bool, error) {
	if principal.Subject == "" || principal.Role != "STAFF" {
		return Payment{}, false, customer.ErrUnauthorized
	}
	if s.qrisStore == nil || s.midtrans == nil {
		return Payment{}, false, ErrMidtransNotReady
	}
	orderID = strings.TrimSpace(orderID)
	var id pgtype.UUID
	if id.Scan(orderID) != nil {
		return Payment{}, false, ErrOrderNotFound
	}
	if !validKey(key) {
		return Payment{}, false, &ValidationError{Field: "Idempotency-Key", Reason: "invalid"}
	}
	payload, _ := json.Marshal(struct {
		OrderID string `json:"order_id"`
		Method  string `json:"method"`
	}{orderID, "MIDTRANS_QRIS"})
	sum := sha256.Sum256(payload)
	p, execute, created, err := s.qrisStore.PrepareQRIS(ctx, orderID, key, hex.EncodeToString(sum[:]), principal.Subject, requestID)
	if err != nil || !execute {
		return p, created, err
	}
	charge, err := s.midtrans.CreateQRIS(ctx, p.ProviderOrderID, p.Amount)
	if err != nil {
		kind, permanent := "provider_error", false
		var providerErr *ProviderError
		if errors.As(err, &providerErr) {
			kind = safeProviderErrorKind(providerErr.Kind)
			permanent = kind == "rejected" || kind == "configuration"
		}
		persistCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 3*time.Second)
		defer cancel()
		if storeErr := s.qrisStore.FailQRIS(persistCtx, p, kind, permanent, principal.Subject, requestID); storeErr != nil {
			return Payment{}, false, storeErr
		}
		if permanent {
			return Payment{}, false, ErrMidtransRejected
		}
		return Payment{}, false, ErrMidtransUnavailable
	}
	persistCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 3*time.Second)
	defer cancel()
	p, err = s.qrisStore.CompleteQRIS(persistCtx, p, charge, principal.Subject, requestID)
	return p, created, err
}

func safeProviderErrorKind(kind string) string {
	switch kind {
	case "timeout", "network", "server", "rejected", "configuration", "encoding", "invalid_response", "duplicate", "rate_limited":
		return kind
	default:
		return "provider_error"
	}
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
