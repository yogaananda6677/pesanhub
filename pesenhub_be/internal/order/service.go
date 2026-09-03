package order

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
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

type WebOrderStore interface {
	CreateWeb(context.Context, PublicOrderCreateInput, string, string, string) (PublicOrderResponse, bool, error)
	PreviewWeb(context.Context, []ItemInput) (PreviewResponse, error)
	GetByPublicToken(context.Context, string) (PublicTrackingDetail, error)
}

type Service struct {
	store       Creator
	transitions Transitioner
	reader      Reader
	webStore    WebOrderStore
}

func NewService(store Creator) *Service {
	s := &Service{store: store}
	s.transitions, _ = store.(Transitioner)
	s.reader, _ = store.(Reader)
	s.webStore, _ = store.(WebOrderStore)
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

func NormalizePhone(raw string) (string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", &ValidationError{Field: "customer_phone", Reason: "Nomor handphone wajib diisi"}
	}
	if strings.HasPrefix(raw, "08") {
		raw = "+628" + raw[2:]
	} else if strings.HasPrefix(raw, "628") {
		raw = "+" + raw
	} else if !strings.HasPrefix(raw, "+628") {
		return "", &ValidationError{Field: "customer_phone", Reason: "Nomor handphone harus diawali +628 atau 08"}
	}

	digits := raw[1:] // after '+'
	if len(digits) < 10 || len(digits) > 15 {
		return "", &ValidationError{Field: "customer_phone", Reason: "Panjang nomor handphone harus antara 10 sampai 15 digit"}
	}
	for _, c := range digits {
		if c < '0' || c > '9' {
			return "", &ValidationError{Field: "customer_phone", Reason: "Nomor handphone hanya boleh berisi angka"}
		}
	}
	return raw, nil
}

func ValidateCustomerName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", &ValidationError{Field: "customer_name", Reason: "Nama pelanggan wajib diisi"}
	}
	if len(name) > 120 {
		return "", &ValidationError{Field: "customer_name", Reason: "Nama pelanggan maksimal 120 karakter"}
	}
	return name, nil
}

func (s *Service) CreateWeb(ctx context.Context, in PublicOrderCreateInput, idempotencyKey, requestID string) (PublicOrderResponse, bool, error) {
	if s.webStore == nil {
		return PublicOrderResponse{}, false, errors.New("web store not configured")
	}

	normPhone, err := NormalizePhone(in.CustomerPhone)
	if err != nil {
		return PublicOrderResponse{}, false, err
	}
	in.CustomerPhone = normPhone

	normName, err := ValidateCustomerName(in.CustomerName)
	if err != nil {
		return PublicOrderResponse{}, false, err
	}
	in.CustomerName = normName

	if len(in.Items) == 0 {
		return PublicOrderResponse{}, false, &ValidationError{Field: "items", Reason: "Minimal harus memilih 1 item"}
	}
	if len(in.Items) > 100 {
		return PublicOrderResponse{}, false, &ValidationError{Field: "items", Reason: "Maksimal 100 item"}
	}
	for _, it := range in.Items {
		if it.Quantity <= 0 || it.Quantity > 99 {
			return PublicOrderResponse{}, false, &ValidationError{Field: "quantity", Reason: "Jumlah item harus antara 1 dan 99"}
		}
	}

	idempotencyKey = strings.TrimSpace(idempotencyKey)
	if idempotencyKey == "" {
		idempotencyKey = "web-" + customer.NewID()
	}

	reqBytes, _ := json.Marshal(in)
	hash := fmt.Sprintf("%x", sha256.Sum256(reqBytes))

	return s.webStore.CreateWeb(ctx, in, idempotencyKey, hash, requestID)
}

func (s *Service) PreviewWeb(ctx context.Context, items []ItemInput) (PreviewResponse, error) {
	if s.webStore == nil {
		return PreviewResponse{}, errors.New("web store not configured")
	}
	if len(items) == 0 {
		return PreviewResponse{}, &ValidationError{Field: "items", Reason: "Minimal harus memilih 1 item"}
	}
	if len(items) > 100 {
		return PreviewResponse{}, &ValidationError{Field: "items", Reason: "Maksimal 100 item"}
	}
	for _, it := range items {
		if it.Quantity <= 0 || it.Quantity > 99 {
			return PreviewResponse{}, &ValidationError{Field: "quantity", Reason: "Jumlah item harus antara 1 dan 99"}
		}
	}
	return s.webStore.PreviewWeb(ctx, items)
}

func (s *Service) GetByPublicToken(ctx context.Context, token string) (PublicTrackingDetail, error) {
	if s.webStore == nil {
		return PublicTrackingDetail{}, errors.New("web store not configured")
	}
	return s.webStore.GetByPublicToken(ctx, token)
}
