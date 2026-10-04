package discount

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"pesenhub/backend/internal/customer"
	dbx "pesenhub/backend/internal/database"
)

type Store struct {
	db *dbx.Pool
}

func NewStore(db *dbx.Pool) *Store {
	return &Store{db: db}
}

func (s *Store) List(ctx context.Context, filter DiscountFilter) ([]Discount, error) {
	q := `SELECT d.id, d.name, d.code, d.scope, d.channel, d.type, d.value, d.max_discount_amount, d.min_order_amount,
	             d.branch_id, COALESCE(b.name, ''), d.is_active, d.start_time, d.end_time, d.version, d.created_at, d.updated_at
	      FROM discounts d
	      LEFT JOIN branches b ON d.branch_id = b.id
	      WHERE 1=1`

	var args []any
	argIdx := 1

	if filter.ActiveOnly {
		q += fmt.Sprintf(" AND d.is_active = $%d", argIdx)
		args = append(args, true)
		argIdx++
	}

	if filter.Channel != "" {
		q += fmt.Sprintf(" AND (d.channel = 'ALL' OR d.channel = $%d)", argIdx)
		args = append(args, filter.Channel)
		argIdx++
	}

	if filter.BranchID != "" {
		q += fmt.Sprintf(" AND (d.branch_id IS NULL OR d.branch_id = $%d)", argIdx)
		args = append(args, filter.BranchID)
		argIdx++
	}

	if filter.Scope != "" {
		q += fmt.Sprintf(" AND d.scope = $%d", argIdx)
		args = append(args, filter.Scope)
		argIdx++
	}

	if filter.Query != "" {
		q += fmt.Sprintf(" AND (LOWER(d.name) LIKE $%d OR LOWER(COALESCE(d.code, '')) LIKE $%d)", argIdx, argIdx)
		args = append(args, "%"+strings.ToLower(filter.Query)+"%")
		argIdx++
	}

	q += " ORDER BY d.created_at DESC"

	rows, err := s.db.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var discounts []Discount
	var discIDs []string

	for rows.Next() {
		var d Discount
		var code sql.NullString
		var branchID sql.NullString
		var startTime sql.NullTime
		var endTime sql.NullTime

		if err := rows.Scan(
			&d.ID, &d.Name, &code, &d.Scope, &d.Channel, &d.Type, &d.Value,
			&d.MaxDiscountAmount, &d.MinOrderAmount, &branchID, &d.BranchName,
			&d.IsActive, &startTime, &endTime, &d.Version, &d.CreatedAt, &d.UpdatedAt,
		); err != nil {
			return nil, err
		}

		if code.Valid {
			d.Code = &code.String
		}
		if branchID.Valid {
			d.BranchID = &branchID.String
		}
		if startTime.Valid {
			d.StartTime = &startTime.Time
		}
		if endTime.Valid {
			d.EndTime = &endTime.Time
		}

		discounts = append(discounts, d)
		discIDs = append(discIDs, d.ID)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	if len(discIDs) > 0 {
		menuMap, err := s.loadDiscountMenus(ctx, discIDs)
		if err != nil {
			return nil, err
		}
		for i := range discounts {
			if menus, ok := menuMap[discounts[i].ID]; ok {
				discounts[i].MenuIDs = menus
			} else {
				discounts[i].MenuIDs = []string{}
			}
		}
	}

	return discounts, nil
}

func (s *Store) loadDiscountMenus(ctx context.Context, discIDs []string) (map[string][]string, error) {
	result := make(map[string][]string)
	if len(discIDs) == 0 {
		return result, nil
	}

	rows, err := s.db.Query(ctx, `SELECT discount_id, menu_id FROM discount_menus WHERE discount_id = ANY($1)`, discIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var dID, mID string
		if err := rows.Scan(&dID, &mID); err != nil {
			return nil, err
		}
		result[dID] = append(result[dID], mID)
	}
	return result, rows.Err()
}

func (s *Store) GetByID(ctx context.Context, id string) (*Discount, error) {
	q := `SELECT d.id, d.name, d.code, d.scope, d.channel, d.type, d.value, d.max_discount_amount, d.min_order_amount,
	             d.branch_id, COALESCE(b.name, ''), d.is_active, d.start_time, d.end_time, d.version, d.created_at, d.updated_at
	      FROM discounts d
	      LEFT JOIN branches b ON d.branch_id = b.id
	      WHERE d.id = $1`

	var d Discount
	var code sql.NullString
	var branchID sql.NullString
	var startTime sql.NullTime
	var endTime sql.NullTime

	err := s.db.QueryRow(ctx, q, id).Scan(
		&d.ID, &d.Name, &code, &d.Scope, &d.Channel, &d.Type, &d.Value,
		&d.MaxDiscountAmount, &d.MinOrderAmount, &branchID, &d.BranchName,
		&d.IsActive, &startTime, &endTime, &d.Version, &d.CreatedAt, &d.UpdatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrDiscountNotFound
	}
	if err != nil {
		return nil, err
	}

	if code.Valid {
		d.Code = &code.String
	}
	if branchID.Valid {
		d.BranchID = &branchID.String
	}
	if startTime.Valid {
		d.StartTime = &startTime.Time
	}
	if endTime.Valid {
		d.EndTime = &endTime.Time
	}

	rows, err := s.db.Query(ctx, `SELECT menu_id FROM discount_menus WHERE discount_id = $1`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	d.MenuIDs = []string{}
	for rows.Next() {
		var mID string
		if err := rows.Scan(&mID); err != nil {
			return nil, err
		}
		d.MenuIDs = append(d.MenuIDs, mID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return &d, nil
}

func (s *Store) Create(ctx context.Context, in CreateDiscountInput) (*Discount, error) {
	name := strings.TrimSpace(in.Name)
	if name == "" {
		return nil, fmt.Errorf("%w: name is required", ErrInvalidInput)
	}

	scope := strings.ToUpper(strings.TrimSpace(in.Scope))
	if scope != ScopeOrder && scope != ScopeItem {
		return nil, fmt.Errorf("%w: invalid scope %s", ErrInvalidInput, in.Scope)
	}

	channel := strings.ToUpper(strings.TrimSpace(in.Channel))
	if channel == "" {
		channel = ChannelAll
	}

	discType := strings.ToUpper(strings.TrimSpace(in.Type))
	if discType != TypePercentage && discType != TypeFixed {
		return nil, fmt.Errorf("%w: invalid type %s", ErrInvalidInput, in.Type)
	}

	if in.Value <= 0 {
		return nil, fmt.Errorf("%w: value must be greater than zero", ErrInvalidInput)
	}
	if discType == TypePercentage && in.Value > 100 {
		return nil, fmt.Errorf("%w: percentage value cannot exceed 100", ErrInvalidInput)
	}

	if scope == ScopeItem && len(in.MenuIDs) == 0 {
		return nil, fmt.Errorf("%w: menu_ids required for item scope discount", ErrInvalidInput)
	}

	isActive := true
	if in.IsActive != nil {
		isActive = *in.IsActive
	}

	id := customer.NewID()
	var codeVal any
	if in.Code != nil && strings.TrimSpace(*in.Code) != "" {
		codeVal = strings.ToUpper(strings.TrimSpace(*in.Code))
	}

	var branchVal any
	if in.BranchID != nil && strings.TrimSpace(*in.BranchID) != "" {
		branchVal = strings.TrimSpace(*in.BranchID)
	}

	tx, err := s.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	insertQ := `INSERT INTO discounts (id, name, code, scope, channel, type, value, max_discount_amount, min_order_amount, branch_id, is_active, start_time, end_time, version)
	            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, 1)`

	if _, err := tx.Exec(ctx, insertQ,
		id, name, codeVal, scope, channel, discType, in.Value,
		in.MaxDiscountAmount, in.MinOrderAmount, branchVal, isActive,
		in.StartTime, in.EndTime,
	); err != nil {
		return nil, err
	}

	if scope == ScopeItem && len(in.MenuIDs) > 0 {
		for _, mID := range in.MenuIDs {
			mID = strings.TrimSpace(mID)
			if mID == "" {
				continue
			}
			if _, err := tx.Exec(ctx, `INSERT INTO discount_menus (discount_id, menu_id) VALUES ($1, $2)`, id, mID); err != nil {
				return nil, err
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return s.GetByID(ctx, id)
}

func (s *Store) Update(ctx context.Context, id string, in UpdateDiscountInput) (*Discount, error) {
	name := strings.TrimSpace(in.Name)
	if name == "" {
		return nil, fmt.Errorf("%w: name is required", ErrInvalidInput)
	}

	scope := strings.ToUpper(strings.TrimSpace(in.Scope))
	if scope != ScopeOrder && scope != ScopeItem {
		return nil, fmt.Errorf("%w: invalid scope %s", ErrInvalidInput, in.Scope)
	}

	channel := strings.ToUpper(strings.TrimSpace(in.Channel))
	if channel == "" {
		channel = ChannelAll
	}

	discType := strings.ToUpper(strings.TrimSpace(in.Type))
	if discType != TypePercentage && discType != TypeFixed {
		return nil, fmt.Errorf("%w: invalid type %s", ErrInvalidInput, in.Type)
	}

	if in.Value <= 0 {
		return nil, fmt.Errorf("%w: value must be greater than zero", ErrInvalidInput)
	}
	if discType == TypePercentage && in.Value > 100 {
		return nil, fmt.Errorf("%w: percentage value cannot exceed 100", ErrInvalidInput)
	}

	if scope == ScopeItem && len(in.MenuIDs) == 0 {
		return nil, fmt.Errorf("%w: menu_ids required for item scope discount", ErrInvalidInput)
	}

	var codeVal any
	if in.Code != nil && strings.TrimSpace(*in.Code) != "" {
		codeVal = strings.ToUpper(strings.TrimSpace(*in.Code))
	}

	var branchVal any
	if in.BranchID != nil && strings.TrimSpace(*in.BranchID) != "" {
		branchVal = strings.TrimSpace(*in.BranchID)
	}

	tx, err := s.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	updateQ := `UPDATE discounts
	            SET name = $1, code = $2, scope = $3, channel = $4, type = $5, value = $6,
	                max_discount_amount = $7, min_order_amount = $8, branch_id = $9,
	                is_active = COALESCE($10, is_active), start_time = $11, end_time = $12,
	                version = version + 1
	            WHERE id = $13`
	args := []any{
		name, codeVal, scope, channel, discType, in.Value,
		in.MaxDiscountAmount, in.MinOrderAmount, branchVal,
		in.IsActive, in.StartTime, in.EndTime, id,
	}

	if in.ExpectedVersion > 0 {
		updateQ += " AND version = $14"
		args = append(args, in.ExpectedVersion)
	}

	res, err := tx.Exec(ctx, updateQ, args...)
	if err != nil {
		return nil, err
	}
	if res.RowsAffected() == 0 {
		if in.ExpectedVersion > 0 {
			return nil, ErrVersionConflict
		}
		return nil, ErrDiscountNotFound
	}

	// Re-sync discount menus
	if _, err := tx.Exec(ctx, `DELETE FROM discount_menus WHERE discount_id = $1`, id); err != nil {
		return nil, err
	}

	if scope == ScopeItem && len(in.MenuIDs) > 0 {
		for _, mID := range in.MenuIDs {
			mID = strings.TrimSpace(mID)
			if mID == "" {
				continue
			}
			if _, err := tx.Exec(ctx, `INSERT INTO discount_menus (discount_id, menu_id) VALUES ($1, $2)`, id, mID); err != nil {
				return nil, err
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return s.GetByID(ctx, id)
}

func (s *Store) ToggleActive(ctx context.Context, id string) (*Discount, error) {
	res, err := s.db.Exec(ctx, `UPDATE discounts SET is_active = NOT is_active, version = version + 1 WHERE id = $1`, id)
	if err != nil {
		return nil, err
	}
	if res.RowsAffected() == 0 {
		return nil, ErrDiscountNotFound
	}
	return s.GetByID(ctx, id)
}

func (s *Store) Delete(ctx context.Context, id string) error {
	res, err := s.db.Exec(ctx, `DELETE FROM discounts WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return ErrDiscountNotFound
	}
	return nil
}

func (s *Store) GetApplicableDiscounts(ctx context.Context, branchID, channel string, subtotal int64) ([]Discount, error) {
	now := time.Now().UTC()
	q := `SELECT d.id, d.name, d.code, d.scope, d.channel, d.type, d.value, d.max_discount_amount, d.min_order_amount,
	             d.branch_id, COALESCE(b.name, ''), d.is_active, d.start_time, d.end_time, d.version, d.created_at, d.updated_at
	      FROM discounts d
	      LEFT JOIN branches b ON d.branch_id = b.id
	      WHERE d.is_active = TRUE
	        AND (d.min_order_amount <= $1)
	        AND (d.start_time IS NULL OR d.start_time <= $2)
	        AND (d.end_time IS NULL OR d.end_time >= $2)`

	args := []any{subtotal, now}
	argIdx := 3

	if branchID != "" {
		q += fmt.Sprintf(" AND (d.branch_id IS NULL OR d.branch_id = $%d)", argIdx)
		args = append(args, branchID)
		argIdx++
	}

	var candidateChannel string
	switch strings.ToUpper(strings.TrimSpace(channel)) {
	case "CASHIER_MANUAL", "OFFLINE":
		candidateChannel = ChannelOffline
	case "WHATSAPP", "WHATSAPP_BOT":
		candidateChannel = ChannelWhatsApp
	case "CUSTOMER_WEB":
		candidateChannel = ChannelCustomerWeb
	case "GOFOOD":
		candidateChannel = ChannelGoFood
	case "GRABFOOD":
		candidateChannel = ChannelGrabFood
	case "SHOPEEFOOD":
		candidateChannel = ChannelShopeeFood
	default:
		candidateChannel = channel
	}

	if candidateChannel != "" {
		q += fmt.Sprintf(" AND (d.channel = 'ALL' OR d.channel = $%d)", argIdx)
		args = append(args, candidateChannel)
		argIdx++
	}

	q += " ORDER BY d.scope ASC, d.value DESC"

	rows, err := s.db.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var discounts []Discount
	var discIDs []string

	for rows.Next() {
		var d Discount
		var code sql.NullString
		var bID sql.NullString
		var startTime sql.NullTime
		var endTime sql.NullTime

		if err := rows.Scan(
			&d.ID, &d.Name, &code, &d.Scope, &d.Channel, &d.Type, &d.Value,
			&d.MaxDiscountAmount, &d.MinOrderAmount, &bID, &d.BranchName,
			&d.IsActive, &startTime, &endTime, &d.Version, &d.CreatedAt, &d.UpdatedAt,
		); err != nil {
			return nil, err
		}

		if code.Valid {
			d.Code = &code.String
		}
		if bID.Valid {
			d.BranchID = &bID.String
		}
		if startTime.Valid {
			d.StartTime = &startTime.Time
		}
		if endTime.Valid {
			d.EndTime = &endTime.Time
		}

		discounts = append(discounts, d)
		discIDs = append(discIDs, d.ID)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	if len(discIDs) > 0 {
		menuMap, err := s.loadDiscountMenus(ctx, discIDs)
		if err != nil {
			return nil, err
		}
		for i := range discounts {
			if menus, ok := menuMap[discounts[i].ID]; ok {
				discounts[i].MenuIDs = menus
			} else {
				discounts[i].MenuIDs = []string{}
			}
		}
	}

	return discounts, nil
}
