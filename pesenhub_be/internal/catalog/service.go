package catalog

import (
	"context"
	"strings"
)

type Repository interface {
	CreateCategory(context.Context, Category) (Category, error)
	CreateMenu(context.Context, Menu) (Menu, error)
	SetMenuAvailability(context.Context, string, bool, int64) (Menu, error)
	ListPublic(context.Context, string) ([]Category, error)
}

type Service struct {
	repo  Repository
	newID func() string
}

func NewService(repo Repository, newID func() string) *Service {
	return &Service{repo: repo, newID: newID}
}

func (s *Service) CreateCategory(ctx context.Context, c Category) (Category, error) {
	c.Name = strings.TrimSpace(c.Name)
	if c.Name == "" || len(c.Name) > 100 || c.SortOrder < 0 {
		return Category{}, ErrInvalidCatalog
	}
	c.ID = s.newID()
	c.Active = true
	return s.repo.CreateCategory(ctx, c)
}

func (s *Service) CreateMenu(ctx context.Context, m Menu) (Menu, error) {
	m.Name, m.SKU = strings.TrimSpace(m.Name), strings.TrimSpace(m.SKU)
	if m.CategoryID == "" || m.Name == "" || len(m.Name) > 160 || m.SKU == "" || len(m.SKU) > 64 || m.PriceAmount < 0 || m.SortOrder < 0 {
		return Menu{}, ErrInvalidCatalog
	}
	m.ID = s.newID()
	m.Available = true
	m.Version = 1
	groupCodes := map[string]struct{}{}
	for gi := range m.Groups {
		g := &m.Groups[gi]
		g.Code, g.Name = strings.TrimSpace(g.Code), strings.TrimSpace(g.Name)
		if g.Code == "" || g.Name == "" || g.MinSelect < 0 || g.MaxSelect < 1 || g.MaxSelect < g.MinSelect || g.SortOrder < 0 || len(g.Options) < g.MinSelect {
			return Menu{}, ErrInvalidCatalog
		}
		if _, ok := groupCodes[g.Code]; ok {
			return Menu{}, ErrInvalidCatalog
		}
		groupCodes[g.Code] = struct{}{}
		g.ID = s.newID()
		g.Active = true
		optionCodes := map[string]struct{}{}
		for oi := range g.Options {
			o := &g.Options[oi]
			o.Code, o.Name = strings.TrimSpace(o.Code), strings.TrimSpace(o.Name)
			if o.Code == "" || o.Name == "" || o.SortOrder < 0 {
				return Menu{}, ErrInvalidCatalog
			}
			if _, ok := optionCodes[o.Code]; ok {
				return Menu{}, ErrInvalidCatalog
			}
			optionCodes[o.Code] = struct{}{}
			o.ID = s.newID()
			o.Available = true
		}
	}
	return s.repo.CreateMenu(ctx, m)
}

func (s *Service) SetMenuAvailability(ctx context.Context, id string, available bool, version int64) (Menu, error) {
	if id == "" || version < 1 {
		return Menu{}, ErrInvalidCatalog
	}
	return s.repo.SetMenuAvailability(ctx, id, available, version)
}
func (s *Service) ListPublic(ctx context.Context, categoryID string) ([]Category, error) {
	return s.repo.ListPublic(ctx, categoryID)
}
