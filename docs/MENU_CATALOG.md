# Menu Catalog Contract

- PostgreSQL is the source of truth for category, menu, modifier group/option, price, and availability. Prices are integer Rupiah (`bigint`/Go `int64`); floating-point money is forbidden.
- Public and agent reads expose only active categories, available menus, active groups, and available options. Ordering is deterministic: `sort_order`, `name`, then immutable `id`. `filter[category_id]` is optional.
- Admin writes require a verified `STAFF` principal and default to forbidden until production auth middleware supplies one.
- Each group defines `min_select` and `max_select`. Options must belong to the selected menu's group, may not repeat, and must be available. The validator returns a safe field path such as `modifier_groups.spice.option_ids`.
- The Backend recalculates `base price + option deltas`; clients/Hermes never submit an authoritative total. Menu availability is rechecked at order commit time, so a cart opened before a price/availability update cannot bypass current catalog state.
- Menu availability updates require expected `version`. Complex promotions and inventory remain outside #16.
- `menu_modifiers` remains as a Phase 0 compatibility table; new writes use `modifier_groups` and `modifier_options`. Order snapshots preserve historical names/prices even if catalog rows change.
