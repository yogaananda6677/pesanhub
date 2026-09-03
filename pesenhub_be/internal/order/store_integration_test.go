package order

import (
	"context"
	"errors"
	"os"
	"sync"
	"testing"

	"pesenhub/backend/internal/catalog"

	"github.com/jackc/pgx/v5/pgxpool"
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

	for _, step := range []struct {
		target  string
		version int64
		key     string
	}{{"ACCEPTED", 1, "status-accepted"}, {"PREPARING", 2, "status-preparing"}} {
		got, changed, err := s.Transition(ctx, first, TransitionInput{TargetStatus: step.target, ExpectedVersion: step.version}, step.key, "staff", "STAFF", "request")
		if err != nil || !changed || got.Version != step.version+1 {
			t.Fatalf("transition %#v got=%#v changed=%v err=%v", step, got, changed, err)
		}
	}
	transition := TransitionInput{TargetStatus: "READY_FOR_PICKUP", ExpectedVersion: 3}
	statusIDs := make(chan StatusResult, 2)
	statusErrs := make(chan error, 2)
	wg = sync.WaitGroup{}
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			got, _, err := s.Transition(ctx, first, transition, "status-ready", "staff", "STAFF", "request-ready")
			if err != nil {
				statusErrs <- err
				return
			}
			statusIDs <- got
		}()
	}
	wg.Wait()
	close(statusIDs)
	close(statusErrs)
	for err := range statusErrs {
		t.Fatal(err)
	}
	for got := range statusIDs {
		if got.Status != "READY_FOR_PICKUP" || got.Version != 4 {
			t.Fatalf("unexpected replay result: %#v", got)
		}
	}
	if _, _, err = s.Transition(ctx, first, transition, "status-ready", "other-staff", "STAFF", "request-ready"); !errors.Is(err, ErrIdempotencyConflict) {
		t.Fatalf("expected actor-scoped idempotency conflict, got %v", err)
	}
	var readyHistory, readyAudit, readyOutbox int
	if err = db.QueryRow(ctx, `SELECT (SELECT count(*) FROM order_status_history WHERE order_id=$1 AND order_version=4),(SELECT count(*) FROM audit_logs WHERE aggregate_id=$1 AND action='ORDER_STATUS_CHANGED'),(SELECT count(*) FROM outbox_events WHERE aggregate_id=$1 AND event_type='ORDER_STATUS_CHANGED')`, first).Scan(&readyHistory, &readyAudit, &readyOutbox); err != nil {
		t.Fatal(err)
	}
	if readyHistory != 1 || readyAudit != 3 || readyOutbox != 3 {
		t.Fatalf("lifecycle counts=%d/%d/%d", readyHistory, readyAudit, readyOutbox)
	}
	if _, _, err = s.Transition(ctx, first, TransitionInput{TargetStatus: "COMPLETED", ExpectedVersion: 3}, "status-stale", "staff", "STAFF", "request"); !errors.Is(err, ErrVersionConflict) {
		t.Fatalf("expected stale version, got %v", err)
	}
	if _, _, err = s.Transition(ctx, first, TransitionInput{TargetStatus: "CANCELLED", ExpectedVersion: 4}, "status-illegal", "staff", "STAFF", "request"); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("expected invalid transition, got %v", err)
	}
	completed, completedChanged, err := s.Transition(ctx, first, TransitionInput{TargetStatus: "COMPLETED", ExpectedVersion: 4}, "status-completed", "staff", "STAFF", "request")
	if err != nil || !completedChanged || completed.Version != 5 {
		t.Fatalf("complete got=%#v changed=%v err=%v", completed, completedChanged, err)
	}
	if _, _, err = s.Transition(ctx, first, TransitionInput{TargetStatus: "ACCEPTED", ExpectedVersion: 5}, "status-terminal", "staff", "STAFF", "request"); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("expected terminal transition rejection, got %v", err)
	}
}
