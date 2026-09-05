package contractfixture

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"pesenhub/backend/internal/domain"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/order"
	"pesenhub/backend/internal/payment"
)

type Enums struct {
	OrderSources    []domain.OrderSource   `json:"order_sources"`
	OrderStatuses   []domain.OrderStatus   `json:"order_statuses"`
	PaymentMethods  []domain.PaymentMethod `json:"payment_methods"`
	PaymentStatuses []domain.PaymentStatus `json:"payment_statuses"`
	EventTypes      []string               `json:"event_types"`
}

type QueueResponse struct {
	Data []order.OrderDetail `json:"data"`
}

type ErrorCase struct {
	HTTPStatus int                   `json:"http_status"`
	Headers    map[string]string     `json:"headers"`
	Body       httpapi.ErrorEnvelope `json:"body"`
}

type Fixture struct {
	ContractVersion int                        `json:"contract_version"`
	Enums           Enums                      `json:"enums"`
	QueueResponse   QueueResponse              `json:"queue_response"`
	OrderCollection order.OrderCollection      `json:"order_collection"`
	Payment         payment.Payment            `json:"payment"`
	ErrorCases      []ErrorCase                `json:"error_cases"`
	Events          []order.OrderEventEnvelope `json:"events"`
}

func Canonical() Fixture {
	createdAt := time.Date(2026, 9, 5, 8, 0, 0, 0, time.UTC)
	updatedAt := createdAt.Add(4 * time.Minute)
	paidAt := createdAt.Add(2 * time.Minute)
	expiresAt := createdAt.Add(15 * time.Minute)
	phone := "0812****7890"
	nextCursor := "MjAyNi0wOS0wNVQwODowMDowMFosYjEwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAx"

	detail := order.OrderDetail{
		ID:            "b1000000-0000-4000-8000-000000000001",
		OrderNumber:   "ORD-CONTRACT-001",
		ClientOrderID: "c1000000-0000-4000-8000-000000000001",
		Source:        string(domain.OrderSourceCashierManual),
		Status:        string(domain.OrderStatusPreparing),
		CustomerName:  "Pelanggan Kontrak",
		CustomerPhone: &phone,
		Notes:         "Fixture sintetis",
		TotalAmount:   25000,
		Version:       3,
		CreatedAt:     createdAt,
		UpdatedAt:     updatedAt,
		Items: []order.OrderItemDetail{{
			ID:              "d1000000-0000-4000-8000-000000000001",
			MenuID:          "e1000000-0000-4000-8000-000000000001",
			Name:            "Nasi Goreng Kontrak",
			SKU:             "CONTRACT-001",
			CategoryName:    "Makanan",
			Quantity:        1,
			UnitPriceAmount: 25000,
			LineTotalAmount: 25000,
			Notes:           "Pedas sedang",
			Modifiers: []order.ModifierSnapshot{{
				ID: "f1000000-0000-4000-8000-000000000001", Name: "Pedas sedang", PriceDeltaAmount: 0,
			}},
		}},
		History: []order.OrderStatusHistoryEntry{{
			FromStatus: string(domain.OrderStatusAccepted), ToStatus: string(domain.OrderStatusPreparing),
			Version: 3, ActorType: "STAFF", ActorID: "staff-contract", CreatedAt: updatedAt,
		}},
	}

	eventPayload := func(status string, version int64) json.RawMessage {
		payload, _ := json.Marshal(map[string]any{
			"order_id": detail.ID, "order_number": detail.OrderNumber, "source": detail.Source,
			"status": status, "total_amount": detail.TotalAmount, "version": version,
		})
		return payload
	}

	return Fixture{
		ContractVersion: 1,
		Enums: Enums{
			OrderSources: []domain.OrderSource{
				domain.OrderSourceCashierManual, domain.OrderSourceCustomerWeb, domain.OrderSourceWhatsApp,
			},
			OrderStatuses: []domain.OrderStatus{
				domain.OrderStatusPending, domain.OrderStatusAccepted, domain.OrderStatusPreparing,
				domain.OrderStatusReady, domain.OrderStatusCompleted, domain.OrderStatusRejected, domain.OrderStatusCancelled,
			},
			PaymentMethods: []domain.PaymentMethod{domain.PaymentMethodCash, domain.PaymentMethodMidtransQRIS},
			PaymentStatuses: []domain.PaymentStatus{
				domain.PaymentStatusUnpaid, domain.PaymentStatusPending, domain.PaymentStatusPaid,
				domain.PaymentStatusFailed, domain.PaymentStatusExpired, domain.PaymentStatusRefunded,
			},
			EventTypes: []string{"ORDER_CREATED", "ORDER_STATUS_CHANGED"},
		},
		QueueResponse:   QueueResponse{Data: []order.OrderDetail{detail}},
		OrderCollection: order.OrderCollection{Data: []order.OrderDetail{detail}, Page: httpapi.PageMeta{Size: 20, NextCursor: &nextCursor}},
		Payment: payment.Payment{
			ID: "a1000000-0000-4000-8000-000000000001", OrderID: detail.ID,
			Method: string(domain.PaymentMethodMidtransQRIS), Status: string(domain.PaymentStatusPaid),
			Amount: 25000, Version: 2, PaidAt: &paidAt, CreatedAt: createdAt, UpdatedAt: updatedAt,
			ProviderOrderID: "PH-CONTRACT-001", ProviderReference: "provider-contract-001",
			QRCodeURL: "https://example.test/qr/contract", ExpiresAt: &expiresAt,
		},
		ErrorCases: []ErrorCase{
			errorCase(401, "UNAUTHENTICATED", "Authentication is required.", nil),
			errorCase(403, "FORBIDDEN", "Access is not allowed.", nil),
			errorCase(422, "VALIDATION_FAILED", "Order validation failed.", []httpapi.FieldError{{Field: "items", Reason: "required"}}),
			errorCase(409, "VERSION_CONFLICT", "Order was modified.", nil),
			errorCase(500, "INTERNAL_ERROR", "An unexpected error occurred.", nil),
		},
		Events: []order.OrderEventEnvelope{
			{EventID: "81000000-0000-4000-8000-000000000001", EventType: "ORDER_CREATED", OrderID: detail.ID, Version: 1, Source: detail.Source, Status: string(domain.OrderStatusPending), Timestamp: createdAt, Payload: eventPayload(string(domain.OrderStatusPending), 1)},
			{EventID: "81000000-0000-4000-8000-000000000002", EventType: "ORDER_STATUS_CHANGED", OrderID: detail.ID, Version: 3, Source: detail.Source, Status: detail.Status, Timestamp: updatedAt, Payload: eventPayload(detail.Status, detail.Version)},
		},
	}
}

func Bytes() ([]byte, error) {
	data, err := json.MarshalIndent(Canonical(), "", "  ")
	if err != nil {
		return nil, err
	}
	return append(data, '\n'), nil
}

func Check(path string) error {
	want, err := Bytes()
	if err != nil {
		return err
	}
	got, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if !bytes.Equal(got, want) {
		return fmt.Errorf("contract fixture is stale; run: go run ./cmd/contractfixture -write %s", path)
	}
	return nil
}

func Write(path string) error {
	data, err := Bytes()
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}

func errorEnvelope(code, message, requestID string, details []httpapi.FieldError) httpapi.ErrorEnvelope {
	return httpapi.ErrorEnvelope{Error: httpapi.Error{Code: code, Message: message, RequestID: requestID, Details: details}}
}

func errorCase(status int, code, message string, details []httpapi.FieldError) ErrorCase {
	requestID := fmt.Sprintf("req-contract-%d", status)
	return ErrorCase{
		HTTPStatus: status,
		Headers:    map[string]string{"x-request-id": requestID},
		Body:       errorEnvelope(code, message, requestID, details),
	}
}
