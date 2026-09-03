package customer

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Store struct{ db *pgxpool.Pool }

func NewStore(db *pgxpool.Pool) *Store { return &Store{db: db} }

func (s *Store) CreateOrGet(ctx context.Context, p Profile, key string) (Profile, bool, error) {
	row := s.db.QueryRow(ctx, `INSERT INTO customers (id, phone_e164, display_name, preferences, create_idempotency_key)
		VALUES ($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING
		RETURNING id::text, phone_e164, display_name, preferences, version`, p.ID, p.PhoneE164, p.DisplayName, p.Preferences, key)
	got, err := scanProfile(row)
	if err == nil {
		return got, true, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return Profile{}, false, err
	}
	row = s.db.QueryRow(ctx, `SELECT id::text, phone_e164, display_name, preferences, version FROM customers WHERE create_idempotency_key=$1 OR phone_e164=$2 ORDER BY (create_idempotency_key=$1) DESC LIMIT 1`, key, p.PhoneE164)
	got, err = scanProfile(row)
	return got, false, err
}

func (s *Store) Update(ctx context.Context, id string, in UpdateInput) (Profile, error) {
	row := s.db.QueryRow(ctx, `UPDATE customers SET display_name=$2, preferences=$3, version=version+1, updated_at=now() WHERE id=$1 AND version=$4 RETURNING id::text, phone_e164, display_name, preferences, version`, id, in.DisplayName, in.Preferences, in.ExpectedVersion)
	p, err := scanProfile(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return Profile{}, ErrVersionConflict
	}
	return p, err
}

func (s *Store) OrderHistory(ctx context.Context, id string) ([]OrderSummary, error) {
	rows, err := s.db.Query(ctx, `SELECT id::text, order_number, status, total_amount FROM orders WHERE customer_id=$1 ORDER BY created_at DESC, id DESC LIMIT 100`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []OrderSummary{}
	for rows.Next() {
		var v OrderSummary
		if err := rows.Scan(&v.ID, &v.OrderNumber, &v.Status, &v.TotalAmount); err != nil {
			return nil, err
		}
		result = append(result, v)
	}
	return result, rows.Err()
}

type profileRow interface{ Scan(...any) error }

func scanProfile(row profileRow) (Profile, error) {
	var p Profile
	var preferences []byte
	err := row.Scan(&p.ID, &p.PhoneE164, &p.DisplayName, &preferences, &p.Version)
	p.Preferences = json.RawMessage(preferences)
	return p, err
}
