package catalog

import "errors"

var (
	ErrInvalidCatalog  = errors.New("invalid catalog data")
	ErrUnavailable     = errors.New("menu or modifier unavailable")
	ErrInvalidModifier = errors.New("invalid modifier selection")
	ErrVersionConflict = errors.New("catalog version conflict")
)

type ValidationError struct {
	Field string
	Err   error
}

func (e *ValidationError) Error() string { return e.Field + ": " + e.Err.Error() }
func (e *ValidationError) Unwrap() error { return e.Err }
func invalid(field string) *ValidationError {
	return &ValidationError{Field: field, Err: ErrInvalidModifier}
}
func unavailable(field string) *ValidationError {
	return &ValidationError{Field: field, Err: ErrUnavailable}
}

type Option struct {
	ID               string `json:"id"`
	Code             string `json:"code"`
	Name             string `json:"name"`
	PriceDeltaAmount int64  `json:"price_delta_amount"`
	Available        bool   `json:"is_available"`
	SortOrder        int    `json:"sort_order"`
}
type Group struct {
	ID        string   `json:"id"`
	Code      string   `json:"code"`
	Name      string   `json:"name"`
	MinSelect int      `json:"min_select"`
	MaxSelect int      `json:"max_select"`
	SortOrder int      `json:"sort_order"`
	Active    bool     `json:"is_active"`
	Options   []Option `json:"options"`
}
type Menu struct {
	ID          string  `json:"id"`
	CategoryID  string  `json:"category_id"`
	SKU         string  `json:"sku"`
	Name        string  `json:"name"`
	Description string  `json:"description,omitempty"`
	PriceAmount int64   `json:"price_amount"`
	Available   bool    `json:"is_available"`
	Version     int64   `json:"version"`
	SortOrder   int     `json:"sort_order"`
	Groups      []Group `json:"modifier_groups"`
}
type Category struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	SortOrder int    `json:"sort_order"`
	Active    bool   `json:"is_active"`
	Menus     []Menu `json:"menus"`
}

type Selection struct {
	GroupID   string
	OptionIDs []string
}

func Price(menu Menu, selections []Selection) (int64, error) {
	if !menu.Available {
		return 0, unavailable("menu_id")
	}
	selected := make(map[string][]string, len(selections))
	for _, s := range selections {
		if _, exists := selected[s.GroupID]; exists {
			return 0, invalid("modifier_groups." + s.GroupID)
		}
		selected[s.GroupID] = s.OptionIDs
	}
	total := menu.PriceAmount
	for _, group := range menu.Groups {
		if !group.Active {
			if len(selected[group.ID]) > 0 {
				return 0, invalid("modifier_groups." + group.ID)
			}
			continue
		}
		ids := selected[group.ID]
		if len(ids) < group.MinSelect || len(ids) > group.MaxSelect {
			return 0, invalid("modifier_groups." + group.ID)
		}
		options := map[string]Option{}
		for _, option := range group.Options {
			options[option.ID] = option
		}
		seen := map[string]struct{}{}
		for _, id := range ids {
			option, ok := options[id]
			if !ok {
				return 0, invalid("modifier_groups." + group.ID + ".option_ids")
			}
			if !option.Available {
				return 0, unavailable("modifier_groups." + group.ID + ".option_ids")
			}
			if _, duplicate := seen[id]; duplicate {
				return 0, invalid("modifier_groups." + group.ID + ".option_ids")
			}
			seen[id] = struct{}{}
			total += option.PriceDeltaAmount
		}
		delete(selected, group.ID)
	}
	if len(selected) != 0 || total < 0 {
		return 0, invalid("modifier_groups")
	}
	return total, nil
}
