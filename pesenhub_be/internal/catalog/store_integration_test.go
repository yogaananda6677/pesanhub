package catalog

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestCatalogCRUDVersionAndAuditIntegration(t *testing.T) {
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

	ids := []string{
		"c1320000-0000-4000-8000-000000000001", // category
		"c1320000-0000-4000-8000-000000000002", // create category audit
		"c1320000-0000-4000-8000-000000000003", // menu
		"c1320000-0000-4000-8000-000000000004", // group
		"c1320000-0000-4000-8000-000000000005", // option
		"c1320000-0000-4000-8000-000000000006", // create menu audit
		"c1320000-0000-4000-8000-000000000007", // update category audit
		"c1320000-0000-4000-8000-000000000008", // replacement group
		"c1320000-0000-4000-8000-000000000009", // replacement option
		"c1320000-0000-4000-8000-00000000000a", // update menu audit
		"c1320000-0000-4000-8000-00000000000b", // availability audit
		"c1320000-0000-4000-8000-00000000000c", // failed stale audit
	}
	_, _ = db.Exec(ctx, `DELETE FROM audit_logs WHERE id = ANY($1::uuid[])`, ids)
	_, _ = db.Exec(ctx, `DELETE FROM menus WHERE id=$1`, ids[2])
	_, _ = db.Exec(ctx, `DELETE FROM menu_categories WHERE id=$1`, ids[0])
	defer func() {
		_, _ = db.Exec(context.Background(), `DELETE FROM audit_logs WHERE id = ANY($1::uuid[])`, ids)
		_, _ = db.Exec(context.Background(), `DELETE FROM menus WHERE id=$1`, ids[2])
		_, _ = db.Exec(context.Background(), `DELETE FROM menu_categories WHERE id=$1`, ids[0])
	}()

	next := 0
	svc := NewService(NewStore(db), func() string {
		id := ids[next]
		next++
		return id
	})
	category, err := svc.CreateCategory(ctx, Category{Name: "Issue 132", SortOrder: 132}, "staff-132", "req-category")
	if err != nil || category.Version != 1 {
		t.Fatalf("create category=%#v err=%v", category, err)
	}
	menu, err := svc.CreateMenu(ctx, Menu{
		CategoryID: category.ID, SKU: "ISSUE-132", Name: "Menu E2E", PriceAmount: 18000,
		Groups: []Group{{Code: "size", Name: "Ukuran", MinSelect: 1, MaxSelect: 1, Options: []Option{{Code: "large", Name: "Besar", PriceDeltaAmount: 3000}}}},
	}, "staff-132", "req-menu")
	if err != nil || menu.Version != 1 {
		t.Fatalf("create menu=%#v err=%v", menu, err)
	}
	category, err = svc.UpdateCategory(ctx, category.ID, Category{Name: "Issue 132 Updated", SortOrder: 133, Active: true}, category.Version, "staff-132", "req-category-update")
	if err != nil || category.Version != 2 {
		t.Fatalf("update category=%#v err=%v", category, err)
	}
	menu, err = svc.UpdateMenu(ctx, menu.ID, Menu{
		CategoryID: category.ID, SKU: "ISSUE-132", Name: "Menu E2E Updated", PriceAmount: 19000,
		Groups: []Group{{Code: "size", Name: "Ukuran", MinSelect: 1, MaxSelect: 1, Options: []Option{{Code: "large", Name: "Besar", PriceDeltaAmount: 4000}}}},
	}, menu.Version, "staff-132", "req-menu-update")
	if err != nil || menu.Version != 2 || menu.PriceAmount != 19000 {
		t.Fatalf("update menu=%#v err=%v", menu, err)
	}
	updated, err := svc.SetMenuAvailability(ctx, menu.ID, false, menu.Version, "staff-132", "req-availability")
	if err != nil || updated.Available || updated.Version != 3 {
		t.Fatalf("availability=%#v err=%v", updated, err)
	}
	if _, err = svc.SetMenuAvailability(ctx, menu.ID, true, menu.Version, "staff-132", "req-stale"); !errors.Is(err, ErrVersionConflict) {
		t.Fatalf("expected version conflict, got %v", err)
	}

	admin, err := svc.ListAdmin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	foundUnavailable := false
	for _, c := range admin {
		for _, item := range c.Menus {
			if item.ID == menu.ID && !item.Available && len(item.Groups) == 1 && len(item.Groups[0].Options) == 1 {
				foundUnavailable = true
			}
		}
	}
	if !foundUnavailable {
		t.Fatal("admin catalog did not preserve unavailable menu and modifiers")
	}

	var audits, staleAudits int
	if err = db.QueryRow(ctx, `SELECT count(*) FROM audit_logs WHERE aggregate_id IN ($1,$2)`, category.ID, menu.ID).Scan(&audits); err != nil {
		t.Fatal(err)
	}
	if err = db.QueryRow(ctx, `SELECT count(*) FROM audit_logs WHERE id=$1`, ids[11]).Scan(&staleAudits); err != nil {
		t.Fatal(err)
	}
	if audits != 5 || staleAudits != 0 {
		t.Fatalf("audit counts successful=%d stale=%d", audits, staleAudits)
	}
}
