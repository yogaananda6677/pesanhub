package hermes

import (
	"context"
	"fmt"
	"regexp"
	"strings"

	"pesenhub/backend/internal/catalog"
)

// CatalogProvider represents the interface needed to fetch active catalog items.
type CatalogProvider interface {
	ListPublic(ctx context.Context, categoryID string) ([]catalog.Category, error)
}

// CatalogResolver resolves extracted items against the active catalog.
type CatalogResolver struct {
	provider CatalogProvider
}

// NewCatalogResolver creates a new CatalogResolver.
func NewCatalogResolver(provider CatalogProvider) *CatalogResolver {
	return &CatalogResolver{provider: provider}
}

var nonAlphanumericRegex = regexp.MustCompile(`[^a-z0-9\s]`)

func normalizeText(s string) string {
	lower := strings.ToLower(strings.TrimSpace(s))
	cleaned := nonAlphanumericRegex.ReplaceAllString(lower, " ")
	fields := strings.Fields(cleaned)
	normalized := strings.Join(fields, " ")

	// Common Indonesian food aliases
	switch normalized {
	case "nasgor":
		return "nasi goreng"
	case "miegor":
		return "mie goreng"
	case "esteh", "es teh manis":
		return "es teh"
	}
	return normalized
}

// ResolveResult contains the resolved items and any ambiguity reasons found during catalog resolution.
type ResolveResult struct {
	Items            []ExtractedItem
	AmbiguityReasons []string
	IsAmbiguous      bool
}

// ResolveOrder matches raw extracted items to active catalog items and computes exact prices.
func (r *CatalogResolver) ResolveOrder(ctx context.Context, raw *RawExtractedOrder) (*ResolveResult, error) {
	categories, err := r.provider.ListPublic(ctx, "")
	if err != nil {
		return nil, fmt.Errorf("failed to fetch catalog: %w", err)
	}

	result := &ResolveResult{
		Items:            make([]ExtractedItem, 0, len(raw.Items)),
		AmbiguityReasons: make([]string, 0),
	}

	if len(raw.Items) == 0 {
		result.IsAmbiguous = true
		result.AmbiguityReasons = append(result.AmbiguityReasons, "empty_order_items")
		return result, nil
	}

	for _, rawItem := range raw.Items {
		item, ambiguities := r.resolveItem(rawItem, categories)
		if len(ambiguities) > 0 {
			result.IsAmbiguous = true
			result.AmbiguityReasons = append(result.AmbiguityReasons, ambiguities...)
		}
		if item != nil {
			result.Items = append(result.Items, *item)
		}
	}

	return result, nil
}

func (r *CatalogResolver) resolveItem(rawItem RawExtractedItem, categories []catalog.Category) (*ExtractedItem, []string) {
	var ambiguities []string
	rawNameNorm := normalizeText(rawItem.MenuName)

	var matchedMenu *catalog.Menu
	// Search in categories
	for _, cat := range categories {
		for _, m := range cat.Menus {
			menuNorm := normalizeText(m.Name)
			skuNorm := normalizeText(m.SKU)

			// Exact match or alias match
			if rawNameNorm == menuNorm || rawNameNorm == skuNorm {
				menuCopy := m
				matchedMenu = &menuCopy
				break
			}
			// Substring / word boundary match
			if strings.Contains(menuNorm, rawNameNorm) || strings.Contains(rawNameNorm, menuNorm) {
				menuCopy := m
				matchedMenu = &menuCopy
				break
			}
		}
		if matchedMenu != nil {
			break
		}
	}

	if matchedMenu == nil {
		ambiguities = append(ambiguities, fmt.Sprintf("menu_not_found:%s", rawItem.MenuName))
		return nil, ambiguities
	}

	if !matchedMenu.Available {
		ambiguities = append(ambiguities, fmt.Sprintf("menu_unavailable:%s", matchedMenu.Name))
		return nil, ambiguities
	}

	qty := rawItem.Quantity
	if qty <= 0 {
		ambiguities = append(ambiguities, fmt.Sprintf("invalid_quantity:%s", matchedMenu.Name))
		qty = 1
	}

	// Match modifiers
	selectedModifiers, modTotal, modAmbiguities := r.resolveModifiers(rawItem.Modifiers, matchedMenu.Groups)
	if len(modAmbiguities) > 0 {
		ambiguities = append(ambiguities, modAmbiguities...)
	}

	lineTotal := (matchedMenu.PriceAmount + modTotal) * int64(qty)

	conf := rawItem.Confidence
	if conf <= 0 {
		conf = 0.8
	}

	extracted := &ExtractedItem{
		MenuID:               matchedMenu.ID,
		SKU:                  matchedMenu.SKU,
		Name:                 matchedMenu.Name,
		Quantity:             qty,
		UnitPriceAmount:      matchedMenu.PriceAmount,
		ModifiersTotalAmount: modTotal,
		LineTotalAmount:      lineTotal,
		SelectedModifiers:    selectedModifiers,
		Notes:                strings.TrimSpace(rawItem.Notes),
		Confidence:           conf,
	}

	return extracted, ambiguities
}

func (r *CatalogResolver) resolveModifiers(rawModifiers []string, groups []catalog.Group) ([]SelectedModifier, int64, []string) {
	var selected []SelectedModifier
	var totalDelta int64
	var ambiguities []string

	selectedPerGroup := make(map[string]int)

	for _, rawMod := range rawModifiers {
		rawModNorm := normalizeText(rawMod)
		if rawModNorm == "" {
			continue
		}

		var bestOpt *catalog.Option
		var bestGroup *catalog.Group
		bestScore := 0

		for _, g := range groups {
			if !g.Active {
				continue
			}
			for _, opt := range g.Options {
				if !opt.Available {
					continue
				}
				optNorm := normalizeText(opt.Name)
				codeNorm := normalizeText(opt.Code)
				score := matchOptionScore(rawModNorm, optNorm, codeNorm)
				if score > bestScore {
					bestScore = score
					optCopy := opt
					bestOpt = &optCopy
					gCopy := g
					bestGroup = &gCopy
				}
			}
		}

		if bestOpt != nil && bestScore > 0 {
			selected = append(selected, SelectedModifier{
				GroupID:          bestGroup.ID,
				GroupName:        bestGroup.Name,
				OptionID:         bestOpt.ID,
				OptionCode:       bestOpt.Code,
				OptionName:       bestOpt.Name,
				PriceDeltaAmount: bestOpt.PriceDeltaAmount,
			})
			totalDelta += bestOpt.PriceDeltaAmount
			selectedPerGroup[bestGroup.ID]++
		} else {
			// Unknown modifier mentioned by customer
			ambiguities = append(ambiguities, fmt.Sprintf("unrecognized_modifier:%s", rawMod))
		}
	}

	// Check modifier group constraints (min_select, max_select)
	for _, g := range groups {
		if !g.Active {
			continue
		}
		count := selectedPerGroup[g.ID]
		if g.MinSelect >= 1 && count < g.MinSelect {
			ambiguities = append(ambiguities, fmt.Sprintf("missing_required_modifier:%s", g.Name))
		}
		if g.MaxSelect > 0 && count > g.MaxSelect {
			ambiguities = append(ambiguities, fmt.Sprintf("modifier_limit_exceeded:%s", g.Name))
		}
	}

	return selected, totalDelta, ambiguities
}
