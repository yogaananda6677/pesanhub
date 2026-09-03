package catalog

import (
	"context"
	"testing"
)

type fakeRepo struct {
	categories        []Category
	menu              Menu
	availabilityCalls int
}

func (f *fakeRepo) CreateCategory(_ context.Context, c Category) (Category, error) {
	f.categories = append(f.categories, c)
	return c, nil
}
func (f *fakeRepo) CreateMenu(_ context.Context, m Menu) (Menu, error) { f.menu = m; return m, nil }
func (f *fakeRepo) SetMenuAvailability(_ context.Context, _ string, a bool, v int64) (Menu, error) {
	f.availabilityCalls++
	return Menu{Available: a, Version: v + 1}, nil
}
func (f *fakeRepo) ListPublic(context.Context, string) ([]Category, error) { return f.categories, nil }

func TestCreateMenuValidatesIntegerCatalog(t *testing.T) {
	n := 0
	s := NewService(&fakeRepo{}, func() string { n++; return string(rune('a' + n)) })
	m, err := s.CreateMenu(context.Background(), Menu{CategoryID: "c", SKU: "NASGOR", Name: "Nasi Goreng", PriceAmount: 15000, Groups: []Group{{Code: "spice", Name: "Pedas", MinSelect: 1, MaxSelect: 1, Options: []Option{{Code: "hot", Name: "Pedas"}}}}})
	if err != nil || m.PriceAmount != 15000 || m.Groups[0].Options[0].ID == "" {
		t.Fatalf("menu=%#v err=%v", m, err)
	}
}
func TestCreateMenuRejectsIllegalGroup(t *testing.T) {
	s := NewService(&fakeRepo{}, func() string { return "id" })
	for _, m := range []Menu{{CategoryID: "c", SKU: "A", Name: "A", PriceAmount: -1}, {CategoryID: "c", SKU: "A", Name: "A", Groups: []Group{{Code: "x", Name: "X", MinSelect: 2, MaxSelect: 1}}}, {CategoryID: "c", SKU: "A", Name: "A", Groups: []Group{{Code: "x", Name: "X", MinSelect: 1, MaxSelect: 1}}}} {
		if _, err := s.CreateMenu(context.Background(), m); err != ErrInvalidCatalog {
			t.Fatalf("menu=%#v err=%v", m, err)
		}
	}
}
