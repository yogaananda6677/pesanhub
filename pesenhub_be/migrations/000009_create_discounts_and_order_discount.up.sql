CREATE TABLE IF NOT EXISTS discounts (
  id CHAR(36) PRIMARY KEY,
  name VARCHAR(160) NOT NULL,
  code VARCHAR(64) UNIQUE NULL,
  scope VARCHAR(32) NOT NULL,
  channel VARCHAR(32) NOT NULL DEFAULT 'ALL',
  type VARCHAR(32) NOT NULL,
  value BIGINT NOT NULL,
  max_discount_amount BIGINT NULL DEFAULT NULL,
  min_order_amount BIGINT NOT NULL DEFAULT 0,
  branch_id CHAR(36) NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  start_time DATETIME(6) NULL,
  end_time DATETIME(6) NULL,
  version BIGINT NOT NULL DEFAULT 1,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_discounts_branch FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE,
  CONSTRAINT chk_discounts_scope CHECK (scope IN ('ORDER', 'ITEM')),
  CONSTRAINT chk_discounts_type CHECK (type IN ('PERCENTAGE', 'FIXED')),
  CONSTRAINT chk_discounts_value CHECK (value > 0),
  CONSTRAINT chk_discounts_min_order CHECK (min_order_amount >= 0),
  INDEX idx_discounts_active_channel (is_active, channel),
  INDEX idx_discounts_branch (branch_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS discount_menus (
  discount_id CHAR(36) NOT NULL,
  menu_id CHAR(36) NOT NULL,
  PRIMARY KEY (discount_id, menu_id),
  CONSTRAINT fk_dm_discount FOREIGN KEY (discount_id) REFERENCES discounts(id) ON DELETE CASCADE,
  CONSTRAINT fk_dm_menu FOREIGN KEY (menu_id) REFERENCES menus(id) ON DELETE CASCADE
) ENGINE=InnoDB;

ALTER TABLE orders
  ADD COLUMN discount_amount BIGINT NOT NULL DEFAULT 0 AFTER subtotal_amount,
  ADD COLUMN discount_id CHAR(36) NULL AFTER discount_amount,
  ADD COLUMN discount_name_snapshot VARCHAR(160) NULL AFTER discount_id,
  ADD CONSTRAINT fk_orders_discount FOREIGN KEY (discount_id) REFERENCES discounts(id) ON DELETE SET NULL;

-- Drop old check constraint orders_chk_2 (total_amount = subtotal_amount)
ALTER TABLE orders DROP CHECK orders_chk_2;

-- Add updated check constraints
ALTER TABLE orders
  ADD CONSTRAINT chk_orders_discount_nonnegative CHECK (discount_amount >= 0),
  ADD CONSTRAINT chk_orders_total_calc CHECK (total_amount = subtotal_amount - discount_amount),
  ADD CONSTRAINT chk_orders_total_nonnegative CHECK (total_amount >= 0);
