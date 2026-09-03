package order

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/domain"
)

type Creator interface {
	Create(context.Context, CreateInput, string, string, string) (Order, bool, error)
}

type Transitioner interface {
	Transition(context.Context, string, TransitionInput, string, string, string, string) (StatusResult, bool, error)
}

type Service struct {
	store       Creator
	transitions Transitioner
}

func NewService(store Creator) *Service {
	s := &Service{store: store}
	s.transitions, _ = store.(Transitioner)
	return s
}

func (s *Service) CreateManual(ctx context.Context, in CreateInput, key, actorID, requestID string) (Order, bool, error) {
	in.ClientOrderID = strings.TrimSpace(in.ClientOrderID)
	in.CustomerID = strings.TrimSpace(in.CustomerID)
	in.CustomerName = strings.TrimSpace(in.CustomerName)
	in.CustomerPhone = strings.TrimSpace(in.CustomerPhone)
	in.Notes = strings.TrimSpace(in.Notes)
	if !validIdempotencyKey(key) {
		return Order{}, false, &ValidationError{Field: "Idempotency-Key"}
	}
	if err := validateUUID(in.ClientOrderID); err != nil {
		return Order{}, false, &ValidationError{Field: "client_order_id"}
	}
	if in.CustomerID != "" {
		if err := validateUUID(in.CustomerID); err != nil {
			return Order{}, false, &ValidationError{Field: "customer_id"}
		}
	}
	if len(in.CustomerName) < 1 || len(in.CustomerName) > 120 {
		return Order{}, false, &ValidationError{Field: "customer_name"}
	}
	if in.CustomerPhone != "" {
		phone, err := customer.NormalizeIndonesia(in.CustomerPhone)
		if err != nil {
			return Order{}, false, &ValidationError{Field: "customer_phone"}
		}
		in.CustomerPhone = phone
	}
	if len(in.Items) < 1 || len(in.Items) > 100 {
		return Order{}, false, &ValidationError{Field: "items"}
	}
	for i := range in.Items {
		in.Items[i].MenuID = strings.TrimSpace(in.Items[i].MenuID)
		in.Items[i].Notes = strings.TrimSpace(in.Items[i].Notes)
		if err := validateUUID(in.Items[i].MenuID); err != nil {
			return Order{}, false, &ValidationError{Field: "items.menu_id"}
		}
		if in.Items[i].Quantity < 1 || in.Items[i].Quantity > 100 {
			return Order{}, false, &ValidationError{Field: "items.quantity"}
		}
	}
	payload, _ := json.Marshal(in)
	sum := sha256.Sum256(payload)
	return s.store.Create(ctx, in, key, hex.EncodeToString(sum[:]), actorID+"|"+requestID)
}

func validateUUID(value string) error { var id pgtype.UUID; return id.Scan(value) }

func (s *Service) Transition(ctx context.Context, orderID string, in TransitionInput, key, actorID, actorRole, requestID string) (StatusResult, bool, error) {
	if s.transitions == nil {
		return StatusResult{}, false, errors.New("transition store unavailable")
	}
	if err := validateUUID(strings.TrimSpace(orderID)); err != nil {
		return StatusResult{}, false, ErrNotFound
	}
	in.TargetStatus = strings.TrimSpace(in.TargetStatus)
	in.ReasonCode = strings.TrimSpace(in.ReasonCode)
	if !validIdempotencyKey(key) {
		return StatusResult{}, false, &ValidationError{Field: "Idempotency-Key"}
	}
	if in.ExpectedVersion < 1 {
		return StatusResult{}, false, &ValidationError{Field: "expected_version"}
	}
	if !domain.OrderStatus(in.TargetStatus).Valid() {
		return StatusResult{}, false, &ValidationError{Field: "target_status"}
	}
	if len(in.ReasonCode) > 64 {
		return StatusResult{}, false, &ValidationError{Field: "reason_code"}
	}
	payload, _ := json.Marshal(in)
	sum := sha256.Sum256(payload)
	return s.transitions.Transition(ctx, orderID, in, key, hex.EncodeToString(sum[:]), actorID, actorRole+"|"+requestID)
}

func ValidTransition(from, to domain.OrderStatus) bool {
	switch from {
	case domain.OrderStatusPending:
		return to == domain.OrderStatusAccepted || to == domain.OrderStatusRejected || to == domain.OrderStatusCancelled
	case domain.OrderStatusAccepted:
		return to == domain.OrderStatusPreparing || to == domain.OrderStatusCancelled
	case domain.OrderStatusPreparing:
		return to == domain.OrderStatusReady
	case domain.OrderStatusReady:
		return to == domain.OrderStatusCompleted
	default:
		return false
	}
}

func validIdempotencyKey(key string) bool {
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
