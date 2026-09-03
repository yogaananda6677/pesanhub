package domain

type OrderSource string
type Fulfillment string
type OrderStatus string
type PaymentMethod string
type PaymentStatus string

const (
	OrderSourceWhatsApp       OrderSource   = "WHATSAPP"
	OrderSourceCashierManual  OrderSource   = "CASHIER_MANUAL"
	OrderSourceCustomerWeb    OrderSource   = "CUSTOMER_WEB"
	FulfillmentPickup         Fulfillment   = "PICKUP"
	OrderStatusPending        OrderStatus   = "PENDING"
	OrderStatusAccepted       OrderStatus   = "ACCEPTED"
	OrderStatusPreparing      OrderStatus   = "PREPARING"
	OrderStatusReady          OrderStatus   = "READY_FOR_PICKUP"
	OrderStatusCompleted      OrderStatus   = "COMPLETED"
	OrderStatusRejected       OrderStatus   = "REJECTED"
	OrderStatusCancelled      OrderStatus   = "CANCELLED"
	PaymentMethodCash         PaymentMethod = "CASH"
	PaymentMethodMidtransQRIS PaymentMethod = "MIDTRANS_QRIS"
	PaymentStatusUnpaid       PaymentStatus = "UNPAID"
	PaymentStatusPending      PaymentStatus = "PENDING_PAYMENT"
	PaymentStatusPaid         PaymentStatus = "PAID"
	PaymentStatusFailed       PaymentStatus = "FAILED"
	PaymentStatusExpired      PaymentStatus = "EXPIRED"
	PaymentStatusRefunded     PaymentStatus = "REFUNDED"
)

func (v OrderSource) Valid() bool {
	return v == OrderSourceWhatsApp || v == OrderSourceCashierManual || v == OrderSourceCustomerWeb
}
func (v Fulfillment) Valid() bool { return v == FulfillmentPickup }
func (v OrderStatus) Valid() bool {
	switch v {
	case OrderStatusPending, OrderStatusAccepted, OrderStatusPreparing, OrderStatusReady, OrderStatusCompleted, OrderStatusRejected, OrderStatusCancelled:
		return true
	}
	return false
}
func (v PaymentMethod) Valid() bool { return v == PaymentMethodCash || v == PaymentMethodMidtransQRIS }
func (v PaymentStatus) Valid() bool {
	switch v {
	case PaymentStatusUnpaid, PaymentStatusPending, PaymentStatusPaid, PaymentStatusFailed, PaymentStatusExpired, PaymentStatusRefunded:
		return true
	}
	return false
}
