ALTER TABLE menus
  ADD COLUMN product_type varchar(32) NOT NULL DEFAULT 'MARTABAK_TELUR' AFTER description,
  ADD COLUMN image_url varchar(500) NULL AFTER product_type,
  ADD CONSTRAINT chk_menus_product_type
    CHECK (product_type IN ('MARTABAK_TELUR', 'TERANG_BULAN'));
