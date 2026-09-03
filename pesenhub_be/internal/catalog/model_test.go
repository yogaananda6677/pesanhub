package catalog

import (
	"errors"
	"testing"
)

func TestPriceValidatesAvailabilityAndModifiers(t *testing.T) {
	menu := Menu{ID: "m1", PriceAmount: 15000, Available: true, Groups: []Group{{ID: "spice", Active: true, MinSelect: 1, MaxSelect: 1, Options: []Option{{ID: "hot", Available: true}, {ID: "mild", Available: false}}}, {ID: "topping", Active: true, MaxSelect: 2, Options: []Option{{ID: "egg", Available: true, PriceDeltaAmount: 5000}}}}}
	price, err := Price(menu, []Selection{{GroupID: "spice", OptionIDs: []string{"hot"}}, {GroupID: "topping", OptionIDs: []string{"egg"}}})
	if err != nil || price != 20000 {
		t.Fatalf("price=%d err=%v", price, err)
	}
	for name, selections := range map[string][]Selection{"missing required": {}, "foreign option": {{GroupID: "spice", OptionIDs: []string{"egg"}}}, "duplicate": {{GroupID: "spice", OptionIDs: []string{"hot", "hot"}}}} {
		if _, err := Price(menu, selections); !errors.Is(err, ErrInvalidModifier) {
			t.Errorf("%s err=%v", name, err)
		}
	}
	if _, err := Price(menu, []Selection{{GroupID: "spice", OptionIDs: []string{"mild"}}}); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("unavailable option err=%v", err)
	}
	menu.Available = false
	if _, err := Price(menu, nil); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("unavailable menu err=%v", err)
	}
}
