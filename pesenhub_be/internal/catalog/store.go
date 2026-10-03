package catalog

import (
	"context"
	"encoding/json"
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
	if _, err = tx.Exec(ctx, `
		INSERT IGNORE INTO branch_menu_availability (branch_id, menu_id, is_available, version)
		SELECT id, $1, $2, 1 FROM branches`, m.ID, m.Available); err != nil {
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

func (s *Store) SetMenuAvailability(ctx context.Context, branchID, id string, available bool, version int64, meta MutationMeta) (Menu, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Menu{}, err
	}
	defer tx.Rollback(ctx)

	// Ensure branch row exists
	_, err = tx.Exec(ctx, `
		INSERT INTO branch_menu_availability (branch_id, menu_id, is_available, version)
		SELECT $1, id, is_available, 1 FROM menus WHERE id = $2
		ON DUPLICATE KEY UPDATE branch_id = branch_id`, branchID, id)
	if err != nil {
		return Menu{}, err
	}

	res, err := tx.Exec(ctx, `
		UPDATE branch_menu_availability
		SET is_available = $3, version = version + 1, updated_at = now()
		WHERE branch_id = $1 AND menu_id = $2 AND version = $4`,
		branchID, id, available, version)
	if err != nil {
		return Menu{}, err
	}
	if res.RowsAffected() == 0 {
		var exists bool
		_ = tx.QueryRow(ctx, `SELECT true FROM menus WHERE id = $1`, id).Scan(&exists)
		if !exists {
			return Menu{}, ErrInvalidCatalog
		}
		return Menu{}, fmt.Errorf("%w", ErrVersionConflict)
	}

	var m Menu
	err = tx.QueryRow(ctx, `
		SELECT m.id::text, m.category_id::text, m.sku, m.name, COALESCE(m.description,''), m.product_type, COALESCE(m.image_url,''), m.price_amount, m.hpp_amount, bma.is_available, bma.version, m.sort_order
		FROM menus m
		JOIN branch_menu_availability bma ON bma.menu_id = m.id AND bma.branch_id = $1
		WHERE m.id = $2`, branchID, id).Scan(&m.ID, &m.CategoryID, &m.SKU, &m.Name, &m.Description, &m.ProductType, &m.ImageURL, &m.PriceAmount, &m.HPPAmount, &m.Available, &m.Version, &m.SortOrder)
	if err != nil {
		return Menu{}, err
	}

	if m.ChannelPrices, err = loadChannelPricesTx(ctx, tx, m.ID); err != nil {
		return Menu{}, err
	}
	availMeta, _ := json.Marshal(map[string]any{"branch_id": branchID, "menu_id": id, "is_available": available})
	if err = audit(ctx, tx, meta, "CATALOG_MENU", m.ID, "MENU_AVAILABILITY_UPDATED", availMeta); err != nil {
		return Menu{}, err
	}
	return m, tx.Commit(ctx)
}

func (s *Store) SetModifierOptionAvailability(ctx context.Context, branchID, id string, available bool, version int64, meta MutationMeta) (Option, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Option{}, err
	}
	defer tx.Rollback(ctx)

	// Ensure branch row exists
	_, err = tx.Exec(ctx, `
		INSERT INTO branch_modifier_option_availability (branch_id, modifier_option_id, is_available, version)
		SELECT $1, id, is_available, 1 FROM modifier_options WHERE id = $2
		ON DUPLICATE KEY UPDATE branch_id = branch_id`, branchID, id)
	if err != nil {
		return Option{}, err
	}

	res, err := tx.Exec(ctx, `
		UPDATE branch_modifier_option_availability
		SET is_available = $3, version = version + 1, updated_at = now()
		WHERE branch_id = $1 AND modifier_option_id = $2 AND version = $4`,
		branchID, id, available, version)
	if err != nil {
		return Option{}, err
	}
	if res.RowsAffected() == 0 {
		var exists bool
		_ = tx.QueryRow(ctx, `SELECT true FROM modifier_options WHERE id = $1`, id).Scan(&exists)
		if !exists {
			return Option{}, ErrInvalidCatalog
		}
		return Option{}, fmt.Errorf("%w", ErrVersionConflict)
	}

	var o Option
	err = tx.QueryRow(ctx, `
		SELECT o.id::text, o.code, o.name, o.price_delta_amount, bmoa.is_available, o.sort_order
		FROM modifier_options o
		JOIN branch_modifier_option_availability bmoa ON bmoa.modifier_option_id = o.id AND bmoa.branch_id = $1
		WHERE o.id = $2`, branchID, id).Scan(&o.ID, &o.Code, &o.Name, &o.PriceDeltaAmount, &o.Available, &o.SortOrder)
	if err != nil {
		return Option{}, err
	}

	modAvailMeta, _ := json.Marshal(map[string]any{"branch_id": branchID, "modifier_option_id": id, "is_available": available})
	if err = audit(ctx, tx, meta, "CATALOG_MODIFIER_OPTION", o.ID, "MODIFIER_OPTION_AVAILABILITY_UPDATED", modAvailMeta); err != nil {
		return Option{}, err
	}
	return o, tx.Commit(ctx)
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
			if _, err := tx.Exec(ctx, `
				INSERT IGNORE INTO branch_modifier_option_availability (branch_id, modifier_option_id, is_available, version)
				SELECT id, $1, $2, 1 FROM branches`, o.ID, o.Available); err != nil {
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

func audit(ctx context.Context, tx *dbx.Tx, meta MutationMeta, aggregateType, aggregateID, action string, payload ...[]byte) error {
	p := []byte("{}")
	if len(payload) > 0 && len(payload[0]) > 0 {
		p = payload[0]
	}
	_, err := tx.Exec(ctx, `INSERT INTO audit_logs(id,aggregate_type,aggregate_id,action,actor_type,actor_id,request_id,metadata_redacted) VALUES($1,$2,$3,$4,'STAFF',$5,$6,$7)`, meta.AuditID, aggregateType, aggregateID, action, meta.ActorID, meta.RequestID, p)
	return err
}

func (s *Store) ListPublic(ctx context.Context, categoryID string, branchID ...string) ([]Category, error) {
	bID := ""
	if len(branchID) > 0 {
		bID = branchID[0]
	}
	if bID == "" {
		_ = s.db.QueryRow(ctx, `SELECT id::text FROM branches WHERE is_default = true LIMIT 1`).Scan(&bID)
	}
	return s.list(ctx, categoryID, bID, false)
}
func (s *Store) ListAdmin(ctx context.Context, branchID ...string) ([]Category, error) {
	bID := ""
	if len(branchID) > 0 {
		bID = branchID[0]
	}
	return s.list(ctx, "", bID, true)
}

func (s *Store) list(ctx context.Context, categoryID, branchID string, admin bool) ([]Category, error) {
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
		menuSQL := `SELECT m.id::text,m.category_id::text,m.sku,m.name,COALESCE(m.description,''),m.product_type,COALESCE(m.image_url,''),m.price_amount,m.hpp_amount,COALESCE(bma.is_available, m.is_available),COALESCE(bma.version, m.version),m.sort_order 
FROM menus m 
LEFT JOIN branch_menu_availability bma ON bma.menu_id = m.id AND bma.branch_id = $2 
WHERE m.category_id=$1`
		if !admin {
			menuSQL += ` AND COALESCE(bma.is_available, m.is_available) = true`
		}
		menuSQL += ` ORDER BY m.sort_order,m.name,m.id`
		menuRows, err := s.db.Query(ctx, menuSQL, categories[ci].ID, branchID)
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
			if err := s.loadGroups(ctx, &categories[ci].Menus[mi], branchID, admin); err != nil {
				return nil, err
			}
		}
	}
	return categories, nil
}

func (s *Store) loadGroups(ctx context.Context, menu *Menu, branchID string, admin bool) error {
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
		optionSQL := `SELECT o.id::text,o.code,o.name,o.price_delta_amount,COALESCE(bmoa.is_available, o.is_available),o.sort_order 
FROM modifier_options o 
LEFT JOIN branch_modifier_option_availability bmoa ON bmoa.modifier_option_id = o.id AND bmoa.branch_id = $2 
WHERE o.group_id=$1`
		if !admin {
			optionSQL += ` AND COALESCE(bmoa.is_available, o.is_available) = true`
		}
		optionSQL += ` ORDER BY o.sort_order,o.name,o.id`
		optionRows, err := s.db.Query(ctx, optionSQL, groups[gi].ID, branchID)
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
