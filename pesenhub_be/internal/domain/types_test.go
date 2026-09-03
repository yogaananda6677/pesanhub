package domain

import "testing"

func TestCanonicalDomainValues(t *testing.T) {
	tests := []struct {
		name  string
		valid bool
	}{
		{"source", OrderSourceWhatsApp.Valid() && OrderSourceCashierManual.Valid() && OrderSourceCustomerWeb.Valid() && !OrderSource("GOFOOD").Valid()},
		{"fulfillment", FulfillmentPickup.Valid() && !Fulfillment("DELIVERY").Valid()},
		{"order status", OrderStatusReady.Valid() && !OrderStatus("READY").Valid()},
		{"payment method", PaymentMethodMidtransQRIS.Valid() && !PaymentMethod("CARD").Valid()},
		{"payment status", PaymentStatusPending.Valid() && !PaymentStatus("PENDING").Valid()},
	}
	for _, tt := range tests {
		if !tt.valid {
			t.Errorf("%s mapping is invalid", tt.name)
		}
	}
}
