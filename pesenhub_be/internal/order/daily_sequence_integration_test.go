package order

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/customer"
	dbx "pesenhub/backend/internal/database"
)

func TestDailyOrderSequenceAndClientOrderIDIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx := context.Background()
	db, err := dbx.Open(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	branchID := "b0000000-0000-0000-0000-000000000001"
	branchCode := "BWX"

	tx, err := db.BeginTx(ctx, dbx.TxOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)

	num1, err := nextDailyOrderNumber(ctx, tx, branchID, branchCode)
	if err != nil {
		t.Fatalf("nextDailyOrderNumber 1 failed: %v", err)
	}
	num2, err := nextDailyOrderNumber(ctx, tx, branchID, branchCode)
	if err != nil {
		t.Fatalf("nextDailyOrderNumber 2 failed: %v", err)
	}

	loc, _ := time.LoadLocation("Asia/Jakarta")
	dateCompact := time.Now().In(loc).Format("20060102")

	if !strings.HasPrefix(num1, "BWX-"+dateCompact+"-") {
		t.Fatalf("expected prefix BWX-%s-, got %s", dateCompact, num1)
	}
	if !strings.HasPrefix(num2, "BWX-"+dateCompact+"-") {
		t.Fatalf("expected prefix BWX-%s-, got %s", dateCompact, num2)
	}

	// Verify that num2 sequence is greater than num1 sequence
	if num1 >= num2 {
		t.Fatalf("expected num2 (%s) > num1 (%s)", num2, num1)
	}

	// Test order creation and transition by client_order_id
	clientOrderID := customer.NewID()
	key := "test-seq-" + customer.NewID()

	// Direct insert an order with client_order_id
	orderNum := num1
	_, err = tx.Exec(ctx, `INSERT INTO orders (id, order_number, branch_id, source, status, customer_name_snapshot, subtotal_amount, total_amount, idempotency_key, client_order_id, version)
		VALUES ($1, $2, $3::uuid, 'CASHIER_MANUAL', 'PENDING', 'Tester', 20000, 20000, $4, $5, 1)`,
		clientOrderID, orderNum, branchID, key, clientOrderID)
	if err != nil {
		t.Fatalf("insert order failed: %v", err)
	}

	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}

	store := NewStore(db)

	// Lookup by client_order_id via GetByID
	detail, err := store.GetByID(ctx, clientOrderID)
	if err != nil {
		t.Fatalf("GetByID with client_order_id failed: %v", err)
	}
	if detail.OrderNumber != orderNum {
		t.Fatalf("expected order number %s, got %s", orderNum, detail.OrderNumber)
	}

	// Transition by client_order_id
	res, isNew, err := store.Transition(ctx, clientOrderID, TransitionInput{
		TargetStatus:    "PREPARING",
		ExpectedVersion: 1,
	}, "trans-key-"+clientOrderID, strings.Repeat("b", 64), "staff-1", "STAFF|req-1")
	if err != nil {
		t.Fatalf("Transition by client_order_id failed: %v", err)
	}
	if !isNew || res.Status != "PREPARING" || res.Version != 2 {
		t.Fatalf("unexpected transition result: %#v", res)
	}
}
