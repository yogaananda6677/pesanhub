ALTER TABLE menus
  ADD COLUMN hpp_amount bigint NULL AFTER price_amount,
  ADD CONSTRAINT chk_menus_hpp_nonnegative CHECK (hpp_amount IS NULL OR hpp_amount >= 0);

CREATE TABLE menu_channel_prices (
  menu_id char(36) NOT NULL,
  channel varchar(24) NOT NULL,
  amount bigint NOT NULL,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (menu_id, channel),
  CONSTRAINT fk_menu_channel_prices_menu
    FOREIGN KEY (menu_id) REFERENCES menus(id) ON DELETE CASCADE,
  CONSTRAINT chk_menu_channel_prices_channel
    CHECK (channel IN ('OFFLINE', 'GOFOOD', 'GRABFOOD', 'SHOPEEFOOD')),
  CONSTRAINT chk_menu_channel_prices_amount CHECK (amount >= 0),
  INDEX menu_channel_prices_channel_idx (channel, amount)
) ENGINE=InnoDB;

INSERT INTO menu_channel_prices(menu_id, channel, amount)
SELECT id, 'OFFLINE', price_amount FROM menus;
