package order

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/customer"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestWhatsAppOrderValidation(t *testing.T) {
	svc := NewService(nil)

	// Nil store
	_, _, err := svc.CreateWhatsApp(context.Background(), WhatsAppOrderCreateInput{
		CustomerPhone: "08123456789",
		CustomerName:  "Test",
		Items:         []ItemInput{{MenuID: "11111111-1111-1111-1111-111111111111", Quantity: 1}},
	}, "test-key", "req-1")
	if err == nil || !strings.Contains(err.Error(), "not configured") {
		t.Fatalf("expected not configured error, got %v", err)
	}
}

func TestWhatsAppOrderIntegration(t *testing.T) {
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

	// Ensure test menu category and menu exist
	catID := customer.NewID()
	menuID := customer.NewID()
	modGroupID := customer.NewID()
	modOptID := customer.NewID()
	sku := "NASGOR-WA-" + customer.NewID()[:8]
	catName := "Makanan WA " + customer.NewID()[:6]

	if _, err = db.Exec(ctx, `INSERT INTO menu_categories (id, name, sort_order) VALUES ($1, $2, 1)`, catID, catName); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(ctx, `INSERT INTO menus (id, category_id, sku, name, price_amount, is_available, sort_order)
		VALUES ($1, $2, $3, 'Nasi Goreng WhatsApp', 22000, true, 1)`, menuID, catID, sku); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(ctx, `INSERT INTO modifier_groups (id, menu_id, code, name, min_select, max_select, sort_order)
		VALUES ($1, $2, 'spice-wa', 'Level Pedas WA', 0, 1, 1)`, modGroupID, menuID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(ctx, `INSERT INTO modifier_options (id, group_id, code, name, price_delta_amount, sort_order)
		VALUES ($1, $2, 'sedang-wa', 'Pedas Sedang', 1000, 1)`, modOptID, modGroupID); err != nil {
		t.Fatal(err)
	}

	items := []ItemInput{
		{
			MenuID:   menuID,
			Quantity: 2,
			Selections: []catalog.Selection{
				{
					GroupID:   modGroupID,
					OptionIDs: []string{modOptID},
				},
			},
		},
	}
	expectedTotal := int64((22000 + 1000) * 2) // 46000

	idempotencyKey := "wa-test-key-" + time.Now().Format("20060102150405.000000")
	createIn := WhatsAppOrderCreateInput{
		CustomerName:  "Andi WhatsApp",
		CustomerPhone: "08987654321",
		Notes:         "jangan terlalu asin",
		Items:         items,
	}

	// 1. Initial creation
	resp, isNew, err := svc.CreateWhatsApp(ctx, createIn, idempotencyKey, "req-wa-1")
	if err != nil {
		t.Fatalf("create whatsapp order error: %v", err)
	}
	if !isNew {
		t.Fatal("expected order to be newly created")
	}
	if !strings.HasPrefix(resp.OrderNumber, "ORD-") {
		t.Fatalf("expected order number prefix ORD-, got %s", resp.OrderNumber)
	}
	if !strings.HasPrefix(resp.PublicTrackingToken, "trk_") {
		t.Fatalf("expected tracking token prefix trk_, got %s", resp.PublicTrackingToken)
	}
	if resp.TotalAmount != expectedTotal {
		t.Fatalf("expected total %d, got %d", expectedTotal, resp.TotalAmount)
	}
	if resp.Status != "PENDING" {
		t.Fatalf("expected status PENDING, got %s", resp.Status)
	}

	// Verify database record constraints
	var dbSource, dbFulfillment, dbPhone string
	err = db.QueryRow(ctx, `SELECT source, fulfillment, customer_phone_snapshot FROM orders WHERE id = $1`, resp.ID).Scan(&dbSource, &dbFulfillment, &dbPhone)
	if err != nil {
		t.Fatalf("failed to query order: %v", err)
	}
	if dbSource != "WHATSAPP" {
		t.Fatalf("expected source WHATSAPP, got %s", dbSource)
	}
	if dbFulfillment != "PICKUP" {
		t.Fatalf("expected fulfillment PICKUP, got %s", dbFulfillment)
	}
	if dbPhone != "+628987654321" {
		t.Fatalf("expected phone +628987654321, got %s", dbPhone)
	}

	// 2. Retry with exact same idempotency key (idempotent duplicate delivery)
	resp2, isNew2, err := svc.CreateWhatsApp(ctx, createIn, idempotencyKey, "req-wa-2")
	if err != nil {
		t.Fatalf("retry whatsapp order error: %v", err)
	}
	if isNew2 {
		t.Fatal("expected order to NOT be newly created on retry")
	}
	if resp2.ID != resp.ID {
		t.Fatalf("expected same order ID %s, got %s", resp.ID, resp2.ID)
	}
	if resp2.OrderNumber != resp.OrderNumber {
		t.Fatalf("expected same order number %s, got %s", resp.OrderNumber, resp2.OrderNumber)
	}

	// 3. Conflict with different payload using same idempotency key
	conflictIn := createIn
	conflictIn.Notes = "catatan berbeda"
	_, _, err = svc.CreateWhatsApp(ctx, conflictIn, idempotencyKey, "req-wa-3")
	if !errors.Is(err, ErrIdempotencyConflict) {
		t.Fatalf("expected ErrIdempotencyConflict, got %v", err)
	}
}
