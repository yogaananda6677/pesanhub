package branch

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"strings"

	"github.com/go-sql-driver/mysql"
	"pesenhub/backend/internal/customer"
	dbx "pesenhub/backend/internal/database"
)

type Store struct {
	db *dbx.Pool
}

func NewStore(db *dbx.Pool) *Store {
	return &Store{db: db}
}

func (s *Store) List(ctx context.Context, activeOnly bool) ([]Branch, error) {
	q := `SELECT id::text, code, name, COALESCE(address, ''), COALESCE(phone, ''), is_default, is_active, created_at, updated_at
		FROM branches`
	if activeOnly {
		q += ` WHERE is_active = true`
	}
	q += ` ORDER BY is_default DESC, name ASC`

	rows, err := s.db.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var branches []Branch
	for rows.Next() {
		var b Branch
		if err := rows.Scan(&b.ID, &b.Code, &b.Name, &b.Address, &b.Phone, &b.IsDefault, &b.IsActive, &b.CreatedAt, &b.UpdatedAt); err != nil {
			return nil, err
		}
		branches = append(branches, b)
	}
	return branches, rows.Err()
}

func (s *Store) GetByID(ctx context.Context, id string) (Branch, error) {
	var b Branch
	err := s.db.QueryRow(ctx, `
		SELECT id::text, code, name, COALESCE(address, ''), COALESCE(phone, ''), is_default, is_active, created_at, updated_at
		FROM branches
		WHERE id = $1::uuid`, id).Scan(&b.ID, &b.Code, &b.Name, &b.Address, &b.Phone, &b.IsDefault, &b.IsActive, &b.CreatedAt, &b.UpdatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return Branch{}, ErrNotFound
	}
	return b, err
}

func (s *Store) GetByCode(ctx context.Context, code string) (Branch, error) {
	var b Branch
	err := s.db.QueryRow(ctx, `
		SELECT id::text, code, name, COALESCE(address, ''), COALESCE(phone, ''), is_default, is_active, created_at, updated_at
		FROM branches
		WHERE UPPER(code) = UPPER($1)`, strings.TrimSpace(code)).Scan(&b.ID, &b.Code, &b.Name, &b.Address, &b.Phone, &b.IsDefault, &b.IsActive, &b.CreatedAt, &b.UpdatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return Branch{}, ErrNotFound
	}
	return b, err
}

func (s *Store) GetDefault(ctx context.Context) (Branch, error) {
	var b Branch
	err := s.db.QueryRow(ctx, `
		SELECT id::text, code, name, COALESCE(address, ''), COALESCE(phone, ''), is_default, is_active, created_at, updated_at
		FROM branches
		WHERE is_default = true
		LIMIT 1`).Scan(&b.ID, &b.Code, &b.Name, &b.Address, &b.Phone, &b.IsDefault, &b.IsActive, &b.CreatedAt, &b.UpdatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return Branch{}, ErrNotFound
	}
	return b, err
}

func (s *Store) Create(ctx context.Context, b Branch) (Branch, error) {
	tx, err := s.db.BeginTx(ctx, dbx.TxOptions{})
	if err != nil {
		return Branch{}, err
	}
	defer tx.Rollback(ctx)

	if b.IsDefault {
		if _, err := tx.Exec(ctx, `UPDATE branches SET is_default = false WHERE is_default = true`); err != nil {
			return Branch{}, err
		}
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO branches (id, code, name, address, phone, is_default, is_active)
		VALUES ($1::uuid, $2, $3, NULLIF($4, ''), NULLIF($5, ''), $6, $7)`,
		b.ID, b.Code, b.Name, b.Address, b.Phone, b.IsDefault, b.IsActive)
	if err != nil {
		var dbErr *mysql.MySQLError
		if errors.As(err, &dbErr) && dbErr.Number == 1062 {
			return Branch{}, ErrDuplicateCode
		}
		return Branch{}, err
	}

	// Also populate initial menu and modifier availability for this new branch from global master
	_, _ = tx.Exec(ctx, `
		INSERT IGNORE INTO branch_menu_availability (branch_id, menu_id, is_available, version)
		SELECT $1::uuid, id, is_available, 1 FROM menus`, b.ID)

	_, _ = tx.Exec(ctx, `
		INSERT IGNORE INTO branch_modifier_option_availability (branch_id, modifier_option_id, is_available, version)
		SELECT $1::uuid, id, is_available, 1 FROM modifier_options`, b.ID)

	auditID := customer.NewID()
	branchMeta, _ := json.Marshal(map[string]any{
		"branch_id":  b.ID,
		"code":       b.Code,
		"name":       b.Name,
		"is_default": b.IsDefault,
	})
	_, _ = tx.Exec(ctx, `INSERT INTO audit_logs (id, aggregate_type, aggregate_id, action, actor_type, actor_id, request_id, metadata_redacted, created_at)
		VALUES ($1::uuid, 'BRANCH', $2, 'BRANCH_CREATED', 'STAFF', 'system', 'system', $3, now())`,
		auditID, b.ID, branchMeta)

	if err := tx.Commit(ctx); err != nil {
		return Branch{}, err
	}
	return s.GetByID(ctx, b.ID)
}

func (s *Store) Update(ctx context.Context, b Branch) (Branch, error) {
	tx, err := s.db.BeginTx(ctx, dbx.TxOptions{})
	if err != nil {
		return Branch{}, err
	}
	defer tx.Rollback(ctx)

	if b.IsDefault {
		if _, err := tx.Exec(ctx, `UPDATE branches SET is_default = false WHERE is_default = true AND id != $1::uuid`, b.ID); err != nil {
			return Branch{}, err
		}
	}

	res, err := tx.Exec(ctx, `
		UPDATE branches
		SET code = $2, name = $3, address = NULLIF($4, ''), phone = NULLIF($5, ''), is_default = $6, is_active = $7, updated_at = now()
		WHERE id = $1::uuid`,
		b.ID, b.Code, b.Name, b.Address, b.Phone, b.IsDefault, b.IsActive)
	if err != nil {
		var dbErr *mysql.MySQLError
		if errors.As(err, &dbErr) && dbErr.Number == 1062 {
			return Branch{}, ErrDuplicateCode
		}
		return Branch{}, err
	}
	if res.RowsAffected() == 0 {
		return Branch{}, ErrNotFound
	}

	if err := tx.Commit(ctx); err != nil {
		return Branch{}, err
	}
	return s.GetByID(ctx, b.ID)
}

func (s *Store) AssignUserBranch(ctx context.Context, userID, branchID string) error {
	res, err := s.db.Exec(ctx, `
		UPDATE app_users
		SET branch_id = $2::uuid, updated_at = now()
		WHERE id = $1::uuid`, userID, branchID)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
