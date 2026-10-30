package shift

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"pesenhub/backend/internal/customer"
	dbx "pesenhub/backend/internal/database"
)

var (
	ErrShiftAlreadyOpen   = errors.New("a cash shift is already open for this branch")
	ErrShiftNotFound      = errors.New("cash shift not found")
	ErrShiftAlreadyClosed = errors.New("cash shift is already closed")
)

type Store struct {
	db *dbx.Pool
}

func NewStore(db *dbx.Pool) *Store {
	return &Store{db: db}
}

func (s *Store) OpenShift(ctx context.Context, cs CashShift) (CashShift, error) {
	// Verify no open shift currently exists for this branch
	var existingID string
	err := s.db.QueryRow(ctx, `SELECT id FROM cash_shifts WHERE branch_id = $1::uuid AND status = 'OPEN' LIMIT 1`, cs.BranchID).Scan(&existingID)
	if err == nil {
		return CashShift{}, ErrShiftAlreadyOpen
	} else if !errors.Is(err, sql.ErrNoRows) {
		return CashShift{}, err
	}

	if cs.ID == "" {
		cs.ID = customer.NewID()
	}
	now := time.Now().UTC()
	cs.ShiftStart = now
	cs.Status = "OPEN"
	cs.ExpectedCash = cs.StartingCash
	cs.CashIn = 0
	cs.CashOut = 0
	cs.CreatedAt = now
	cs.UpdatedAt = now

	insertQuery := `
		INSERT INTO cash_shifts (
			id, branch_id, cashier_id, cashier_name, shift_start,
			starting_cash, expected_cash, cash_in, cash_out, notes, status,
			created_at, updated_at
		) VALUES (
			$1, $2::uuid, $3, $4, $5,
			$6, $7, $8, $9, NULLIF($10, ''), $11,
			$12, $13
		)`

	notesStr := ""
	if cs.Notes != nil {
		notesStr = *cs.Notes
	}

	_, err = s.db.Exec(ctx, insertQuery,
		cs.ID, cs.BranchID, cs.CashierID, cs.CashierName, cs.ShiftStart,
		cs.StartingCash, cs.ExpectedCash, cs.CashIn, cs.CashOut, notesStr, cs.Status,
		cs.CreatedAt, cs.UpdatedAt,
	)
	if err != nil {
		return CashShift{}, err
	}

	return cs, nil
}

