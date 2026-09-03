package customer

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
)

var (
	ErrInvalidProfile  = errors.New("invalid customer profile")
	ErrPhoneCollision  = errors.New("phone belongs to a different profile")
	ErrUnauthenticated = errors.New("customer authentication required")
	ErrUnauthorized    = errors.New("customer access unauthorized")
	ErrVersionConflict = errors.New("customer version conflict")
)

type Profile struct {
	ID          string          `json:"id"`
	PhoneE164   string          `json:"phone_e164"`
	DisplayName string          `json:"display_name"`
	Preferences json.RawMessage `json:"preferences"`
	Version     int64           `json:"version"`
}

type CreateInput struct {
	Phone, DisplayName, IdempotencyKey string
	Preferences                        json.RawMessage
}
type UpdateInput struct {
	DisplayName     string
	Preferences     json.RawMessage
	ExpectedVersion int64
}
type OrderSummary struct {
	ID, OrderNumber, Status string
	TotalAmount             int64
}
type Principal struct{ Subject, Role, CustomerID string }

type Repository interface {
	CreateOrGet(context.Context, Profile, string) (Profile, bool, error)
	Update(context.Context, string, UpdateInput) (Profile, error)
	OrderHistory(context.Context, string) ([]OrderSummary, error)
}

type Service struct {
	repo  Repository
	newID func() string
}

func NewService(repo Repository, newID func() string) *Service {
	return &Service{repo: repo, newID: newID}
}

func (s *Service) Create(ctx context.Context, in CreateInput) (Profile, bool, error) {
	phone, err := NormalizeIndonesia(in.Phone)
	if err != nil || strings.TrimSpace(in.DisplayName) == "" || len(strings.TrimSpace(in.DisplayName)) > 120 || !ValidIdempotencyKey(in.IdempotencyKey) || !validPreferences(in.Preferences) {
		return Profile{}, false, ErrInvalidProfile
	}
	wanted := Profile{ID: s.newID(), PhoneE164: phone, DisplayName: strings.TrimSpace(in.DisplayName), Preferences: normalizePreferences(in.Preferences), Version: 1}
	got, created, err := s.repo.CreateOrGet(ctx, wanted, in.IdempotencyKey)
	if err != nil {
		return Profile{}, false, err
	}
	if !created && (got.PhoneE164 != wanted.PhoneE164 || got.DisplayName != wanted.DisplayName || string(got.Preferences) != string(wanted.Preferences)) {
		return Profile{}, false, ErrPhoneCollision
	}
	return got, created, nil
}

func (s *Service) Update(ctx context.Context, principal Principal, id string, in UpdateInput) (Profile, error) {
	if err := authorize(principal, id); err != nil {
		return Profile{}, err
	}
	if strings.TrimSpace(in.DisplayName) == "" || len(strings.TrimSpace(in.DisplayName)) > 120 || in.ExpectedVersion < 1 || !validPreferences(in.Preferences) {
		return Profile{}, ErrInvalidProfile
	}
	in.DisplayName, in.Preferences = strings.TrimSpace(in.DisplayName), normalizePreferences(in.Preferences)
	return s.repo.Update(ctx, id, in)
}

func (s *Service) History(ctx context.Context, principal Principal, id string) ([]OrderSummary, error) {
	if err := authorize(principal, id); err != nil {
		return nil, err
	}
	return s.repo.OrderHistory(ctx, id)
}

func authorize(p Principal, id string) error {
	if p.Subject == "" {
		return ErrUnauthenticated
	}
	if p.Role == "STAFF" || (p.Role == "CUSTOMER" && p.CustomerID != "" && p.CustomerID == id) {
		return nil
	}
	return ErrUnauthorized
}
func validPreferences(v json.RawMessage) bool {
	var x map[string]any
	return len(v) == 0 || (json.Unmarshal(v, &x) == nil && x != nil)
}
func normalizePreferences(v json.RawMessage) json.RawMessage {
	if len(v) == 0 {
		return json.RawMessage(`{}`)
	}
	var x any
	_ = json.Unmarshal(v, &x)
	b, _ := json.Marshal(x)
	return b
}
