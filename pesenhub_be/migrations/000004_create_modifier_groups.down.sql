ALTER TABLE order_item_modifiers DROP COLUMN IF EXISTS modifier_option_id;
DROP INDEX IF EXISTS menus_public_order_idx;
DROP TABLE IF EXISTS modifier_options;
DROP TABLE IF EXISTS modifier_groups;
ALTER TABLE menus DROP COLUMN IF EXISTS sort_order;
COMMENT ON TABLE menu_modifiers IS NULL;
