package catalog

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Store struct{ db *pgxpool.Pool }

func NewStore(db *pgxpool.Pool) *Store { return &Store{db: db} }

func (s *Store) CreateCategory(ctx context.Context, c Category) (Category, error) {
	err := s.db.QueryRow(ctx, `INSERT INTO menu_categories(id,name,sort_order,is_active) VALUES($1,$2,$3,$4) RETURNING id::text,name,sort_order,is_active`, c.ID, c.Name, c.SortOrder, c.Active).Scan(&c.ID, &c.Name, &c.SortOrder, &c.Active)
	return c, err
}

func (s *Store) CreateMenu(ctx context.Context, m Menu) (Menu, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Menu{}, err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `INSERT INTO menus(id,category_id,sku,name,description,price_amount,is_available,sort_order) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, m.ID, m.CategoryID, m.SKU, m.Name, m.Description, m.PriceAmount, m.Available, m.SortOrder); err != nil {
		return Menu{}, err
	}
	for _, g := range m.Groups {
		if _, err = tx.Exec(ctx, `INSERT INTO modifier_groups(id,menu_id,code,name,min_select,max_select,is_active,sort_order) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, g.ID, m.ID, g.Code, g.Name, g.MinSelect, g.MaxSelect, g.Active, g.SortOrder); err != nil {
			return Menu{}, err
		}
		for _, o := range g.Options {
			if _, err = tx.Exec(ctx, `INSERT INTO modifier_options(id,group_id,code,name,price_delta_amount,is_available,sort_order) VALUES($1,$2,$3,$4,$5,$6,$7)`, o.ID, g.ID, o.Code, o.Name, o.PriceDeltaAmount, o.Available, o.SortOrder); err != nil {
				return Menu{}, err
			}
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return Menu{}, err
	}
	return m, nil
}

func (s *Store) SetMenuAvailability(ctx context.Context, id string, available bool, version int64) (Menu, error) {
	var m Menu
	err := s.db.QueryRow(ctx, `UPDATE menus SET is_available=$2,version=version+1,updated_at=now() WHERE id=$1 AND version=$3 RETURNING id::text,category_id::text,sku,name,description,price_amount,is_available,version,sort_order`, id, available, version).Scan(&m.ID, &m.CategoryID, &m.SKU, &m.Name, &m.Description, &m.PriceAmount, &m.Available, &m.Version, &m.SortOrder)
	if err == pgx.ErrNoRows {
		return Menu{}, fmt.Errorf("%w", ErrVersionConflict)
	}
	return m, err
}

func (s *Store) ListPublic(ctx context.Context, categoryID string) ([]Category, error) {
	rows, err := s.db.Query(ctx, `SELECT c.id::text,c.name,c.sort_order,m.id::text,m.sku,m.name,COALESCE(m.description,''),m.price_amount,m.version,m.sort_order FROM menu_categories c JOIN menus m ON m.category_id=c.id WHERE c.is_active AND m.is_available AND ($1='' OR c.id::text=$1) ORDER BY c.sort_order,c.name,c.id,m.sort_order,m.name,m.id`, categoryID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	categories := []Category{}
	indexes := map[string]int{}
	menuIndexes := map[string][2]int{}
	for rows.Next() {
		var c Category
		var m Menu
		if err := rows.Scan(&c.ID, &c.Name, &c.SortOrder, &m.ID, &m.SKU, &m.Name, &m.Description, &m.PriceAmount, &m.Version, &m.SortOrder); err != nil {
			return nil, err
		}
		m.CategoryID, m.Available, m.Groups = c.ID, true, []Group{}
		ci, ok := indexes[c.ID]
		if !ok {
			ci = len(categories)
			indexes[c.ID] = ci
			c.Active = true
			c.Menus = []Menu{}
			categories = append(categories, c)
		}
		categories[ci].Menus = append(categories[ci].Menus, m)
		menuIndexes[m.ID] = [2]int{ci, len(categories[ci].Menus) - 1}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	groupRows, err := s.db.Query(ctx, `SELECT g.id::text,g.menu_id::text,g.code,g.name,g.min_select,g.max_select,g.sort_order,o.id::text,o.code,o.name,o.price_delta_amount,o.sort_order FROM modifier_groups g JOIN modifier_options o ON o.group_id=g.id WHERE g.is_active AND o.is_available ORDER BY g.menu_id,g.sort_order,g.name,g.id,o.sort_order,o.name,o.id`)
	if err != nil {
		return nil, err
	}
	defer groupRows.Close()
	groupIndexes := map[string][3]int{}
	for groupRows.Next() {
		var g Group
		var menuID string
		var o Option
		if err := groupRows.Scan(&g.ID, &menuID, &g.Code, &g.Name, &g.MinSelect, &g.MaxSelect, &g.SortOrder, &o.ID, &o.Code, &o.Name, &o.PriceDeltaAmount, &o.SortOrder); err != nil {
			return nil, err
		}
		mi, ok := menuIndexes[menuID]
		if !ok {
			continue
		}
		g.Active = true
		o.Available = true
		gi, ok := groupIndexes[g.ID]
		if !ok {
			menu := &categories[mi[0]].Menus[mi[1]]
			g.Options = []Option{}
			menu.Groups = append(menu.Groups, g)
			gi = [3]int{mi[0], mi[1], len(menu.Groups) - 1}
			groupIndexes[g.ID] = gi
		}
		categories[gi[0]].Menus[gi[1]].Groups[gi[2]].Options = append(categories[gi[0]].Menus[gi[1]].Groups[gi[2]].Options, o)
	}
	return categories, groupRows.Err()
}
