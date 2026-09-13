ALTER TABLE menus ADD COLUMN sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0);

CREATE TABLE modifier_groups (
    id uuid PRIMARY KEY,
    menu_id uuid NOT NULL REFERENCES menus(id) ON DELETE CASCADE,
    code text NOT NULL CHECK (char_length(btrim(code)) BETWEEN 1 AND 64),
    name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 120),
    min_select integer NOT NULL DEFAULT 0 CHECK (min_select >= 0),
    max_select integer NOT NULL DEFAULT 1 CHECK (max_select >= 1 AND max_select >= min_select),
    is_active boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (menu_id, code)
);
CREATE INDEX modifier_groups_menu_idx ON modifier_groups (menu_id, sort_order, id);

CREATE TABLE modifier_options (
    id uuid PRIMARY KEY,
    group_id uuid NOT NULL REFERENCES modifier_groups(id) ON DELETE CASCADE,
    code text NOT NULL CHECK (char_length(btrim(code)) BETWEEN 1 AND 64),
    name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 120),
    price_delta_amount bigint NOT NULL DEFAULT 0,
    is_available boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (group_id, code)
);
CREATE INDEX modifier_options_group_idx ON modifier_options (group_id, sort_order, id);
CREATE INDEX menus_public_order_idx ON menus (category_id, sort_order, name, id) WHERE is_available;

ALTER TABLE order_item_modifiers
    ADD COLUMN modifier_option_id uuid REFERENCES modifier_options(id) ON DELETE SET NULL;

COMMENT ON TABLE menu_modifiers IS 'Legacy Phase 0 flat modifier definition; new catalog writes use modifier_groups/modifier_options.';
