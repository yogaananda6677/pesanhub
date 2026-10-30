-- 000014_create_cash_shifts.up.sql
CREATE TABLE IF NOT EXISTS cash_shifts (
  id CHAR(36) PRIMARY KEY,
  branch_id CHAR(36) NOT NULL,
  cashier_id VARCHAR(191) NOT NULL,
  cashier_name VARCHAR(120) NOT NULL,
  shift_start DATETIME(6) NOT NULL,
  shift_end DATETIME(6) NULL,
  starting_cash BIGINT NOT NULL DEFAULT 0,
  expected_cash BIGINT NOT NULL DEFAULT 0,
  actual_cash BIGINT NULL,
  cash_in BIGINT NOT NULL DEFAULT 0,
  cash_out BIGINT NOT NULL DEFAULT 0,
  discrepancy BIGINT NULL,
  notes TEXT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'OPEN',
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_cash_shifts_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE RESTRICT,
  INDEX idx_cash_shifts_branch_status (branch_id, status, shift_start DESC),
  INDEX idx_cash_shifts_cashier (cashier_id, shift_start DESC)
) ENGINE=InnoDB;
