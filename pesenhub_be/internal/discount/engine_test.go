package discount

import (
	"testing"
	"time"
)

func ptr[T any](v T) *T {
	return &v
}

func TestCalculate_OrderPercentage(t *testing.T) {
	d := &Discount{
		ID:             "disc-1",
		Name:           "Diskon 10% All",
		Scope:          ScopeOrder,
		Channel:        ChannelAll,
		Type:           TypePercentage,
		Value:          10,
		MinOrderAmount: 20000,
		IsActive:       true,
	}

	res := Calculate(d, CalculationInput{
		Channel:        "OFFLINE",
		SubtotalAmount: 50000,
	})

	if !res.Eligible {
		t.Fatalf("expected eligible, got: %s", res.IneligibleReason)
	}
	if res.DiscountAmount != 5000 {
		t.Errorf("expected 5000 discount, got %d", res.DiscountAmount)
	}
	if res.FinalTotalAmount != 45000 {
		t.Errorf("expected 45000 final, got %d", res.FinalTotalAmount)
	}
}

func TestCalculate_OrderPercentageWithCap(t *testing.T) {
	d := &Discount{
		ID:                "disc-cap",
		Name:              "Diskon 50% Max 10rb",
		Scope:             ScopeOrder,
		Channel:           ChannelAll,
		Type:              TypePercentage,
		Value:             50,
		MaxDiscountAmount: ptr(int64(10000)),
		MinOrderAmount:    0,
		IsActive:          true,
	}

	res := Calculate(d, CalculationInput{
		Channel:        "OFFLINE",
		SubtotalAmount: 100000,
	})

	if !res.Eligible {
		t.Fatalf("expected eligible, got: %s", res.IneligibleReason)
	}
	// 50% of 100k is 50k, but max is 10k
	if res.DiscountAmount != 10000 {
		t.Errorf("expected 10000 discount, got %d", res.DiscountAmount)
	}
	if res.FinalTotalAmount != 90000 {
		t.Errorf("expected 90000 final, got %d", res.FinalTotalAmount)
	}
}

func TestCalculate_OrderFixed(t *testing.T) {
	d := &Discount{
		ID:             "disc-fixed",
		Name:           "Potongan 15rb",
		Scope:          ScopeOrder,
		Channel:        ChannelAll,
		Type:           TypeFixed,
		Value:          15000,
		MinOrderAmount: 30000,
		IsActive:       true,
	}

	res := Calculate(d, CalculationInput{
		Channel:        "CASHIER_MANUAL",
		SubtotalAmount: 40000,
	})

	if !res.Eligible {
		t.Fatalf("expected eligible, got: %s", res.IneligibleReason)
	}
	if res.DiscountAmount != 15000 {
		t.Errorf("expected 15000 discount, got %d", res.DiscountAmount)
	}
	if res.FinalTotalAmount != 25000 {
		t.Errorf("expected 25000 final, got %d", res.FinalTotalAmount)
	}
}

func TestCalculate_MinSpendNotMet(t *testing.T) {
	d := &Discount{
		ID:             "disc-min",
		Name:           "Diskon Min 50rb",
		Scope:          ScopeOrder,
		Channel:        ChannelAll,
		Type:           TypeFixed,
		Value:          10000,
		MinOrderAmount: 50000,
		IsActive:       true,
	}

	res := Calculate(d, CalculationInput{
		Channel:        "OFFLINE",
		SubtotalAmount: 45000,
	})

	if res.Eligible {
		t.Fatalf("expected ineligible due to min spend")
	}
	if res.DiscountAmount != 0 {
		t.Errorf("expected 0 discount, got %d", res.DiscountAmount)
	}
	if res.FinalTotalAmount != 45000 {
		t.Errorf("expected 45000 final, got %d", res.FinalTotalAmount)
	}
}

func TestCalculate_ItemPercentageSpecificMenu(t *testing.T) {
	d := &Discount{
		ID:             "disc-item",
		Name:           "Diskon 20% Martabak",
		Scope:          ScopeItem,
		Channel:        ChannelGoFood,
		Type:           TypePercentage,
		Value:          20,
		MinOrderAmount: 0,
		MenuIDs:        []string{"menu-martabak-1", "menu-martabak-2"},
		IsActive:       true,
	}

	// 1 martabak (30k) + 1 minuman (10k) = 40k subtotal
	items := []ItemForDiscount{
		{MenuID: "menu-martabak-1", UnitPrice: 30000, Quantity: 1, LineTotal: 30000},
		{MenuID: "menu-drink-1", UnitPrice: 10000, Quantity: 1, LineTotal: 10000},
	}

	res := Calculate(d, CalculationInput{
		Channel:        "GOFOOD",
		SubtotalAmount: 40000,
		Items:          items,
	})

	if !res.Eligible {
		t.Fatalf("expected eligible, got: %s", res.IneligibleReason)
	}
	// 20% of 30,000 = 6,000
	if res.DiscountAmount != 6000 {
		t.Errorf("expected 6000 discount, got %d", res.DiscountAmount)
	}
	if res.FinalTotalAmount != 34000 {
		t.Errorf("expected 34000 final, got %d", res.FinalTotalAmount)
	}
}

