package shift

import "time"

type CashShift struct {
	ID           string     `json:"id"`
	BranchID     string     `json:"branch_id"`
	CashierID    string     `json:"cashier_id"`
	CashierName  string     `json:"cashier_name"`
	ShiftStart   time.Time  `json:"shift_start"`
	ShiftEnd     *time.Time `json:"shift_end,omitempty"`
	StartingCash int64      `json:"starting_cash"`
	ExpectedCash int64      `json:"expected_cash"`
	ActualCash   *int64     `json:"actual_cash,omitempty"`
	CashIn       int64      `json:"cash_in"`
	CashOut      int64      `json:"cash_out"`
	Discrepancy  *int64     `json:"discrepancy,omitempty"`
	Notes        *string    `json:"notes,omitempty"`
	Status       string     `json:"status"` // "OPEN", "CLOSED"
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
}

type OpenShiftRequest struct {
	StartingCash int64  `json:"starting_cash"`
	Notes        string `json:"notes,omitempty"`
	BranchID     string `json:"branch_id,omitempty"`
}

type CloseShiftRequest struct {
	ShiftID    string `json:"shift_id,omitempty"`
	ActualCash int64  `json:"actual_cash"`
	Notes      string `json:"notes,omitempty"`
}

type ShiftResponse struct {
	Shift CashShift `json:"shift"`
}

type ShiftListResponse struct {
	Shifts []CashShift `json:"shifts"`
}
