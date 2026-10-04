package contact

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

func (s *Store) List(ctx context.Context, filter ListFilter) ([]Contact, error) {
	q := `SELECT id, branch_id, phone_e164, COALESCE(name, ''), contact_type, auto_reply_enabled, COALESCE(notes, ''), created_at, updated_at
	      FROM whatsapp_contacts
	      WHERE 1=1`

	var args []any
	argIdx := 1

	if filter.BranchID != "" {
		q += fmt.Sprintf(" AND branch_id = $%d", argIdx)
		args = append(args, filter.BranchID)
		argIdx++
	}

	if filter.ContactType != "" {
		q += fmt.Sprintf(" AND contact_type = $%d", argIdx)
		args = append(args, filter.ContactType)
		argIdx++
	}

	if filter.Search != "" {
		q += fmt.Sprintf(" AND (phone_e164 LIKE $%d OR LOWER(COALESCE(name, '')) LIKE $%d OR LOWER(COALESCE(notes, '')) LIKE $%d)", argIdx, argIdx, argIdx)
		args = append(args, "%"+strings.ToLower(filter.Search)+"%")
		argIdx++
	}

	q += " ORDER BY updated_at DESC"

	if filter.Limit > 0 {
		q += fmt.Sprintf(" LIMIT $%d", argIdx)
		args = append(args, filter.Limit)
	} else {
		q += " LIMIT 100"
	}

	rows, err := s.db.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to query whatsapp contacts: %w", err)
	}
	defer rows.Close()

	var contacts []Contact
	for rows.Next() {
		var c Contact
		if err := rows.Scan(
			&c.ID, &c.BranchID, &c.PhoneE164, &c.Name, &c.ContactType, &c.AutoReplyEnabled, &c.Notes, &c.CreatedAt, &c.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("failed to scan contact: %w", err)
		}
		contacts = append(contacts, c)
	}

	return contacts, nil
}

func (s *Store) GetByPhone(ctx context.Context, phone string) (*Contact, error) {
	cleanPhone, err := customer.NormalizeIndonesia(phone)
	if err != nil {
		cleanPhone = strings.TrimSpace(phone)
	}

	q := `SELECT id, branch_id, phone_e164, COALESCE(name, ''), contact_type, auto_reply_enabled, COALESCE(notes, ''), created_at, updated_at
	      FROM whatsapp_contacts
	      WHERE phone_e164 = $1
	      LIMIT 1`

	var c Contact
	err = s.db.QueryRow(ctx, q, cleanPhone).Scan(
		&c.ID, &c.BranchID, &c.PhoneE164, &c.Name, &c.ContactType, &c.AutoReplyEnabled, &c.Notes, &c.CreatedAt, &c.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrContactNotFound
		}
		return nil, fmt.Errorf("failed to get contact by phone: %w", err)
	}

	return &c, nil
}

func (s *Store) GetByID(ctx context.Context, id string) (*Contact, error) {
	q := `SELECT id, branch_id, phone_e164, COALESCE(name, ''), contact_type, auto_reply_enabled, COALESCE(notes, ''), created_at, updated_at
	      FROM whatsapp_contacts
	      WHERE id = $1
	      LIMIT 1`

	var c Contact
	err := s.db.QueryRow(ctx, q, id).Scan(
		&c.ID, &c.BranchID, &c.PhoneE164, &c.Name, &c.ContactType, &c.AutoReplyEnabled, &c.Notes, &c.CreatedAt, &c.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrContactNotFound
		}
		return nil, fmt.Errorf("failed to get contact by id: %w", err)
	}

	return &c, nil
}

func (s *Store) Upsert(ctx context.Context, in UpsertContactInput) (*Contact, error) {
	phone, err := customer.NormalizeIndonesia(in.Phone)
	if err != nil {
		phone = strings.TrimSpace(in.Phone)
		if phone == "" {
			return nil, ErrInvalidPhone
		}
	}

	branchID := strings.TrimSpace(in.BranchID)
	if branchID == "" {
		branchID = "b0000000-0000-0000-0000-000000000001" // Default Branch
	}

	contactType := strings.TrimSpace(in.ContactType)
	if contactType == "" {
		contactType = TypeCustomer
	}

	autoReply := true
	if in.AutoReplyEnabled != nil {
		autoReply = *in.AutoReplyEnabled
	} else if contactType == TypeNonCustomer || contactType == TypeBlacklist {
		autoReply = false
	}

	existing, err := s.GetByPhone(ctx, phone)
	now := time.Now()
	if err != nil && !errors.Is(err, ErrContactNotFound) {
		return nil, err
	}

	if existing != nil {
		name := existing.Name
		if strings.TrimSpace(in.Name) != "" {
			name = strings.TrimSpace(in.Name)
		}
		notes := existing.Notes
		if strings.TrimSpace(in.Notes) != "" {
			notes = strings.TrimSpace(in.Notes)
		}

		q := `UPDATE whatsapp_contacts
		      SET name = $1, contact_type = $2, auto_reply_enabled = $3, notes = $4, updated_at = $5
		      WHERE id = $6`
		if _, err := s.db.Exec(ctx, q, name, contactType, autoReply, notes, now, existing.ID); err != nil {
			return nil, fmt.Errorf("failed to update contact: %w", err)
		}
		return s.GetByID(ctx, existing.ID)
	}

	id := customer.NewID()
	name := strings.TrimSpace(in.Name)
	notes := strings.TrimSpace(in.Notes)

	q := `INSERT INTO whatsapp_contacts (id, branch_id, phone_e164, name, contact_type, auto_reply_enabled, notes, created_at, updated_at)
	      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`

	if _, err := s.db.Exec(ctx, q, id, branchID, phone, name, contactType, autoReply, notes, now, now); err != nil {
		return nil, fmt.Errorf("failed to insert contact: %w", err)
	}

	return s.GetByID(ctx, id)
}

func (s *Store) ToggleAutoReply(ctx context.Context, id string, enabled bool) (*Contact, error) {
	q := `UPDATE whatsapp_contacts
	      SET auto_reply_enabled = $1, updated_at = $2
	      WHERE id = $3`

	res, err := s.db.Exec(ctx, q, enabled, time.Now(), id)
	if err != nil {
		return nil, fmt.Errorf("failed to toggle auto reply: %w", err)
	}
	if res.RowsAffected() == 0 {
		return nil, ErrContactNotFound
	}

	return s.GetByID(ctx, id)
}

func (s *Store) MarkAsNonCustomer(ctx context.Context, id string, contactType, notes string) (*Contact, error) {
	if contactType == "" {
		contactType = TypeNonCustomer
	}

	q := `UPDATE whatsapp_contacts
	      SET contact_type = $1, auto_reply_enabled = false, notes = CASE WHEN $2 != '' THEN $2 ELSE notes END, updated_at = $3
	      WHERE id = $4`

	res, err := s.db.Exec(ctx, q, contactType, strings.TrimSpace(notes), time.Now(), id)
	if err != nil {
		return nil, fmt.Errorf("failed to mark contact as non-customer: %w", err)
	}
	if res.RowsAffected() == 0 {
		return nil, ErrContactNotFound
	}

	return s.GetByID(ctx, id)
}
