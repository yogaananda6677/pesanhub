package order

import (
	"context"
	"errors"
	"os"
	"sync"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
	"pesenhub/backend/internal/catalog"
)

func TestStoreCreateConcurrentIdempotencyIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx := context.Background()
	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	_, err = db.Exec(ctx, `INSERT INTO menu_categories(id,name) VALUES ('a1000000-0000-4000-8000-000000000001','Integration') ON CONFLICT DO NOTHING;
		INSERT INTO menus(id,category_id,sku,name,price_amount,is_available) VALUES ('a2000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','INTEGRATION-RICE','Integration Rice',15000,true) ON CONFLICT DO NOTHING;
		INSERT INTO modifier_groups(id,menu_id,code,name,min_select,max_select) VALUES ('a3000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000001','size','Size',1,1) ON CONFLICT DO NOTHING;
		INSERT INTO modifier_options(id,group_id,code,name,price_delta_amount,is_available) VALUES ('a4000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001','large','Large',5000,true) ON CONFLICT DO NOTHING`)
	if err != nil {
		t.Fatal(err)
	}
	in := CreateInput{
		ClientOrderID: "a5000000-0000-4000-8000-000000000001",
		CustomerName:  "Integration",
		Items: []ItemInput{{
			MenuID:   "a2000000-0000-4000-8000-000000000001",
			Quantity: 2,
			Selections: []catalog.Selection{{
				GroupID:   "a3000000-0000-4000-8000-000000000001",
				OptionIDs: []string{"a4000000-0000-4000-8000-000000000001"},
			}},
		}},
	}
	s := NewService(NewStore(db))
	var wg sync.WaitGroup
	ids := make(chan string, 2)
	errs := make(chan error, 2)
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			o, _, err := s.CreateManual(ctx, in, "integration-retry", "staff", "request")
			if err != nil {
				errs <- err
				return
			}
			ids <- o.ID
		}()
	}
	wg.Wait()
	close(ids)
	close(errs)
	for err := range errs {
		t.Fatal(err)
	}
	first := ""
	for id := range ids {
		if first == "" {
			first = id
		} else if first != id {
			t.Fatalf("different orders: %s %s", first, id)
		}
	}
	var orders, history, audits, outbox int
	if err = db.QueryRow(ctx, `SELECT (SELECT count(*) FROM orders WHERE idempotency_key='integration-retry'),(SELECT count(*) FROM order_status_history h JOIN orders o ON o.id=h.order_id WHERE o.idempotency_key='integration-retry'),(SELECT count(*) FROM audit_logs a JOIN orders o ON o.id=a.aggregate_id WHERE o.idempotency_key='integration-retry'),(SELECT count(*) FROM outbox_events e JOIN orders o ON o.id=e.aggregate_id WHERE o.idempotency_key='integration-retry')`).Scan(&orders, &history, &audits, &outbox); err != nil {
		t.Fatal(err)
	}
	if orders != 1 || history != 1 || audits != 1 || outbox != 1 {
		t.Fatalf("counts=%d/%d/%d/%d", orders, history, audits, outbox)
	}
	changed := in
	changed.Items = append([]ItemInput(nil), in.Items...)
	changed.Items[0].Quantity = 3
	if _, _, err = s.CreateManual(ctx, changed, "integration-retry", "staff", "request"); !errors.Is(err, ErrIdempotencyConflict) {
		t.Fatalf("expected conflict, got %v", err)
	}
	_, err = db.Exec(ctx, `UPDATE menus SET is_available=false WHERE id='a2000000-0000-4000-8000-000000000001'`)
	if err != nil {
		t.Fatal(err)
	}
	in.ClientOrderID = "a5000000-0000-4000-8000-000000000002"
	if _, _, err = s.CreateManual(ctx, in, "integration-unavailable", "staff", "request"); !errors.Is(err, catalog.ErrUnavailable) {
		t.Fatalf("expected unavailable, got %v", err)
	}
}
