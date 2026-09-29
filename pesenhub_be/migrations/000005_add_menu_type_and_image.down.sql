ALTER TABLE menus
  DROP CHECK chk_menus_product_type,
  DROP COLUMN image_url,
  DROP COLUMN product_type;
