package order

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"
	"pesenhub/backend/internal/customer"
)

type Creator interface {
	Create(context.Context, CreateInput, string, string, string) (Order, bool, error)
}

type Service struct{ store Creator }

func NewService(store Creator) *Service { return &Service{store: store} }

func (s *Service) CreateManual(ctx context.Context, in CreateInput, key, actorID, requestID string) (Order, bool, error) {
	in.ClientOrderID = strings.TrimSpace(in.ClientOrderID)
	in.CustomerID = strings.TrimSpace(in.CustomerID)
	in.CustomerName = strings.TrimSpace(in.CustomerName)
	in.CustomerPhone = strings.TrimSpace(in.CustomerPhone)
	in.Notes = strings.TrimSpace(in.Notes)
	if len(key) < 1 || len(key) > 128 {
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
