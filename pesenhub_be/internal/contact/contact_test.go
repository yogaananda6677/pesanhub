package contact

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestContactTypes(t *testing.T) {
	types := []string{TypeCustomer, TypeNonCustomer, TypeVendor, TypePersonal, TypeBlacklist}
	if len(types) != 5 {
		t.Errorf("expected 5 contact types, got %d", len(types))
	}
}

func TestHandler_Unauthorized(t *testing.T) {
	h := NewHandler(nil)
	req := httptest.NewRequest("GET", "/api/v1/contacts", nil)
	rec := httptest.NewRecorder()

	h.List(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Errorf("expected 403 Forbidden without staff header, got %d", rec.Code)
	}
}

func TestHandler_DecodeJSON(t *testing.T) {
	body := bytes.NewBufferString(`{"branch_id":"b-1","phone":"08123456789","contact_type":"NON_CUSTOMER"}`)
	req := httptest.NewRequest("POST", "/api/v1/contacts", body)

	var in UpsertContactInput
	err := decodeJSON(req, &in)
	if err != nil {
		t.Fatalf("unexpected error decoding JSON: %v", err)
	}

	if in.Phone != "08123456789" || in.ContactType != "NON_CUSTOMER" {
		t.Errorf("unexpected decoded values: %+v", in)
	}
}
