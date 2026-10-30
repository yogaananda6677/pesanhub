package phonename

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

// AutoMigrate ensures customer_phone_names table exists.
func (s *Store) AutoMigrate(ctx context.Context) error {
	q := `CREATE TABLE IF NOT EXISTS customer_phone_names (
		phone_e164 VARCHAR(20) PRIMARY KEY,
		customer_name VARCHAR(120) NOT NULL,
		notes TEXT NULL,
		created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
		updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6)
	) ENGINE=InnoDB;`
	_, err := s.db.Exec(ctx, q)
	return err
}

func (s *Store) Get(ctx context.Context, phone string) (string, error) {
	cleanPhone, err := customer.NormalizeIndonesia(phone)
	if err != nil {
		cleanPhone = strings.TrimSpace(phone)
	}
	if cleanPhone == "" {
		return "", nil
	}

	q := `SELECT customer_name FROM customer_phone_names WHERE phone_e164 = $1 LIMIT 1`
	var name string
	err = s.db.QueryRow(ctx, q, cleanPhone).Scan(&name)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", nil
		}
		return "", err
	}
	return strings.TrimSpace(name), nil
}

func (s *Store) Set(ctx context.Context, in SetPhoneNameInput) (*PhoneName, error) {
	cleanPhone, err := customer.NormalizeIndonesia(in.Phone)
	if err != nil {
		cleanPhone = strings.TrimSpace(in.Phone)
	}
	cleanName := strings.TrimSpace(in.CustomerName)
	if cleanPhone == "" || cleanName == "" {
		return nil, errors.New("phone and customer_name are required")
	}

	now := time.Now().UTC()
	q := `INSERT INTO customer_phone_names (phone_e164, customer_name, notes, created_at, updated_at)
	      VALUES ($1, $2, $3, $4, $5)
	      ON DUPLICATE KEY UPDATE customer_name = VALUES(customer_name), notes = VALUES(notes), updated_at = VALUES(updated_at)`

	if _, err := s.db.Exec(ctx, q, cleanPhone, cleanName, strings.TrimSpace(in.Notes), now, now); err != nil {
		return nil, fmt.Errorf("failed to upsert phone name: %w", err)
	}

	return &PhoneName{
		PhoneE164:    cleanPhone,
		CustomerName: cleanName,
		Notes:        strings.TrimSpace(in.Notes),
		CreatedAt:    now,
		UpdatedAt:    now,
	}, nil
}

func (s *Store) List(ctx context.Context) ([]PhoneName, error) {
	q := `SELECT phone_e164, customer_name, COALESCE(notes, ''), created_at, updated_at FROM customer_phone_names ORDER BY updated_at DESC LIMIT 500`
	rows, err := s.db.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []PhoneName
	for rows.Next() {
		var item PhoneName
		if err := rows.Scan(&item.PhoneE164, &item.CustomerName, &item.Notes, &item.CreatedAt, &item.UpdatedAt); err != nil {
			return nil, err
		}
		list = append(list, item)
	}
	return list, nil
}

func (s *Store) Delete(ctx context.Context, phone string) error {
	cleanPhone, err := customer.NormalizeIndonesia(phone)
	if err != nil {
		cleanPhone = strings.TrimSpace(phone)
	}
	q := `DELETE FROM customer_phone_names WHERE phone_e164 = $1`
	_, err = s.db.Exec(ctx, q, cleanPhone)
	return err
}
