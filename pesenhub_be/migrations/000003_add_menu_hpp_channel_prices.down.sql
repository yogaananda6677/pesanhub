DROP TABLE IF EXISTS menu_channel_prices;

ALTER TABLE menus
  DROP CHECK chk_menus_hpp_nonnegative,
  DROP COLUMN hpp_amount;
