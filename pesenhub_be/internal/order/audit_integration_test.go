package order

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/customer"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestOrderAuditLogIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	store := NewStore(db)
	svc := NewService(store)

	catID := "d1000000-0000-4000-8000-000000000001"
	menuID := "d2000000-0000-4000-8000-000000000001"
	_, _ = db.Exec(ctx, `INSERT INTO menu_categories (id, name, sort_order) VALUES ($1, 'Audit Category', 1) ON CONFLICT DO NOTHING`, catID)
	_, _ = db.Exec(ctx, `INSERT INTO menus (id, category_id, sku, name, price_amount, is_available, sort_order)
		VALUES ($1, $2, 'AUDIT-SKU', 'Audit Menu Item', 25000, true, 1) ON CONFLICT DO NOTHING`, menuID, catID)

	// 1. Create a cashier manual order
	idempotencyKey := "audit-key-" + time.Now().Format("20060102150405.000000")
	createIn := CreateInput{
		ClientOrderID: "d3000000-0000-4000-8000-000000000001",
		CustomerName:  "Audit Tester",
		CustomerPhone: "+6281234567890",
		Items: []ItemInput{
			{MenuID: menuID, Quantity: 1},
		},
	}

	order, isNew, err := svc.CreateManual(ctx, createIn, idempotencyKey, "staff-audit-1", "req-audit-1")
	if err != nil {
		t.Fatalf("failed to create order: %v", err)
	}
	if !isNew {
		t.Fatal("expected order to be newly created")
	}

	// Verify exactly 1 audit log created for ORDER_CREATED
	var count int
	err = db.QueryRow(ctx, `SELECT count(*) FROM audit_logs WHERE aggregate_type = 'ORDER' AND aggregate_id = $1 AND action = 'ORDER_CREATED'`, order.ID).Scan(&count)
	if err != nil {
		t.Fatalf("failed to count audit logs: %v", err)
	}
	if count != 1 {
		t.Fatalf("expected exactly 1 ORDER_CREATED audit log, got %d", count)
	}

	// Verify PII redaction in metadata_redacted: phone must be masked, no raw phone
	var metaJSON string
	err = db.QueryRow(ctx, `SELECT metadata_redacted::text FROM audit_logs WHERE aggregate_type = 'ORDER' AND aggregate_id = $1 AND action = 'ORDER_CREATED'`, order.ID).Scan(&metaJSON)
	if err != nil {
		t.Fatalf("failed to query metadata_redacted: %v", err)
	}
	if strings.Contains(metaJSON, "+6281234567890") {
		t.Fatalf("raw phone number leaked in audit log metadata: %s", metaJSON)
	}
	if !strings.Contains(metaJSON, "+62812****7890") {
		t.Fatalf("masked phone number not found in audit log metadata: %s", metaJSON)
	}

	// 2. Perform valid status transition (PENDING -> ACCEPTED)
	transKey := "audit-trans-" + time.Now().Format("20060102150405.000000")
	res, isNewTrans, err := svc.Transition(ctx, order.ID, TransitionInput{
		TargetStatus:    "ACCEPTED",
		ExpectedVersion: 1,
	}, transKey, "staff-audit-2", "STAFF", "req-audit-2")
	if err != nil {
		t.Fatalf("failed to transition status: %v", err)
	}
	if !isNewTrans || res.Status != "ACCEPTED" {
		t.Fatalf("unexpected transition result: %#v", res)
	}

	// Verify exactly 1 audit log created for ORDER_STATUS_CHANGED
	err = db.QueryRow(ctx, `SELECT count(*) FROM audit_logs WHERE aggregate_type = 'ORDER' AND aggregate_id = $1 AND action = 'ORDER_STATUS_CHANGED'`, order.ID).Scan(&count)
	if err != nil {
		t.Fatalf("failed to count transition audit logs: %v", err)
	}
	if count != 1 {
		t.Fatalf("expected exactly 1 ORDER_STATUS_CHANGED audit log, got %d", count)
	}

	// 3. Atomicity test: Failed transition (version conflict) leaves no phantom audit log
	_, _, err = svc.Transition(ctx, order.ID, TransitionInput{
		TargetStatus:    "PREPARING",
		ExpectedVersion: 999, // Wrong version triggers error & rollback
	}, transKey+"-fail", "staff-audit-3", "STAFF", "req-audit-3")
	if err != ErrVersionConflict {
		t.Fatalf("expected ErrVersionConflict, got %v", err)
	}

	// Count should still be 1 (no extra audit log added for failed transaction)
	err = db.QueryRow(ctx, `SELECT count(*) FROM audit_logs WHERE aggregate_type = 'ORDER' AND aggregate_id = $1 AND action = 'ORDER_STATUS_CHANGED'`, order.ID).Scan(&count)
	if err != nil {
		t.Fatalf("failed to count transition audit logs: %v", err)
	}
	if count != 1 {
		t.Fatalf("expected count 1 after failed transaction, got %d", count)
	}

	// 4. Query audit logs via service (STAFF role)
	staffPrincipal := customer.Principal{Subject: "staff-auditor", Role: "STAFF"}
	logs, err := svc.GetAuditLogs(ctx, order.ID, staffPrincipal, "req-audit-query-1")
	if err != nil {
		t.Fatalf("failed to get audit logs: %v", err)
	}

	// Should contain ORDER_CREATED, ORDER_STATUS_CHANGED, and the AUDIT_LOGS_ACCESSED log
	if len(logs) < 2 {
		t.Fatalf("expected at least 2 audit log entries, got %d", len(logs))
	}
	if logs[0].Action != "ORDER_CREATED" {
		t.Fatalf("expected first action ORDER_CREATED, got %s", logs[0].Action)
	}

	// 5. Querying audit logs again should reflect the AUDIT_LOGS_ACCESSED entry
	logs2, err := svc.GetAuditLogs(ctx, order.ID, staffPrincipal, "req-audit-query-2")
	if err != nil {
		t.Fatalf("failed to get audit logs second time: %v", err)
	}

	var hasAccessedAction bool
	for _, l := range logs2 {
		if l.Action == "AUDIT_LOGS_ACCESSED" {
			hasAccessedAction = true
			break
		}
	}
	if !hasAccessedAction {
		t.Fatal("expected AUDIT_LOGS_ACCESSED action to be recorded in audit logs")
	}

	// 6. Non-STAFF access is denied
	customerPrincipal := customer.Principal{Subject: "customer-1", Role: "CUSTOMER"}
	_, err = svc.GetAuditLogs(ctx, order.ID, customerPrincipal, "req-audit-query-denied")
	if err != customer.ErrUnauthorized {
		t.Fatalf("expected customer.ErrUnauthorized, got %v", err)
	}
}
