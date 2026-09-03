package order

import (
	"context"
	"errors"
	"testing"

	"pesenhub/backend/internal/domain"
)

type transitionerFunc func(context.Context, string, TransitionInput, string, string, string, string) (StatusResult, bool, error)

func (f transitionerFunc) Transition(c context.Context, id string, in TransitionInput, key, hash, actor, role string) (StatusResult, bool, error) {
	return f(c, id, in, key, hash, actor, role)
}

func TestValidTransition(t *testing.T) {
	tests := []struct {
		from, to domain.OrderStatus
		want     bool
	}{
		{domain.OrderStatusPending, domain.OrderStatusAccepted, true}, {domain.OrderStatusPending, domain.OrderStatusRejected, true}, {domain.OrderStatusPending, domain.OrderStatusCancelled, true},
		{domain.OrderStatusAccepted, domain.OrderStatusPreparing, true}, {domain.OrderStatusAccepted, domain.OrderStatusCancelled, true},
		{domain.OrderStatusPreparing, domain.OrderStatusReady, true}, {domain.OrderStatusReady, domain.OrderStatusCompleted, true},
		{domain.OrderStatusPending, domain.OrderStatusCompleted, false}, {domain.OrderStatusPreparing, domain.OrderStatusCancelled, false}, {domain.OrderStatusCompleted, domain.OrderStatusPending, false}, {domain.OrderStatusRejected, domain.OrderStatusAccepted, false}, {domain.OrderStatusCancelled, domain.OrderStatusPending, false},
	}
	for _, tt := range tests {
		if got := ValidTransition(tt.from, tt.to); got != tt.want {
			t.Errorf("%s -> %s = %v, want %v", tt.from, tt.to, got, tt.want)
		}
	}
}

func TestTransitionValidatesAndHashes(t *testing.T) {
	called := false
	s := &Service{transitions: transitionerFunc(func(_ context.Context, id string, in TransitionInput, key, hash, actor, role string) (StatusResult, bool, error) {
		called = true
		if id != "11111111-1111-4111-8111-111111111111" || in.TargetStatus != "READY_FOR_PICKUP" || key != "transition-1" || len(hash) != 64 || actor != "staff" || role != "STAFF|req" {
			t.Fatalf("unexpected call: %s %#v %s %s %s %s", id, in, key, hash, actor, role)
		}
		return StatusResult{ID: id, Status: in.TargetStatus, Version: 4}, true, nil
	})}
	got, changed, err := s.Transition(context.Background(), "11111111-1111-4111-8111-111111111111", TransitionInput{TargetStatus: " READY_FOR_PICKUP ", ExpectedVersion: 3}, "transition-1", "staff", "STAFF", "req")
	if err != nil || !changed || got.Version != 4 || !called {
		t.Fatalf("got=%#v changed=%v err=%v", got, changed, err)
	}
}

func TestTransitionRejectsInvalidInput(t *testing.T) {
	s := &Service{transitions: transitionerFunc(func(context.Context, string, TransitionInput, string, string, string, string) (StatusResult, bool, error) {
		t.Fatal("store called")
		return StatusResult{}, false, nil
	})}
	cases := []TransitionInput{{TargetStatus: "UNKNOWN", ExpectedVersion: 1}, {TargetStatus: "ACCEPTED", ExpectedVersion: 0}}
	for _, in := range cases {
		if _, _, err := s.Transition(context.Background(), "11111111-1111-4111-8111-111111111111", in, "key", "staff", "STAFF", "req"); !errors.Is(err, ErrInvalidInput) {
			t.Fatalf("expected invalid, got %v", err)
		}
	}
}
