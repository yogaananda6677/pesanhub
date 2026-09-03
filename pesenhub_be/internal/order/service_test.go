package order

import (
	"context"
	"errors"
	"testing"
)

type creatorFunc func(context.Context, CreateInput, string, string, string) (Order, bool, error)

func (f creatorFunc) Create(c context.Context, i CreateInput, k, h, a string) (Order, bool, error) {
	return f(c, i, k, h, a)
}

func validInput() CreateInput {
	return CreateInput{ClientOrderID: "11111111-1111-4111-8111-111111111111", CustomerName: " Budi ", CustomerPhone: "081234567890", Items: []ItemInput{{MenuID: "22222222-2222-4222-8222-222222222222", Quantity: 2}}}
}
func TestCreateManualNormalizesAndHashes(t *testing.T) {
	called := false
	s := NewService(creatorFunc(func(_ context.Context, in CreateInput, key, hash, actor string) (Order, bool, error) {
		called = true
		if in.CustomerName != "Budi" || in.CustomerPhone != "+6281234567890" || key != "retry-1" || len(hash) != 64 || actor != "staff-1|req-1" {
			t.Fatalf("unexpected normalized call: %#v %s %s", in, hash, actor)
		}
		return Order{ID: "order-1"}, true, nil
	}))
	o, created, err := s.CreateManual(context.Background(), validInput(), "retry-1", "staff-1", "req-1")
	if err != nil || !created || o.ID != "order-1" || !called {
		t.Fatalf("result=%#v created=%v err=%v", o, created, err)
	}
}
func TestCreateManualRejectsInvalidWithoutStore(t *testing.T) {
	s := NewService(creatorFunc(func(context.Context, CreateInput, string, string, string) (Order, bool, error) {
		t.Fatal("store called")
		return Order{}, false, nil
	}))
	cases := []CreateInput{validInput(), validInput(), validInput()}
	cases[0].ClientOrderID = "bad"
	cases[1].Items[0].Quantity = 0
	cases[2].CustomerName = ""
	for _, in := range cases {
		if _, _, err := s.CreateManual(context.Background(), in, "key", "staff", "req"); !errors.Is(err, ErrInvalidInput) {
			t.Fatalf("expected invalid, got %v", err)
		}
	}
}
func TestCreateManualHashDetectsPayloadChange(t *testing.T) {
	var first string
	s := NewService(creatorFunc(func(_ context.Context, _ CreateInput, _ string, hash, _ string) (Order, bool, error) {
		if first == "" {
			first = hash
		} else if first == hash {
			t.Fatal("hash did not change")
		}
		return Order{}, true, nil
	}))
	in := validInput()
	s.CreateManual(context.Background(), in, "key", "s", "r")
	in.Items[0].Quantity++
	s.CreateManual(context.Background(), in, "key", "s", "r")
}
