package catalog

import (
	"context"
	"fmt"

	"database/sql"
	dbx "pesenhub/backend/internal/database"
)

type Store struct{ db *dbx.Pool }

func NewStore(db *dbx.Pool) *Store { return &Store{db: db} }

func (s *Store) CreateCategory(ctx context.Context, c Category, meta MutationMeta) (Category, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Category{}, err
	}
	defer tx.Rollback(ctx)
	err = tx.QueryRow(ctx, `INSERT INTO menu_categories(id,name,sort_order,is_active,version) VALUES($1,$2,$3,$4,1) RETURNING id::text,name,sort_order,is_active,version`, c.ID, c.Name, c.SortOrder, c.Active).Scan(&c.ID, &c.Name, &c.SortOrder, &c.Active, &c.Version)
	if err != nil {
		return Category{}, err
	}
	if err = audit(ctx, tx, meta, "CATALOG_CATEGORY", c.ID, "CATEGORY_CREATED"); err != nil {
		return Category{}, err
	}
	return c, tx.Commit(ctx)
}

func (s *Store) UpdateCategory(ctx context.Context, c Category, expectedVersion int64, meta MutationMeta) (Category, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Category{}, err
	}
	defer tx.Rollback(ctx)
	err = tx.QueryRow(ctx, `UPDATE menu_categories SET name=$2,sort_order=$3,is_active=$4,version=version+1,updated_at=now() WHERE id=$1 AND version=$5 RETURNING id::text,name,sort_order,is_active,version`, c.ID, c.Name, c.SortOrder, c.Active, expectedVersion).Scan(&c.ID, &c.Name, &c.SortOrder, &c.Active, &c.Version)
	if err == sql.ErrNoRows {
		return Category{}, fmt.Errorf("%w", ErrVersionConflict)
	}
	if err != nil {
		return Category{}, err
	}
	if err = audit(ctx, tx, meta, "CATALOG_CATEGORY", c.ID, "CATEGORY_UPDATED"); err != nil {
		return Category{}, err
	}
	return c, tx.Commit(ctx)
}

func (s *Store) CreateMenu(ctx context.Context, m Menu, meta MutationMeta) (Menu, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Menu{}, err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `INSERT INTO menus(id,category_id,sku,name,description,product_type,image_url,price_amount,hpp_amount,is_available,version,sort_order) VALUES($1,$2,$3,$4,$5,$6,NULLIF($7,''),$8,$9,$10,1,$11)`, m.ID, m.CategoryID, m.SKU, m.Name, m.Description, m.ProductType, m.ImageURL, m.PriceAmount, m.HPPAmount, m.Available, m.SortOrder); err != nil {
		return Menu{}, err
	}
	if err = replaceChannelPrices(ctx, tx, m); err != nil {
		return Menu{}, err
	}
	if err = insertGroups(ctx, tx, m); err != nil {
		return Menu{}, err
	}
	if err = audit(ctx, tx, meta, "CATALOG_MENU", m.ID, "MENU_CREATED"); err != nil {
		return Menu{}, err
	}
	return m, tx.Commit(ctx)
}

func (s *Store) UpdateMenu(ctx context.Context, m Menu, expectedVersion int64, meta MutationMeta) (Menu, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Menu{}, err
	}
	defer tx.Rollback(ctx)
	err = tx.QueryRow(ctx, `UPDATE menus SET category_id=$2,sku=$3,name=$4,description=$5,product_type=$6,image_url=NULLIF($7,''),price_amount=$8,hpp_amount=$9,sort_order=$10,version=version+1,updated_at=now() WHERE id=$1 AND version=$11 RETURNING is_available,version`, m.ID, m.CategoryID, m.SKU, m.Name, m.Description, m.ProductType, m.ImageURL, m.PriceAmount, m.HPPAmount, m.SortOrder, expectedVersion).Scan(&m.Available, &m.Version)
	if err == sql.ErrNoRows {
		return Menu{}, fmt.Errorf("%w", ErrVersionConflict)
	}
	if err != nil {
		return Menu{}, err
	}
	if err = replaceChannelPrices(ctx, tx, m); err != nil {
		return Menu{}, err
	}
	if _, err = tx.Exec(ctx, `DELETE FROM modifier_groups WHERE menu_id=$1`, m.ID); err != nil {
		return Menu{}, err
	}
	if err = insertGroups(ctx, tx, m); err != nil {
		return Menu{}, err
	}
	if err = audit(ctx, tx, meta, "CATALOG_MENU", m.ID, "MENU_UPDATED"); err != nil {
		return Menu{}, err
	}
	return m, tx.Commit(ctx)
}

