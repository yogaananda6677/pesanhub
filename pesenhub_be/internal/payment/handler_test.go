package payment

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/customer"
)

func TestCreateQRISHandlerRequiresStaff(t *testing.T) {
	handler := NewHandler(NewServiceWithMidtrans(&fakeQRISStore{}, &fakeMidtrans{}))
	req := httptest.NewRequest(http.MethodPost, "/api/v1/orders/b1000000-0000-4000-8000-000000000001/payments/qris", nil)
	req.SetPathValue("id", "b1000000-0000-4000-8000-000000000001")
	response := httptest.NewRecorder()
	handler.CreateQRIS(response, req)
	if response.Code != http.StatusForbidden || !strings.Contains(response.Body.String(), `"code":"FORBIDDEN"`) {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestReconcileHandlerRequiresStaffAndReturnsSafeRetry(t *testing.T) {
	now := time.Date(2026, 9, 5, 10, 0, 0, 0, time.UTC)
	candidate, _ := reconciliationFixture(now)
	candidate.PaymentID = "b1000000-0000-4000-8000-000000000001"
	store := &reconciliationStoreStub{candidate: candidate}
	reconciler := NewReconciler(ReconcilerConfig{Store: store, Gateway: &reconciliationGatewayStub{err: &ProviderError{Kind: "timeout"}}, Logger: slog.New(slog.NewTextHandler(io.Discard, nil)), Now: func() time.Time { return now }})
	handler := NewHandlerWithReconciler(nil, reconciler)

	request := func(withStaff bool) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/payments/"+candidate.PaymentID+"/reconcile", nil)
		req.SetPathValue("id", candidate.PaymentID)
		if withStaff {
			req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{Subject: "staff-1", Role: "STAFF"}))
		}
		response := httptest.NewRecorder()
		handler.Reconcile(response, req)
		return response
	}
	if response := request(false); response.Code != http.StatusForbidden {
		t.Fatalf("unauthorized status=%d body=%s", response.Code, response.Body.String())
	}
	response := request(true)
	if response.Code != http.StatusAccepted || !strings.Contains(response.Body.String(), `"outcome":"retry"`) || strings.Contains(response.Body.String(), "secret") {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestCreateQRISHandlerReturnsSanitizedPayment(t *testing.T) {
	store := &fakeQRISStore{payment: Payment{ID: "pay-1", OrderID: "b1000000-0000-4000-8000-000000000001", Method: "MIDTRANS_QRIS", Status: "UNPAID", ProviderOrderID: "PH-pay-1", Amount: 27500}, execute: true, created: true}
	gateway := &fakeMidtrans{charge: QRISCharge{ProviderOrderID: "PH-pay-1", ProviderReference: "tx-1", Status: "pending", QRCodeURL: "https://api.sandbox.midtrans.com/v2/qris/tx-1/qr-code"}}
	handler := NewHandler(NewServiceWithMidtrans(store, gateway))
	req := httptest.NewRequest(http.MethodPost, "/api/v1/orders/b1000000-0000-4000-8000-000000000001/payments/qris", nil)
	req.SetPathValue("id", "b1000000-0000-4000-8000-000000000001")
	req.Header.Set("Idempotency-Key", "qris-handler-1")
	req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{Subject: "staff-1", Role: "STAFF"}))
	response := httptest.NewRecorder()
	handler.CreateQRIS(response, req)
	if response.Code != http.StatusCreated || response.Header().Get("Location") != "/api/v1/payments/pay-1" || !strings.Contains(response.Body.String(), `"status":"PENDING_PAYMENT"`) || strings.Contains(response.Body.String(), "server-key") {
		t.Fatalf("status=%d headers=%v body=%s", response.Code, response.Header(), response.Body.String())
	}
}

func TestCreateQRISHandlerReturnsAcceptedWithoutCallingProviderForInflightReplay(t *testing.T) {
	store := &fakeQRISStore{payment: Payment{ID: "pay-1", OrderID: "b1000000-0000-4000-8000-000000000001", Method: "MIDTRANS_QRIS", Status: "UNPAID", ProviderOrderID: "PH-pay-1", Amount: 27500}}
	gateway := &fakeMidtrans{}
	handler := NewHandler(NewServiceWithMidtrans(store, gateway))
	req := httptest.NewRequest(http.MethodPost, "/api/v1/orders/b1000000-0000-4000-8000-000000000001/payments/qris", nil)
	req.SetPathValue("id", "b1000000-0000-4000-8000-000000000001")
	req.Header.Set("Idempotency-Key", "qris-handler-1")
	req = req.WithContext(customer.WithPrincipal(req.Context(), customer.Principal{Subject: "staff-1", Role: "STAFF"}))
	response := httptest.NewRecorder()
	handler.CreateQRIS(response, req)
	if response.Code != http.StatusAccepted || gateway.calls != 0 {
		t.Fatalf("status=%d calls=%d body=%s", response.Code, gateway.calls, response.Body.String())
	}
}
