package catalog

import (
	"context"
	"fmt"
	"testing"
)

type fakeRepo struct {
	categories        []Category
	menu              Menu
	availabilityCalls int
	lastMeta          MutationMeta
}

func (f *fakeRepo) CreateCategory(_ context.Context, c Category, meta MutationMeta) (Category, error) {
	f.lastMeta = meta
	f.categories = append(f.categories, c)
	return c, nil
}
func (f *fakeRepo) UpdateCategory(_ context.Context, c Category, version int64, meta MutationMeta) (Category, error) {
	f.lastMeta = meta
	c.Version = version + 1
	return c, nil
}
func (f *fakeRepo) CreateMenu(_ context.Context, m Menu, meta MutationMeta) (Menu, error) {
	f.lastMeta = meta
	f.menu = m
	return m, nil
}
func (f *fakeRepo) UpdateMenu(_ context.Context, m Menu, version int64, meta MutationMeta) (Menu, error) {
	f.lastMeta = meta
	m.Version = version + 1
	f.menu = m
	return m, nil
}
func (f *fakeRepo) SetMenuAvailability(_ context.Context, _ string, a bool, v int64, meta MutationMeta) (Menu, error) {
	f.lastMeta = meta
	f.availabilityCalls++
	return Menu{Available: a, Version: v + 1}, nil
}
func (f *fakeRepo) ListPublic(context.Context, string) ([]Category, error) { return f.categories, nil }
func (f *fakeRepo) ListAdmin(context.Context) ([]Category, error)          { return f.categories, nil }

func TestCreateMenuValidatesIntegerCatalog(t *testing.T) {
	n := 0
	s := NewService(&fakeRepo{}, func() string { n++; return string(rune('a' + n)) })
	m, err := s.CreateMenu(context.Background(), Menu{CategoryID: "c", SKU: "NASGOR", Name: "Nasi Goreng", PriceAmount: 15000, Groups: []Group{{Code: "spice", Name: "Pedas", MinSelect: 1, MaxSelect: 1, Options: []Option{{Code: "hot", Name: "Pedas"}}}}}, "staff", "request")
	if err != nil || m.PriceAmount != 15000 || m.Groups[0].Options[0].ID == "" {
		t.Fatalf("menu=%#v err=%v", m, err)
	}
}
func TestCreateMenuRejectsIllegalGroup(t *testing.T) {
	s := NewService(&fakeRepo{}, func() string { return "id" })
	for _, m := range []Menu{{CategoryID: "c", SKU: "A", Name: "A", PriceAmount: -1}, {CategoryID: "c", SKU: "A", Name: "A", Groups: []Group{{Code: "x", Name: "X", MinSelect: 2, MaxSelect: 1}}}, {CategoryID: "c", SKU: "A", Name: "A", Groups: []Group{{Code: "x", Name: "X", MinSelect: 1, MaxSelect: 1}}}} {
		if _, err := s.CreateMenu(context.Background(), m, "staff", "request"); err != ErrInvalidCatalog {
			t.Fatalf("menu=%#v err=%v", m, err)
		}
	}
}

func TestCatalogMutationsCarryVersionAndAuditMetadata(t *testing.T) {
	n := 0
	repo := &fakeRepo{}
	s := NewService(repo, func() string {
		n++
		return fmt.Sprintf("id-%d", n)
	})
	category, err := s.CreateCategory(context.Background(), Category{Name: " Minuman ", SortOrder: 2}, "outlet-user", "req-create")
	if err != nil || category.Version != 1 || !category.Active || len(category.Menus) != 0 {
		t.Fatalf("category=%#v err=%v", category, err)
	}
	if repo.lastMeta.ActorID != "outlet-user" || repo.lastMeta.RequestID != "req-create" || repo.lastMeta.AuditID == "" {
		t.Fatalf("meta=%#v", repo.lastMeta)
	}

	menu, err := s.UpdateMenu(context.Background(), "menu-1", Menu{
		CategoryID: category.ID, SKU: "TEH", Name: "Teh", PriceAmount: 8000,
		Groups: []Group{{Code: "sugar", Name: "Gula", MaxSelect: 1, Options: []Option{{Code: "normal", Name: "Normal"}}}},
	}, 4, "outlet-user", "req-update")
	if err != nil || menu.Version != 5 || menu.ID != "menu-1" || menu.Groups[0].ID == "" || menu.Groups[0].Options[0].ID == "" {
		t.Fatalf("menu=%#v err=%v", menu, err)
	}
}

func TestCatalogUpdateRejectsMissingExpectedVersion(t *testing.T) {
	s := NewService(&fakeRepo{}, func() string { return "id" })
	if _, err := s.UpdateCategory(context.Background(), "category", Category{Name: "Food"}, 0, "staff", "request"); err != ErrInvalidCatalog {
		t.Fatalf("expected invalid category version, got %v", err)
	}
}