func (s *Store) SetMenuAvailability(ctx context.Context, id string, available bool, version int64, meta MutationMeta) (Menu, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Menu{}, err
	}
	defer tx.Rollback(ctx)
	var m Menu
	err = tx.QueryRow(ctx, `UPDATE menus SET is_available=$2,version=version+1,updated_at=now() WHERE id=$1 AND version=$3 RETURNING id::text,category_id::text,sku,name,COALESCE(description,''),product_type,COALESCE(image_url,''),price_amount,hpp_amount,is_available,version,sort_order`, id, available, version).Scan(&m.ID, &m.CategoryID, &m.SKU, &m.Name, &m.Description, &m.ProductType, &m.ImageURL, &m.PriceAmount, &m.HPPAmount, &m.Available, &m.Version, &m.SortOrder)
	if err == sql.ErrNoRows {
		return Menu{}, fmt.Errorf("%w", ErrVersionConflict)
	}
	if err != nil {
		return Menu{}, err
	}
	if m.ChannelPrices, err = loadChannelPricesTx(ctx, tx, m.ID); err != nil {
		return Menu{}, err
	}
	if err = audit(ctx, tx, meta, "CATALOG_MENU", m.ID, "MENU_AVAILABILITY_UPDATED"); err != nil {
		return Menu{}, err
	}
	return m, tx.Commit(ctx)
}

