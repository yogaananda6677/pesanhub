package payment

import (
	"context"
	"errors"
	"testing"

	"pesenhub/backend/internal/customer"
)

type fakeStore struct {
	calls             int
	gotHash, gotActor string
	result            Payment
	created           bool
	err               error
}

func (f *fakeStore) RecordCash(_ context.Context, _ string, _ CashInput, _, hash, actor, _ string) (Payment, bool, error) {
	f.calls++
	f.gotHash, f.gotActor = hash, actor
	return f.result, f.created, f.err
}

func TestRecordCashValidationAndAuthorization(t *testing.T) {
	s := NewService(&fakeStore{})
	validID := "b1000000-0000-4000-8000-000000000001"
	tests := []struct {
		name    string
		p       customer.Principal
		id, key string
		amount  int64
		want    error
	}{
		{"unauthorized", customer.Principal{}, validID, "cash-1", 1000, customer.ErrUnauthorized},
		{"invalid id", customer.Principal{Subject: "staff-1", Role: "STAFF"}, "bad", "cash-1", 1000, ErrOrderNotFound},
		{"missing key", customer.Principal{Subject: "staff-1", Role: "STAFF"}, validID, "", 1000, ErrInvalidInput},
		{"invalid amount", customer.Principal{Subject: "staff-1", Role: "STAFF"}, validID, "cash-1", 0, ErrInvalidInput},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, _, err := s.RecordCash(context.Background(), tt.p, tt.id, CashInput{Amount: tt.amount}, tt.key, "req-1")
			if !errors.Is(err, tt.want) {
				t.Fatalf("got %v want %v", err, tt.want)
			}
		})
	}
}

func TestRecordCashPassesStableHashAndActor(t *testing.T) {
	f := &fakeStore{result: Payment{ID: "pay-1"}, created: true}
	s := NewService(f)
	p, created, err := s.RecordCash(context.Background(), customer.Principal{Subject: "staff-7", Role: "STAFF"}, "b1000000-0000-4000-8000-000000000001", CashInput{Amount: 25000}, "cash-1", "req-1")
	if err != nil || !created || p.ID != "pay-1" || f.calls != 1 || len(f.gotHash) != 64 || f.gotActor != "staff-7" {
		t.Fatalf("unexpected result: %#v %v hash=%q actor=%q", p, err, f.gotHash, f.gotActor)
	}
}
