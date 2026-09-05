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

type fakeQRISStore struct {
	fakeStore
	payment              Payment
	execute, created     bool
	prepareErr, finalErr error
	failCode             string
	failPermanent        bool
}

func (f *fakeQRISStore) PrepareQRIS(context.Context, string, string, string, string, string) (Payment, bool, bool, error) {
	return f.payment, f.execute, f.created, f.prepareErr
}
func (f *fakeQRISStore) CompleteQRIS(_ context.Context, _ Payment, charge QRISCharge, _, _ string) (Payment, error) {
	f.payment.Status = "PENDING_PAYMENT"
	f.payment.ProviderReference = charge.ProviderReference
	f.payment.QRCodeURL = charge.QRCodeURL
	return f.payment, f.finalErr
}
func (f *fakeQRISStore) FailQRIS(_ context.Context, _ Payment, code string, permanent bool, _, _ string) error {
	f.failCode, f.failPermanent = code, permanent
	return f.finalErr
}

type fakeMidtrans struct {
	calls   int
	orderID string
	amount  int64
	charge  QRISCharge
	err     error
}

func (f *fakeMidtrans) CreateQRIS(_ context.Context, orderID string, amount int64) (QRISCharge, error) {
	f.calls++
	f.orderID, f.amount = orderID, amount
	return f.charge, f.err
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

func TestCreateQRISUsesReservedProviderIDAndBackendAmount(t *testing.T) {
	store := &fakeQRISStore{payment: Payment{ID: "pay-1", ProviderOrderID: "PH-pay-1", Amount: 27500}, execute: true, created: true}
	gateway := &fakeMidtrans{charge: QRISCharge{ProviderOrderID: "PH-pay-1", ProviderReference: "tx-1", Status: "pending", QRCodeURL: "https://example.test/qr"}}
	service := NewServiceWithMidtrans(store, gateway)
	p, created, err := service.CreateQRIS(context.Background(), customer.Principal{Subject: "staff-1", Role: "STAFF"}, "b1000000-0000-4000-8000-000000000001", "qris-1", "req-1")
	if err != nil || !created || p.Status != "PENDING_PAYMENT" || gateway.calls != 1 || gateway.orderID != "PH-pay-1" || gateway.amount != 27500 {
		t.Fatalf("payment=%#v created=%v calls=%d request=%s/%d err=%v", p, created, gateway.calls, gateway.orderID, gateway.amount, err)
	}
}

func TestCreateQRISReplayDoesNotCallProviderAgain(t *testing.T) {
	store := &fakeQRISStore{payment: Payment{ID: "pay-1", Status: "PENDING_PAYMENT", ProviderOrderID: "PH-pay-1", QRCodeURL: "https://example.test/qr"}}
	gateway := &fakeMidtrans{}
	service := NewServiceWithMidtrans(store, gateway)
	p, created, err := service.CreateQRIS(context.Background(), customer.Principal{Subject: "staff-1", Role: "STAFF"}, "b1000000-0000-4000-8000-000000000001", "qris-1", "req-2")
	if err != nil || created || p.ID != "pay-1" || gateway.calls != 0 {
		t.Fatalf("payment=%#v created=%v calls=%d err=%v", p, created, gateway.calls, err)
	}
}

func TestCreateQRISMapsTimeoutAndPermanentFailure(t *testing.T) {
	for _, tt := range []struct {
		kind      string
		want      error
		permanent bool
	}{{"timeout", ErrMidtransUnavailable, false}, {"server", ErrMidtransUnavailable, false}, {"duplicate", ErrMidtransUnavailable, false}, {"rate_limited", ErrMidtransUnavailable, false}, {"rejected", ErrMidtransRejected, true}} {
		t.Run(tt.kind, func(t *testing.T) {
			store := &fakeQRISStore{payment: Payment{ID: "pay-1", ProviderOrderID: "PH-pay-1", Amount: 1000}, execute: true}
			gateway := &fakeMidtrans{err: &ProviderError{Kind: tt.kind}}
			service := NewServiceWithMidtrans(store, gateway)
			_, _, err := service.CreateQRIS(context.Background(), customer.Principal{Subject: "staff-1", Role: "STAFF"}, "b1000000-0000-4000-8000-000000000001", "qris-1", "req-1")
			if !errors.Is(err, tt.want) || store.failCode != tt.kind || store.failPermanent != tt.permanent {
				t.Fatalf("err=%v failure=%s/%v", err, store.failCode, store.failPermanent)
			}
		})
	}
}

func TestCreateQRISValidationAndAuthorization(t *testing.T) {
	service := NewServiceWithMidtrans(&fakeQRISStore{}, &fakeMidtrans{})
	validID := "b1000000-0000-4000-8000-000000000001"
	if _, _, err := service.CreateQRIS(context.Background(), customer.Principal{}, validID, "qris-1", "req"); !errors.Is(err, customer.ErrUnauthorized) {
		t.Fatalf("auth error=%v", err)
	}
	if _, _, err := service.CreateQRIS(context.Background(), customer.Principal{Subject: "staff", Role: "STAFF"}, "bad", "qris-1", "req"); !errors.Is(err, ErrOrderNotFound) {
		t.Fatalf("id error=%v", err)
	}
	if _, _, err := service.CreateQRIS(context.Background(), customer.Principal{Subject: "staff", Role: "STAFF"}, validID, "", "req"); !errors.Is(err, ErrInvalidInput) {
		t.Fatalf("key error=%v", err)
	}
}

func TestCreateQRISDoesNotPersistUnknownProviderErrorDetail(t *testing.T) {
	store := &fakeQRISStore{payment: Payment{ID: "pay-1", ProviderOrderID: "PH-pay-1", Amount: 1000}, execute: true}
	gateway := &fakeMidtrans{err: &ProviderError{Kind: "secret-provider-detail"}}
	service := NewServiceWithMidtrans(store, gateway)
	_, _, err := service.CreateQRIS(context.Background(), customer.Principal{Subject: "staff-1", Role: "STAFF"}, "b1000000-0000-4000-8000-000000000001", "qris-1", "req-1")
	if !errors.Is(err, ErrMidtransUnavailable) || store.failCode != "provider_error" {
		t.Fatalf("err=%v stored code=%q", err, store.failCode)
	}
}