func insertGroups(ctx context.Context, tx *dbx.Tx, m Menu) error {
	for _, g := range m.Groups {
		if _, err := tx.Exec(ctx, `INSERT INTO modifier_groups(id,menu_id,code,name,min_select,max_select,is_active,sort_order) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, g.ID, m.ID, g.Code, g.Name, g.MinSelect, g.MaxSelect, g.Active, g.SortOrder); err != nil {
			return err
		}
		for _, o := range g.Options {
			if _, err := tx.Exec(ctx, `INSERT INTO modifier_options(id,group_id,code,name,price_delta_amount,is_available,sort_order) VALUES($1,$2,$3,$4,$5,$6,$7)`, o.ID, g.ID, o.Code, o.Name, o.PriceDeltaAmount, o.Available, o.SortOrder); err != nil {
				return err
			}
		}
	}
	return nil
}

func replaceChannelPrices(ctx context.Context, tx *dbx.Tx, m Menu) error {
	if _, err := tx.Exec(ctx, `DELETE FROM menu_channel_prices WHERE menu_id=$1`, m.ID); err != nil {
		return err
	}
	for _, price := range m.ChannelPrices {
		if _, err := tx.Exec(ctx, `INSERT INTO menu_channel_prices(menu_id,channel,amount) VALUES($1,$2,$3)`, m.ID, price.Channel, price.Amount); err != nil {
			return err
		}
	}
	return nil
}

func loadChannelPricesTx(ctx context.Context, tx *dbx.Tx, menuID string) ([]ChannelPrice, error) {
	rows, err := tx.Query(ctx, `SELECT channel,amount FROM menu_channel_prices WHERE menu_id=$1 ORDER BY FIELD(channel,'OFFLINE','GOFOOD','GRABFOOD','SHOPEEFOOD')`, menuID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	prices := []ChannelPrice{}
	for rows.Next() {
		var price ChannelPrice
		if err := rows.Scan(&price.Channel, &price.Amount); err != nil {
			return nil, err
		}
		prices = append(prices, price)
	}
	return prices, rows.Err()
}

func audit(ctx context.Context, tx *dbx.Tx, meta MutationMeta, aggregateType, aggregateID, action string) error {
	_, err := tx.Exec(ctx, `INSERT INTO audit_logs(id,aggregate_type,aggregate_id,action,actor_type,actor_id,request_id,metadata_redacted) VALUES($1,$2,$3,$4,'STAFF',$5,$6,'{}'::jsonb)`, meta.AuditID, aggregateType, aggregateID, action, meta.ActorID, meta.RequestID)
	return err
}

func (s *Store) ListPublic(ctx context.Context, categoryID string) ([]Category, error) {
	return s.list(ctx, categoryID, false)
}
func (s *Store) ListAdmin(ctx context.Context) ([]Category, error) { return s.list(ctx, "", true) }

func (s *Store) list(ctx context.Context, categoryID string, admin bool) ([]Category, error) {
	categorySQL := `SELECT id::text,name,sort_order,is_active,version FROM menu_categories WHERE ($1='' OR id::text=$1)`
	if !admin {
		categorySQL += ` AND is_active`
	}
	categorySQL += ` ORDER BY sort_order,name,id`
	rows, err := s.db.Query(ctx, categorySQL, categoryID)
	if err != nil {
		return nil, err
	}
	categories := []Category{}
	for rows.Next() {
		var c Category
		if err := rows.Scan(&c.ID, &c.Name, &c.SortOrder, &c.Active, &c.Version); err != nil {
			rows.Close()
			return nil, err
		}
		c.Menus = []Menu{}
		categories = append(categories, c)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	for ci := range categories {
		menuSQL := `SELECT id::text,category_id::text,sku,name,COALESCE(description,''),product_type,COALESCE(image_url,''),price_amount,hpp_amount,is_available,version,sort_order FROM menus WHERE category_id=$1`
		if !admin {
			menuSQL += ` AND is_available`
		}
		menuSQL += ` ORDER BY sort_order,name,id`
		menuRows, err := s.db.Query(ctx, menuSQL, categories[ci].ID)
		if err != nil {
			return nil, err
		}
		for menuRows.Next() {
			var m Menu
			if err := menuRows.Scan(&m.ID, &m.CategoryID, &m.SKU, &m.Name, &m.Description, &m.ProductType, &m.ImageURL, &m.PriceAmount, &m.HPPAmount, &m.Available, &m.Version, &m.SortOrder); err != nil {
				menuRows.Close()
				return nil, err
			}
			m.Groups = []Group{}
			categories[ci].Menus = append(categories[ci].Menus, m)
		}
		err = menuRows.Err()
		menuRows.Close()
		if err != nil {
			return nil, err
		}
		for mi := range categories[ci].Menus {
			priceRows, priceErr := s.db.Query(ctx, `SELECT channel,amount FROM menu_channel_prices WHERE menu_id=$1 ORDER BY FIELD(channel,'OFFLINE','GOFOOD','GRABFOOD','SHOPEEFOOD')`, categories[ci].Menus[mi].ID)
			if priceErr != nil {
				return nil, priceErr
			}
			prices := []ChannelPrice{}
			for priceRows.Next() {
				var price ChannelPrice
				if err := priceRows.Scan(&price.Channel, &price.Amount); err != nil {
					priceRows.Close()
					return nil, err
				}
				prices = append(prices, price)
			}
			priceErr = priceRows.Err()
			priceRows.Close()
			if priceErr != nil {
				return nil, priceErr
			}
			categories[ci].Menus[mi].ChannelPrices = prices
			if !admin {
				categories[ci].Menus[mi].HPPAmount = nil
			}
			if err := s.loadGroups(ctx, &categories[ci].Menus[mi], admin); err != nil {
				return nil, err
			}
		}
	}
	return categories, nil
}

func (s *Store) loadGroups(ctx context.Context, menu *Menu, admin bool) error {
	groupSQL := `SELECT id::text,code,name,min_select,max_select,sort_order,is_active FROM modifier_groups WHERE menu_id=$1`
	if !admin {
		groupSQL += ` AND is_active`
	}
	groupSQL += ` ORDER BY sort_order,name,id`
	rows, err := s.db.Query(ctx, groupSQL, menu.ID)
	if err != nil {
		return err
	}
	groups := []Group{}
	for rows.Next() {
		var g Group
		if err := rows.Scan(&g.ID, &g.Code, &g.Name, &g.MinSelect, &g.MaxSelect, &g.SortOrder, &g.Active); err != nil {
			rows.Close()
			return err
		}
		g.Options = []Option{}
		groups = append(groups, g)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for gi := range groups {
		optionSQL := `SELECT id::text,code,name,price_delta_amount,is_available,sort_order FROM modifier_options WHERE group_id=$1`
		if !admin {
			optionSQL += ` AND is_available`
		}
		optionSQL += ` ORDER BY sort_order,name,id`
		optionRows, err := s.db.Query(ctx, optionSQL, groups[gi].ID)
		if err != nil {
			return err
		}
		for optionRows.Next() {
			var o Option
			if err := optionRows.Scan(&o.ID, &o.Code, &o.Name, &o.PriceDeltaAmount, &o.Available, &o.SortOrder); err != nil {
				optionRows.Close()
				return err
			}
			groups[gi].Options = append(groups[gi].Options, o)
		}
		err = optionRows.Err()
		optionRows.Close()
		if err != nil {
			return err
		}
	}
	menu.Groups = groups
	return nil
}
