ALTER TABLE orders
  DROP CHECK chk_orders_total_nonnegative,
  DROP CHECK chk_orders_total_calc,
  DROP CHECK chk_orders_discount_nonnegative;

ALTER TABLE orders
  ADD CONSTRAINT orders_chk_2 CHECK (total_amount = subtotal_amount);

ALTER TABLE orders
  DROP FOREIGN KEY fk_orders_discount;

ALTER TABLE orders
  DROP COLUMN discount_name_snapshot,
  DROP COLUMN discount_id,
  DROP COLUMN discount_amount;

DROP TABLE IF EXISTS discount_menus;
DROP TABLE IF EXISTS discounts;
