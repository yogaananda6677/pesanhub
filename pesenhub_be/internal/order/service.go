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
	"pesenhub/backend/internal/httpapi"
)

type Creator interface {
	Create(context.Context, CreateInput, string, string, string) (Order, bool, error)
}

type Transitioner interface {
	Transition(context.Context, string, TransitionInput, string, string, string, string) (StatusResult, bool, error)
}

type Reader interface {
	List(context.Context, OrderFilter) ([]OrderDetail, string, error)
	GetByID(context.Context, string) (OrderDetail, error)
}

type Service struct {
	store       Creator
	transitions Transitioner
	reader      Reader
}

func NewService(store Creator) *Service {
	s := &Service{store: store}
	s.transitions, _ = store.(Transitioner)
	s.reader, _ = store.(Reader)
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

func (s *Service) List(ctx context.Context, p customer.Principal, filter OrderFilter) (OrderCollection, error) {
	if s.reader == nil {
		return OrderCollection{}, errors.New("order reader unavailable")
	}
	if p.Subject == "" || (p.Role != "STAFF" && p.Role != "KDS") {
		return OrderCollection{}, customer.ErrUnauthorized
	}
	for i, st := range filter.Statuses {
		filter.Statuses[i] = strings.TrimSpace(st)
		if !domain.OrderStatus(filter.Statuses[i]).Valid() {
			return OrderCollection{}, &ValidationError{Field: "status"}
		}
	}
	for i, src := range filter.Sources {
		filter.Sources[i] = strings.TrimSpace(src)
		switch filter.Sources[i] {
		case "WHATSAPP", "CASHIER_MANUAL", "CUSTOMER_WEB":
		default:
			return OrderCollection{}, &ValidationError{Field: "source"}
		}
	}
	if filter.CreatedFrom != nil && filter.CreatedTo != nil && filter.CreatedFrom.After(*filter.CreatedTo) {
		return OrderCollection{}, &ValidationError{Field: "created_from"}
	}
	orders, nextCursor, err := s.reader.List(ctx, filter)
	if err != nil {
		return OrderCollection{}, err
	}
	if orders == nil {
		orders = []OrderDetail{}
	}
	for i := range orders {
		orders[i].RedactForRole(p.Role)
	}
	var next *string
	if nextCursor != "" {
		next = &nextCursor
	}
	return OrderCollection{
		Data: orders,
		Page: httpapi.PageMeta{
			Size:       len(orders),
			NextCursor: next,
		},
	}, nil
}

func (s *Service) GetByID(ctx context.Context, p customer.Principal, id string) (OrderDetail, error) {
	if s.reader == nil {
		return OrderDetail{}, errors.New("order reader unavailable")
	}
	if p.Subject == "" || (p.Role != "STAFF" && p.Role != "KDS") {
		return OrderDetail{}, customer.ErrUnauthorized
	}
	id = strings.TrimSpace(id)
	if err := validateUUID(id); err != nil {
		return OrderDetail{}, ErrNotFound
	}
	order, err := s.reader.GetByID(ctx, id)
	if err != nil {
		return OrderDetail{}, err
	}
	order.RedactForRole(p.Role)
	return order, nil
}

func (s *Service) QueueSnapshot(ctx context.Context, p customer.Principal) ([]OrderDetail, error) {
	if s.reader == nil {
		return nil, errors.New("order reader unavailable")
	}
	if p.Subject == "" || (p.Role != "STAFF" && p.Role != "KDS") {
		return nil, customer.ErrUnauthorized
	}
	filter := OrderFilter{
		Statuses: []string{"ACCEPTED", "PREPARING", "READY_FOR_PICKUP"},
		Pagination: httpapi.Pagination{
			Size:  httpapi.MaxPageSize,
			Order: "asc",
		},
	}
	orders, _, err := s.reader.List(ctx, filter)
	if err != nil {
		return nil, err
	}
	if orders == nil {
		orders = []OrderDetail{}
	}
	for i := range orders {
		orders[i].RedactForRole(p.Role)
	}
	return orders, nil
}
