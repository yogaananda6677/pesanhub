package catalog

import (
	"context"
	"strings"
)

type Repository interface {
	CreateCategory(context.Context, Category, MutationMeta) (Category, error)
	UpdateCategory(context.Context, Category, int64, MutationMeta) (Category, error)
	CreateMenu(context.Context, Menu, MutationMeta) (Menu, error)
	UpdateMenu(context.Context, Menu, int64, MutationMeta) (Menu, error)
	SetMenuAvailability(context.Context, string, bool, int64, MutationMeta) (Menu, error)
	ListPublic(context.Context, string) ([]Category, error)
	ListAdmin(context.Context) ([]Category, error)
}

type Service struct {
	repo  Repository
	newID func() string
}

func NewService(repo Repository, newID func() string) *Service {
	return &Service{repo: repo, newID: newID}
}

func (s *Service) CreateCategory(ctx context.Context, c Category, actorID, requestID string) (Category, error) {
	c.Name = strings.TrimSpace(c.Name)
	if c.Name == "" || len(c.Name) > 100 || c.SortOrder < 0 {
		return Category{}, ErrInvalidCatalog
	}
	c.ID = s.newID()
	c.Active = true
	c.Version = 1
	c.Menus = []Menu{}
	return s.repo.CreateCategory(ctx, c, s.meta(actorID, requestID))
}

func (s *Service) CreateMenu(ctx context.Context, m Menu, actorID, requestID string) (Menu, error) {
	if err := s.prepareMenu(&m, true); err != nil {
		return Menu{}, err
	}
	return s.repo.CreateMenu(ctx, m, s.meta(actorID, requestID))
}

func (s *Service) UpdateCategory(ctx context.Context, id string, c Category, expectedVersion int64, actorID, requestID string) (Category, error) {
	c.Name = strings.TrimSpace(c.Name)
	if id == "" || c.Name == "" || len(c.Name) > 100 || c.SortOrder < 0 || expectedVersion < 1 {
		return Category{}, ErrInvalidCatalog
	}
	c.ID = id
	c.Menus = []Menu{}
	return s.repo.UpdateCategory(ctx, c, expectedVersion, s.meta(actorID, requestID))
}

func (s *Service) UpdateMenu(ctx context.Context, id string, m Menu, expectedVersion int64, actorID, requestID string) (Menu, error) {
	if id == "" || expectedVersion < 1 {
		return Menu{}, ErrInvalidCatalog
	}
	m.ID = id
	if err := s.prepareMenu(&m, false); err != nil {
		return Menu{}, err
	}
	return s.repo.UpdateMenu(ctx, m, expectedVersion, s.meta(actorID, requestID))
}

func (s *Service) prepareMenu(m *Menu, create bool) error {
	m.Name, m.SKU = strings.TrimSpace(m.Name), strings.TrimSpace(m.SKU)
	if m.CategoryID == "" || m.Name == "" || len(m.Name) > 160 || m.SKU == "" || len(m.SKU) > 64 || m.PriceAmount < 0 || m.SortOrder < 0 {
		return ErrInvalidCatalog
	}
	if create {
		m.ID = s.newID()
		m.Available = true
		m.Version = 1
	}
	groupCodes := map[string]struct{}{}
	for gi := range m.Groups {
		g := &m.Groups[gi]
		g.Code, g.Name = strings.TrimSpace(g.Code), strings.TrimSpace(g.Name)
		if g.Code == "" || g.Name == "" || g.MinSelect < 0 || g.MaxSelect < 1 || g.MaxSelect < g.MinSelect || g.SortOrder < 0 || len(g.Options) < g.MinSelect {
			return ErrInvalidCatalog
		}
		if _, ok := groupCodes[g.Code]; ok {
			return ErrInvalidCatalog
		}
		groupCodes[g.Code] = struct{}{}
		g.ID = s.newID()
		g.Active = true
		optionCodes := map[string]struct{}{}
		for oi := range g.Options {
			o := &g.Options[oi]
			o.Code, o.Name = strings.TrimSpace(o.Code), strings.TrimSpace(o.Name)
			if o.Code == "" || o.Name == "" || o.SortOrder < 0 {
				return ErrInvalidCatalog
			}
			if _, ok := optionCodes[o.Code]; ok {
				return ErrInvalidCatalog
			}
			optionCodes[o.Code] = struct{}{}
			o.ID = s.newID()
			o.Available = true
		}
	}
	return nil
}

func (s *Service) SetMenuAvailability(ctx context.Context, id string, available bool, version int64, actorID, requestID string) (Menu, error) {
	if id == "" || version < 1 {
		return Menu{}, ErrInvalidCatalog
	}
	return s.repo.SetMenuAvailability(ctx, id, available, version, s.meta(actorID, requestID))
}
func (s *Service) ListPublic(ctx context.Context, categoryID string) ([]Category, error) {
	return s.repo.ListPublic(ctx, categoryID)
}
func (s *Service) ListAdmin(ctx context.Context) ([]Category, error) {
	return s.repo.ListAdmin(ctx)
}

func (s *Service) meta(actorID, requestID string) MutationMeta {
	return MutationMeta{ActorID: actorID, RequestID: requestID, AuditID: s.newID()}
}
