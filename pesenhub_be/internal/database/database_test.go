package database

import (
	"reflect"
	"testing"
)

func TestQueryRebindsRepeatedOrdinalPlaceholders(t *testing.T) {
	gotSQL, gotArgs := query("SELECT id FROM orders WHERE id=$1 OR client_order_id=$1", []any{"same-id"})
	wantSQL := "SELECT id FROM orders WHERE id=? OR client_order_id=?"
	wantArgs := []any{"same-id", "same-id"}
	if gotSQL != wantSQL || !reflect.DeepEqual(gotArgs, wantArgs) {
		t.Fatalf("query() = %q, %#v; want %q, %#v", gotSQL, gotArgs, wantSQL, wantArgs)
	}
}

func TestQueryExpandsAnySlice(t *testing.T) {
	gotSQL, gotArgs := query("SELECT id FROM orders WHERE status = ANY($1) AND source=$2", []any{[]string{"PENDING", "PAID"}, "WHATSAPP"})
	wantSQL := "SELECT id FROM orders WHERE status IN (?,?) AND source=?"
	wantArgs := []any{"PENDING", "PAID", "WHATSAPP"}
	if gotSQL != wantSQL || !reflect.DeepEqual(gotArgs, wantArgs) {
		t.Fatalf("query() = %q, %#v; want %q, %#v", gotSQL, gotArgs, wantSQL, wantArgs)
	}
}

func TestQueryTranslatesLegacyCastsAndConflict(t *testing.T) {
	gotSQL, gotArgs := query("INSERT INTO customers(id, preferences) VALUES($1::uuid, '{}'::jsonb) ON CONFLICT (id) DO NOTHING", []any{"customer-id"})
	wantSQL := "INSERT INTO customers(id, preferences) VALUES(?, '{}') ON DUPLICATE KEY UPDATE id=id"
	wantArgs := []any{"customer-id"}
	if gotSQL != wantSQL || !reflect.DeepEqual(gotArgs, wantArgs) {
		t.Fatalf("query() = %q, %#v; want %q, %#v", gotSQL, gotArgs, wantSQL, wantArgs)
	}
}
