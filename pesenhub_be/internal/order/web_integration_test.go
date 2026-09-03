package order

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	"pesenhub/backend/internal/catalog"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestCustomerWebOrderIntegration(t *testing.T) {
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
	catID := "b1000000-0000-4000-8000-000000000001"
	menuID := "b2000000-0000-4000-8000-000000000001"
	modGroupID := "b3000000-0000-4000-8000-000000000001"
	modOptID := "b4000000-0000-4000-8000-000000000001"

	if _, err = db.Exec(ctx, `INSERT INTO menu_categories (id, name, sort_order) VALUES ($1, 'Makanan Web', 1) ON CONFLICT DO NOTHING`, catID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(ctx, `INSERT INTO menus (id, category_id, sku, name, price_amount, is_available, sort_order)
		VALUES ($1, $2, 'NASGOR-WEB-TEST', 'Nasi Goreng Web', 20000, true, 1) ON CONFLICT DO NOTHING`, menuID, catID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(ctx, `INSERT INTO modifier_groups (id, menu_id, code, name, min_select, max_select, sort_order)
		VALUES ($1, $2, 'spice-web', 'Level Pedas', 0, 1, 1) ON CONFLICT DO NOTHING`, modGroupID, menuID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(ctx, `INSERT INTO modifier_options (id, group_id, code, name, price_delta_amount, sort_order)
		VALUES ($1, $2, 'extra-pedas', 'Extra Pedas', 2000, 1) ON CONFLICT DO NOTHING`, modOptID, modGroupID); err != nil {
		t.Fatal(err)
	}

	// 1. Preview order
	previewIn := []ItemInput{
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
	preview, err := svc.PreviewWeb(ctx, previewIn)
	if err != nil {
		t.Fatalf("preview error: %v", err)
	}
	expectedTotal := int64((20000 + 2000) * 2) // 44000
	if preview.TotalAmount != expectedTotal {
		t.Fatalf("expected preview total %d, got %d", expectedTotal, preview.TotalAmount)
	}

	// 2. Submit order with raw Indonesian phone 081234567890
	idempotencyKey := "web-test-key-" + time.Now().Format("20060102150405.000000")
	createIn := PublicOrderCreateInput{
		CustomerName:  "Citra Dewi",
		CustomerPhone: "081234567890",
		Notes:         "minta sendok",
		Items:         previewIn,
	}

	resp, isNew, err := svc.CreateWeb(ctx, createIn, idempotencyKey, "req-web-1")
	if err != nil {
		t.Fatalf("create web order error: %v", err)
	}
	if !isNew {
		t.Fatal("expected order to be newly created")
	}
	if !strings.HasPrefix(resp.PublicTrackingToken, "trk_") {
		t.Fatalf("expected tracking token prefix trk_, got %s", resp.PublicTrackingToken)
	}
	if resp.TotalAmount != expectedTotal {
		t.Fatalf("expected order total %d, got %d", expectedTotal, resp.TotalAmount)
	}
	if resp.Status != "PENDING" {
		t.Fatalf("expected status PENDING, got %s", resp.Status)
	}

	// Verify customer table has normalized phone (+6281234567890)
	var custPhone string
	err = db.QueryRow(ctx, `SELECT phone_e164 FROM customers WHERE phone_e164 = '+6281234567890'`).Scan(&custPhone)
	if err != nil {
		t.Fatalf("customer phone not found in database: %v", err)
	}

	// 3. Double-submit test: same key and payload returns identical response
	replayResp, isNew2, err := svc.CreateWeb(ctx, createIn, idempotencyKey, "req-web-replay")
	if err != nil {
		t.Fatalf("replay error: %v", err)
	}
	if isNew2 {
		t.Fatal("replay must not mark order as newly created")
	}
	if replayResp.OrderNumber != resp.OrderNumber || replayResp.PublicTrackingToken != resp.PublicTrackingToken {
		t.Fatalf("replay response mismatch: original=%#v, replay=%#v", resp, replayResp)
	}

	// 4. Double-submit with payload modification causes idempotency conflict
	conflictIn := createIn
	conflictIn.Notes = "berubah catatan"
	_, _, err = svc.CreateWeb(ctx, conflictIn, idempotencyKey, "req-web-conflict")
	if err != ErrIdempotencyConflict {
		t.Fatalf("expected ErrIdempotencyConflict, got %v", err)
	}

	// 5. Query public tracking detail by token
	tracking, err := svc.GetByPublicToken(ctx, resp.PublicTrackingToken)
	if err != nil {
		t.Fatalf("get by tracking token error: %v", err)
	}
	if tracking.OrderNumber != resp.OrderNumber {
		t.Fatalf("order number mismatch: %s vs %s", tracking.OrderNumber, resp.OrderNumber)
	}
	if tracking.CustomerName != "Citra Dewi" {
		t.Fatalf("customer name mismatch: got %s, want Citra Dewi", tracking.CustomerName)
	}
	if len(tracking.Items) != 1 || tracking.Items[0].Quantity != 2 {
		t.Fatalf("unexpected tracking items: %#v", tracking.Items)
	}

	// 6. Query with non-existent token returns ErrNotFound
	_, err = svc.GetByPublicToken(ctx, "trk_nonexistent")
	if err != ErrNotFound {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}