func (s *Store) GetCurrentShift(ctx context.Context, branchID string) (*CashShift, error) {
	query := `
		SELECT id, branch_id, cashier_id, cashier_name, shift_start, shift_end,
		       starting_cash, expected_cash, actual_cash, cash_in, cash_out,
		       discrepancy, notes, status, created_at, updated_at
		FROM cash_shifts
		WHERE branch_id = $1::uuid AND status = 'OPEN'
		ORDER BY shift_start DESC
		LIMIT 1`

	var cs CashShift
	var shiftEnd sql.NullTime
	var actualCash, discrepancy sql.NullInt64
	var notes sql.NullString

	err := s.db.QueryRow(ctx, query, branchID).Scan(
		&cs.ID, &cs.BranchID, &cs.CashierID, &cs.CashierName, &cs.ShiftStart, &shiftEnd,
		&cs.StartingCash, &cs.ExpectedCash, &actualCash, &cs.CashIn, &cs.CashOut,
		&discrepancy, &notes, &cs.Status, &cs.CreatedAt, &cs.UpdatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	if shiftEnd.Valid {
		cs.ShiftEnd = &shiftEnd.Time
	}
	if actualCash.Valid {
		cs.ActualCash = &actualCash.Int64
	}
	if discrepancy.Valid {
		cs.Discrepancy = &discrepancy.Int64
	}
	if notes.Valid {
		cs.Notes = &notes.String
	}

	// Calculate live cash-in from completed or paid CASH orders since shift_start
	cashInQuery := `
		SELECT COALESCE(SUM(o.total_amount), 0)
		FROM orders o
		JOIN payments p ON p.order_id = o.id
		WHERE o.branch_id = $1::uuid
		  AND (o.status = 'COMPLETED' OR p.status = 'PAID')
		  AND o.status NOT IN ('CANCELLED', 'REJECTED')
		  AND p.method = 'CASH'
		  AND o.created_at >= $2`

	var liveCashIn int64
	if err := s.db.QueryRow(ctx, cashInQuery, branchID, cs.ShiftStart).Scan(&liveCashIn); err == nil {
		cs.CashIn = liveCashIn
		cs.ExpectedCash = cs.StartingCash + liveCashIn - cs.CashOut
	}

	return &cs, nil
}

func (s *Store) CloseShift(ctx context.Context, shiftID string, branchID string, actualCash int64, notes string) (CashShift, error) {
	query := `
		SELECT id, branch_id, cashier_id, cashier_name, shift_start, shift_end,
		       starting_cash, expected_cash, actual_cash, cash_in, cash_out,
		       discrepancy, notes, status, created_at, updated_at
		FROM cash_shifts
		WHERE id = $1`

	var cs CashShift
	var shiftEnd sql.NullTime
	var oldActual, oldDiscrepancy sql.NullInt64
	var oldNotes sql.NullString

	err := s.db.QueryRow(ctx, query, shiftID).Scan(
		&cs.ID, &cs.BranchID, &cs.CashierID, &cs.CashierName, &cs.ShiftStart, &shiftEnd,
		&cs.StartingCash, &cs.ExpectedCash, &oldActual, &cs.CashIn, &cs.CashOut,
		&oldDiscrepancy, &oldNotes, &cs.Status, &cs.CreatedAt, &cs.UpdatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return CashShift{}, ErrShiftNotFound
	}
	if err != nil {
		return CashShift{}, err
	}

	if cs.Status != "OPEN" {
		return CashShift{}, ErrShiftAlreadyClosed
	}

	now := time.Now().UTC()
	cs.ShiftEnd = &now

	// Compute final cash-in
	cashInQuery := `
		SELECT COALESCE(SUM(o.total_amount), 0)
		FROM orders o
		JOIN payments p ON p.order_id = o.id
		WHERE o.branch_id = $1::uuid
		  AND (o.status = 'COMPLETED' OR p.status = 'PAID')
		  AND o.status NOT IN ('CANCELLED', 'REJECTED')
		  AND p.method = 'CASH'
		  AND o.created_at >= $2`

	var finalCashIn int64
	_ = s.db.QueryRow(ctx, cashInQuery, cs.BranchID, cs.ShiftStart).Scan(&finalCashIn)

	cs.CashIn = finalCashIn
	cs.ExpectedCash = cs.StartingCash + finalCashIn - cs.CashOut
	cs.ActualCash = &actualCash
	diff := actualCash - cs.ExpectedCash
	cs.Discrepancy = &diff
	cs.Status = "CLOSED"
	if notes != "" {
		cs.Notes = &notes
	} else if oldNotes.Valid {
		cs.Notes = &oldNotes.String
	}
	cs.UpdatedAt = now

	updateQuery := `
		UPDATE cash_shifts
		SET status = 'CLOSED',
		    shift_end = $1,
		    actual_cash = $2,
		    cash_in = $3,
		    expected_cash = $4,
		    discrepancy = $5,
		    notes = NULLIF($6, ''),
		    updated_at = $7
		WHERE id = $8`

	notesVal := ""
	if cs.Notes != nil {
		notesVal = *cs.Notes
	}

	_, err = s.db.Exec(ctx, updateQuery,
		cs.ShiftEnd, *cs.ActualCash, cs.CashIn, cs.ExpectedCash,
		*cs.Discrepancy, notesVal, cs.UpdatedAt, cs.ID,
	)
	if err != nil {
		return CashShift{}, err
	}

	return cs, nil
}

func (s *Store) ListShifts(ctx context.Context, branchID string, limit int) ([]CashShift, error) {
	if limit <= 0 {
		limit = 20
	}
	query := `
		SELECT id, branch_id, cashier_id, cashier_name, shift_start, shift_end,
		       starting_cash, expected_cash, actual_cash, cash_in, cash_out,
		       discrepancy, notes, status, created_at, updated_at
		FROM cash_shifts
		WHERE branch_id = $1::uuid
		ORDER BY shift_start DESC
		LIMIT $2`

	rows, err := s.db.Query(ctx, query, branchID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []CashShift
	for rows.Next() {
		var cs CashShift
		var shiftEnd sql.NullTime
		var actualCash, discrepancy sql.NullInt64
		var notes sql.NullString

		if err := rows.Scan(
			&cs.ID, &cs.BranchID, &cs.CashierID, &cs.CashierName, &cs.ShiftStart, &shiftEnd,
			&cs.StartingCash, &cs.ExpectedCash, &actualCash, &cs.CashIn, &cs.CashOut,
			&discrepancy, &notes, &cs.Status, &cs.CreatedAt, &cs.UpdatedAt,
		); err == nil {
			if shiftEnd.Valid {
				cs.ShiftEnd = &shiftEnd.Time
			}
			if actualCash.Valid {
				cs.ActualCash = &actualCash.Int64
			}
			if discrepancy.Valid {
				cs.Discrepancy = &discrepancy.Int64
			}
			if notes.Valid {
				cs.Notes = &notes.String
			}
			list = append(list, cs)
		}
	}

	if list == nil {
		list = []CashShift{}
	}
	return list, nil
}
