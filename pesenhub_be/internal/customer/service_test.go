package customer

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
)

type fakeRepo struct {
	profile      Profile
	created      bool
	updates      int
	historyCalls int
}

func (f *fakeRepo) CreateOrGet(_ context.Context, p Profile, _ string) (Profile, bool, error) {
	if f.profile.ID == "" {
		f.profile = p
	}
	return f.profile, f.created, nil
}
func (f *fakeRepo) Update(_ context.Context, _ string, in UpdateInput) (Profile, error) {
	f.updates++
	f.profile.DisplayName, f.profile.Preferences, f.profile.Version = in.DisplayName, in.Preferences, in.ExpectedVersion+1
	return f.profile, nil
}
func (f *fakeRepo) OrderHistory(context.Context, string) ([]OrderSummary, error) {
	f.historyCalls++
	return []OrderSummary{{ID: "o1"}}, nil
}

func TestCreateRetryAndCollision(t *testing.T) {
	repo := &fakeRepo{created: true}
	s := NewService(repo, func() string { return "customer-1" })
	first, _, err := s.Create(context.Background(), CreateInput{Phone: "0812 3456 7890", DisplayName: "Ayu", IdempotencyKey: "key-1", Preferences: json.RawMessage(`{"spicy":true}`)})
	if err != nil || first.PhoneE164 != "+6281234567890" {
		t.Fatalf("first = %#v, %v", first, err)
	}
	repo.created = false
	if _, created, err := s.Create(context.Background(), CreateInput{Phone: "+6281234567890", DisplayName: "Ayu", IdempotencyKey: "key-1", Preferences: json.RawMessage(`{"spicy":true}`)}); err != nil || created {
		t.Fatalf("retry created=%v err=%v", created, err)
	}
	if _, _, err := s.Create(context.Background(), CreateInput{Phone: "081234567890", DisplayName: "Different", IdempotencyKey: "key-2"}); !errors.Is(err, ErrPhoneCollision) {
		t.Fatalf("collision err=%v", err)
	}
}

func TestInvalidPhoneIsNotPersisted(t *testing.T) {
	repo := &fakeRepo{}
	_, _, err := NewService(repo, func() string { return "customer-1" }).Create(context.Background(), CreateInput{Phone: "021-555", DisplayName: "Ayu", IdempotencyKey: "key"})
	if !errors.Is(err, ErrInvalidProfile) || repo.profile.ID != "" {
		t.Fatalf("err=%v profile=%#v", err, repo.profile)
	}
}

func TestHistoryRequiresAuthorizedPrincipal(t *testing.T) {
	repo := &fakeRepo{}
	s := NewService(repo, func() string { return "unused" })
	if _, err := s.History(context.Background(), Principal{}, "customer-1"); !errors.Is(err, ErrUnauthenticated) {
		t.Fatalf("missing principal err=%v", err)
	}
	if _, err := s.History(context.Background(), Principal{Subject: "other", Role: "CUSTOMER", CustomerID: "other"}, "customer-1"); !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("wrong principal err=%v", err)
	}
	if repo.historyCalls != 0 {
		t.Fatalf("unauthorized lookup reached repository")
	}
	if _, err := s.History(context.Background(), Principal{Subject: "self", Role: "CUSTOMER", CustomerID: "customer-1"}, "customer-1"); err != nil || repo.historyCalls != 1 {
		t.Fatalf("authorized err=%v calls=%d", err, repo.historyCalls)
	}
}

func TestUpdateRequiresVersionAndAuthorization(t *testing.T) {
	repo := &fakeRepo{}
	s := NewService(repo, func() string { return "unused" })
	if _, err := s.Update(context.Background(), Principal{}, "customer-1", UpdateInput{}); !errors.Is(err, ErrUnauthenticated) {
		t.Fatal(err)
	}
	_, err := s.Update(context.Background(), Principal{Subject: "staff-1", Role: "STAFF"}, "customer-1", UpdateInput{DisplayName: "Ayu", Preferences: json.RawMessage(`{}`), ExpectedVersion: 1})
	if err != nil || repo.updates != 1 {
		t.Fatalf("err=%v updates=%d", err, repo.updates)
	}
}
