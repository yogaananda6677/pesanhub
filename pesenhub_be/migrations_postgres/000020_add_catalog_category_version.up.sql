ALTER TABLE menu_categories
    ADD COLUMN version bigint NOT NULL DEFAULT 1 CHECK (version >= 1);