func TestCalculate_ItemNoMatchingItems(t *testing.T) {
	d := &Discount{
		ID:       "disc-item-only",
		Name:     "Diskon Terang Bulan",
		Scope:    ScopeItem,
		Channel:  ChannelAll,
		Type:     TypePercentage,
		Value:    15,
		MenuIDs:  []string{"menu-terang-bulan"},
		IsActive: true,
	}

	items := []ItemForDiscount{
		{MenuID: "menu-martabak", UnitPrice: 30000, Quantity: 1, LineTotal: 30000},
	}

	res := Calculate(d, CalculationInput{
		Channel:        "OFFLINE",
		SubtotalAmount: 30000,
		Items:          items,
	})

	if res.Eligible {
		t.Fatalf("expected ineligible because no item matches")
	}
	if res.DiscountAmount != 0 {
		t.Errorf("expected 0 discount, got %d", res.DiscountAmount)
	}
}

func TestCalculate_ChannelIsolation(t *testing.T) {
	d := &Discount{
		ID:       "disc-gf",
		Name:     "Khusus GoFood",
		Scope:    ScopeOrder,
		Channel:  ChannelGoFood,
		Type:     TypeFixed,
		Value:    5000,
		IsActive: true,
	}

	// Try with GrabFood
	res1 := Calculate(d, CalculationInput{
		Channel:        "GRABFOOD",
		SubtotalAmount: 30000,
	})
	if res1.Eligible {
		t.Errorf("expected GrabFood to be rejected for GoFood promo")
	}

	// Try with Offline / Cashier
	res2 := Calculate(d, CalculationInput{
		Channel:        "CASHIER_MANUAL",
		SubtotalAmount: 30000,
	})
	if res2.Eligible {
		t.Errorf("expected CASHIER_MANUAL to be rejected for GoFood promo")
	}

	// Try with GoFood
	res3 := Calculate(d, CalculationInput{
		Channel:        "GOFOOD",
		SubtotalAmount: 30000,
	})
	if !res3.Eligible {
		t.Errorf("expected GOFOOD to be accepted, got: %s", res3.IneligibleReason)
	}
	if res3.DiscountAmount != 5000 {
		t.Errorf("expected 5000 discount, got %d", res3.DiscountAmount)
	}
}

func TestCalculate_ActiveAndDates(t *testing.T) {
	past := time.Now().Add(-2 * time.Hour)
	future := time.Now().Add(2 * time.Hour)

	// Inactive
	dInactive := &Discount{
		ID:       "d-inact",
		Name:     "Inactive",
		Scope:    ScopeOrder,
		Channel:  ChannelAll,
		Type:     TypeFixed,
		Value:    5000,
		IsActive: false,
	}
	if res := Calculate(dInactive, CalculationInput{SubtotalAmount: 20000}); res.Eligible {
		t.Errorf("expected inactive discount to be rejected")
	}

	// Expired (End in past)
	dExpired := &Discount{
		ID:       "d-exp",
		Name:     "Expired",
		Scope:    ScopeOrder,
		Channel:  ChannelAll,
		Type:     TypeFixed,
		Value:    5000,
		IsActive: true,
		EndTime:  &past,
	}
	if res := Calculate(dExpired, CalculationInput{SubtotalAmount: 20000}); res.Eligible {
		t.Errorf("expected expired discount to be rejected")
	}

	// Valid with start in past and end in future
	dValid := &Discount{
		ID:        "d-valid",
		Name:      "Valid Promo",
		Scope:     ScopeOrder,
		Channel:   ChannelAll,
		Type:      TypeFixed,
		Value:     5000,
		IsActive:  true,
		StartTime: &past,
		EndTime:   &future,
	}
	if res := Calculate(dValid, CalculationInput{SubtotalAmount: 20000}); !res.Eligible {
		t.Errorf("expected valid date discount to be accepted, got: %s", res.IneligibleReason)
	}
}
