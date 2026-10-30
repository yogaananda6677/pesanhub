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
	ListPublic(ctx context.Context, categoryID string, branchID ...string) ([]catalog.Category, error)
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
	lower = strings.ReplaceAll(lower, "terangbulan", "terang bulan")
	lower = strings.ReplaceAll(lower, "marteltelur", "martabak telur")
	cleaned := nonAlphanumericRegex.ReplaceAllString(lower, " ")
	fields := strings.Fields(cleaned)
	normalized := strings.Join(fields, " ")

	// Common Indonesian food aliases
	switch normalized {
	case "nasgor":
		return "nasi goreng"
	case "miegor":
		return "mie goreng"
	case "terbul", "terang bulan":
		return "terang bulan"
	case "martabak", "martabak telor", "marteg", "martel":
		return "martabak telur"
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

	var allTexts []string
	allTexts = append(allTexts, rawItem.MenuName)
	allTexts = append(allTexts, rawItem.Modifiers...)
	combinedNorm := normalizeText(strings.Join(allTexts, " "))

	var matchedMenu *catalog.Menu
	var matchedCat *catalog.Category

	// Search in categories
	// First pass: exact match with category+menu, menu name, or SKU
	for _, cat := range categories {
		for _, m := range cat.Menus {
			menuNorm := normalizeText(m.Name)
			skuNorm := normalizeText(m.SKU)
			fullMenuNorm := normalizeText(cat.Name + " " + m.Name)

			if rawNameNorm == fullMenuNorm || rawNameNorm == menuNorm || rawNameNorm == skuNorm ||
				combinedNorm == fullMenuNorm || combinedNorm == menuNorm {
				menuCopy := m
				catCopy := cat
				matchedMenu = &menuCopy
				matchedCat = &catCopy
				break
			}
		}
		if matchedMenu != nil {
			break
		}
	}

	// Second pass: full category + menu containment (more specific than menu only)
	if matchedMenu == nil {
		for _, cat := range categories {
			for _, m := range cat.Menus {
				fullMenuNorm := normalizeText(cat.Name + " " + m.Name)
				if strings.Contains(rawNameNorm, fullMenuNorm) || strings.Contains(fullMenuNorm, rawNameNorm) ||
					strings.Contains(combinedNorm, fullMenuNorm) {
					menuCopy := m
					catCopy := cat
					matchedMenu = &menuCopy
					matchedCat = &catCopy
					break
				}
			}
			if matchedMenu != nil {
				break
			}
		}
	}

	// Smart Pass for Martabak Telur: Match Isian (Sapi, Ayam, Sosis, Jamur, Moza) + Level (Biasa, Spesial, Istimewa)
	if matchedMenu == nil {
		for _, cat := range categories {
			catLower := strings.ToLower(cat.Name)
			catMatched := false
			if strings.Contains(combinedNorm, "sapi") && strings.Contains(catLower, "sapi") {
				catMatched = true
			} else if strings.Contains(combinedNorm, "ayam") && strings.Contains(catLower, "ayam") {
				catMatched = true
			} else if strings.Contains(combinedNorm, "sosis") && strings.Contains(catLower, "sosis") {
				catMatched = true
			} else if strings.Contains(combinedNorm, "jamur") && strings.Contains(catLower, "jamur") {
				catMatched = true
			} else if (strings.Contains(combinedNorm, "moza") || strings.Contains(combinedNorm, "mozarella")) && (strings.Contains(catLower, "moza") || strings.Contains(catLower, "mozarella")) {
				catMatched = true
			}

			if catMatched {
				for _, m := range cat.Menus {
					mLower := strings.ToLower(m.Name)
					if strings.Contains(combinedNorm, "istimewa") && strings.Contains(mLower, "istimewa") {
						menuCopy := m
						catCopy := cat
						matchedMenu = &menuCopy
						matchedCat = &catCopy
						break
					} else if strings.Contains(combinedNorm, "spesial") && strings.Contains(mLower, "spesial") {
						menuCopy := m
						catCopy := cat
						matchedMenu = &menuCopy
						matchedCat = &catCopy
						break
					} else if strings.Contains(combinedNorm, "biasa") && strings.Contains(mLower, "biasa") {
						menuCopy := m
						catCopy := cat
						matchedMenu = &menuCopy
						matchedCat = &catCopy
						break
					}
				}
				// Default to Biasa if level not specified in text
				if matchedMenu == nil {
					for _, m := range cat.Menus {
						if strings.Contains(strings.ToLower(m.Name), "biasa") || strings.Contains(strings.ToLower(m.Name), "1 isian") {
							menuCopy := m
							catCopy := cat
							matchedMenu = &menuCopy
							matchedCat = &catCopy
							break
						}
					}
				}
				if matchedMenu != nil {
					break
				}
			}
		}
	}

	// Smart Pass for Terang Bulan: Match Topping Count & Size (Biasa vs Besar)
	if matchedMenu == nil && (strings.Contains(combinedNorm, "terang bulan") || strings.Contains(combinedNorm, "terbul") || strings.Contains(combinedNorm, "toping") || strings.Contains(combinedNorm, "topping") || strings.Contains(combinedNorm, "pizza")) {
		for _, cat := range categories {
			catLower := strings.ToLower(cat.Name)
			if !strings.Contains(catLower, "terang bulan") && !strings.Contains(catLower, "terbul") {
				continue
			}

			isBesar := strings.Contains(combinedNorm, "besar")
			isPizza := strings.Contains(combinedNorm, "pizza") || strings.Contains(combinedNorm, "all in one")
			if isPizza {
				for _, m := range cat.Menus {
					if strings.Contains(strings.ToLower(m.Name), "pizza") {
						menuCopy := m
						catCopy := cat
						matchedMenu = &menuCopy
						matchedCat = &catCopy
						break
					}
				}
				if matchedMenu != nil {
					break
				}
			}

			toppingCount := 1
			if strings.Contains(combinedNorm, "3 toping") || strings.Contains(combinedNorm, "3 topping") || strings.Contains(combinedNorm, "tiga toping") || strings.Contains(combinedNorm, "tiga topping") ||
				strings.Contains(combinedNorm, "3 biasa") || strings.Contains(combinedNorm, "3 besar") || strings.Contains(combinedNorm, "tiga biasa") || strings.Contains(combinedNorm, "tiga besar") {
				toppingCount = 3
			} else if strings.Contains(combinedNorm, "2 toping") || strings.Contains(combinedNorm, "2 topping") || strings.Contains(combinedNorm, "dua toping") || strings.Contains(combinedNorm, "dua topping") ||
				strings.Contains(combinedNorm, "2 biasa") || strings.Contains(combinedNorm, "2 besar") || strings.Contains(combinedNorm, "dua biasa") || strings.Contains(combinedNorm, "dua besar") {
				toppingCount = 2
			} else if strings.Contains(combinedNorm, "1 toping") || strings.Contains(combinedNorm, "1 topping") || strings.Contains(combinedNorm, "satu toping") || strings.Contains(combinedNorm, "satu topping") ||
				strings.Contains(combinedNorm, "1 biasa") || strings.Contains(combinedNorm, "1 besar") || strings.Contains(combinedNorm, "satu biasa") || strings.Contains(combinedNorm, "satu besar") {
				toppingCount = 1
			} else {
				flavorCount := countTerangBulanToppings(combinedNorm)
				if flavorCount >= 3 {
					toppingCount = 3
				} else if flavorCount == 2 {
					toppingCount = 2
				} else if len(rawItem.Modifiers) >= 3 {
					toppingCount = 3
				} else if len(rawItem.Modifiers) == 2 {
					toppingCount = 2
				}
			}

			sizeKeyword := "Biasa"
			if isBesar {
				sizeKeyword = "Besar"
			}
			targetName := fmt.Sprintf("%d Toping - %s", toppingCount, sizeKeyword)
			targetWithHyphen := fmt.Sprintf("%d toping - %s", toppingCount, strings.ToLower(sizeKeyword))
			targetWithoutHyphen := fmt.Sprintf("%d toping %s", toppingCount, strings.ToLower(sizeKeyword))
			for _, m := range cat.Menus {
				mNorm := strings.ToLower(m.Name)
				topingStr := fmt.Sprintf("%d toping", toppingCount)
				toppingStr := fmt.Sprintf("%d topping", toppingCount)
				sizeStr := strings.ToLower(sizeKeyword)

				if strings.EqualFold(m.Name, targetName) ||
					strings.Contains(mNorm, targetWithHyphen) ||
					strings.Contains(mNorm, targetWithoutHyphen) ||
					((strings.Contains(mNorm, topingStr) || strings.Contains(mNorm, toppingStr)) && strings.Contains(mNorm, sizeStr)) {
					menuCopy := m
					catCopy := cat
					matchedMenu = &menuCopy
					matchedCat = &catCopy
					break
				}
			}
			if matchedMenu != nil {
				break
			}
		}
	}

	// Third pass: menu name substring / word boundary match
	if matchedMenu == nil {
		for _, cat := range categories {
			for _, m := range cat.Menus {
				menuNorm := normalizeText(m.Name)
				if strings.Contains(menuNorm, rawNameNorm) || strings.Contains(rawNameNorm, menuNorm) ||
					strings.Contains(combinedNorm, menuNorm) {
					menuCopy := m
					catCopy := cat
					matchedMenu = &menuCopy
					matchedCat = &catCopy
					break
				}
			}
			if matchedMenu != nil {
				break
			}
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
	selectedModifiers, modTotal, modAmbiguities := r.resolveModifiers(rawItem.Modifiers, matchedMenu.Groups, matchedMenu, matchedCat)
	if len(modAmbiguities) > 0 {
		ambiguities = append(ambiguities, modAmbiguities...)
	}

	lineTotal := (matchedMenu.PriceAmount + modTotal) * int64(qty)

	conf := rawItem.Confidence
	if conf <= 0 {
		conf = 0.8
	}

	displayName := matchedMenu.Name
	if matchedCat != nil && matchedCat.Name != "" {
		catLower := strings.ToLower(matchedCat.Name)
		if strings.Contains(catLower, "terang bulan") {
			if !strings.Contains(strings.ToLower(displayName), "terang bulan") {
				displayName = fmt.Sprintf("Terang Bulan %s", matchedMenu.Name)
			}
		} else if strings.Contains(catLower, "martel") {
			if !strings.Contains(strings.ToLower(displayName), "martel") {
				displayName = fmt.Sprintf("Martel Mozarella %s", matchedMenu.Name)
			}
		} else {
			displayName = fmt.Sprintf("Martabak %s - %s", matchedCat.Name, matchedMenu.Name)
		}
	}

	extracted := &ExtractedItem{
		MenuID:               matchedMenu.ID,
		SKU:                  matchedMenu.SKU,
		Name:                 displayName,
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

func isRedundantModifier(rawMod string, menu *catalog.Menu, cat *catalog.Category) bool {
	modNorm := normalizeText(rawMod)
	if modNorm == "" {
		return true
	}
	if menu != nil {
		menuNorm := normalizeText(menu.Name)
		if modNorm == menuNorm || strings.Contains(menuNorm, modNorm) || strings.Contains(modNorm, menuNorm) {
			return true
		}
	}
	if cat != nil {
		catNorm := normalizeText(cat.Name)
		if modNorm == catNorm || strings.Contains(catNorm, modNorm) || strings.Contains(modNorm, catNorm) {
			return true
		}
	}
	switch modNorm {
	case "biasa", "spesial", "special", "istimewa", "besar", "kecil", "sedang", "standar", "standard":
		return true
	case "1 isian", "mix 2", "mix 3", "mix 4", "isian", "moza", "mozarella":
		return true
	case "1 toping", "2 toping", "3 toping", "toping", "topping", "1 topping", "2 topping", "3 topping":
		return true
	case "martabak", "martabak telur", "martel", "terang bulan", "terbul", "manis", "asin", "gurih":
		return true
	case "daging", "sapi", "daging sapi", "ayam", "daging ayam", "sosis", "jamur", "sosis jamur":
		return true
	case "porsi", "biji", "buah", "bungkus", "takeaway", "pickup", "dine in", "cut pizza", "all in one", "pizza":
		return true
	}
	// Check if only a number
	if _, err := regexp.MatchString(`^\d+$`, modNorm); err == nil {
		var isDigitOnly = true
		for _, r := range modNorm {
			if r < '0' || r > '9' {
				isDigitOnly = false
				break
			}
		}
		if isDigitOnly {
			return true
		}
	}
	return false
}

func countTerangBulanToppings(text string) int {
	toppings := []string{"coklat", "keju", "pisang", "oreo", "kacang", "strawberry", "blueberry", "goldenfill", "meses", "susu", "nutella"}
	count := 0
	for _, top := range toppings {
		if strings.Contains(text, top) {
			count++
		}
	}
	return count
}

func isTerangBulan(name string) bool {
	lower := strings.ToLower(name)
	return strings.Contains(lower, "terang bulan") || strings.Contains(lower, "terbul") || strings.Contains(lower, "toping") || strings.Contains(lower, "topping") || strings.Contains(lower, "pizza")
}

func isMartabak(name string) bool {
	lower := strings.ToLower(name)
	return strings.Contains(lower, "martabak") || strings.Contains(lower, "martel")
}

// expectedToppingCount returns the expected minimum and maximum selection for a modifier group.
// It inspects the menu name for explicit topping counts (1, 2, 3 Toping / Mix 2) if it's a topping group.
func expectedToppingCount(menuName string, g *catalog.Group) (int, int) {
	minSel := g.MinSelect
	maxSel := g.MaxSelect

	nameLower := strings.ToLower(menuName)
	groupLower := strings.ToLower(g.Name)
	if strings.Contains(groupLower, "toping") || strings.Contains(groupLower, "topping") {
		if strings.Contains(nameLower, "1 toping") || strings.Contains(nameLower, "1 topping") {
			return 1, 1
		}
		if strings.Contains(nameLower, "2 toping") || strings.Contains(nameLower, "2 topping") || strings.Contains(nameLower, "mix 2") {
			return 2, 2
		}
		if strings.Contains(nameLower, "3 toping") || strings.Contains(nameLower, "3 topping") || strings.Contains(nameLower, "mix 3") {
			return 3, 3
		}
	}
	return minSel, maxSel
}

// containsOptionMatch checks if an option is mentioned in text, avoiding false positives (e.g. tidak pedas vs pedas).
func containsOptionMatch(textNorm, optNameNorm, optCodeNorm string) bool {
	if textNorm == optNameNorm || textNorm == optCodeNorm {
		return true
	}
	// Check pedas negation
	if (optNameNorm == "pedas" || optCodeNorm == "hot") &&
		(strings.Contains(textNorm, "tidak pedas") || strings.Contains(textNorm, "gak pedas") || strings.Contains(textNorm, "nggak pedas")) {
		return false
	}
	// Sub-phrase for multi-word option
	if strings.Contains(textNorm, optNameNorm) || strings.Contains(textNorm, optCodeNorm) {
		return true
	}
	// Aliases
	if strings.Contains(optNameNorm, "strawberry") && (strings.Contains(textNorm, "strawberry") || strings.Contains(textNorm, "stroberi")) {
		return true
	}
	if strings.Contains(optNameNorm, "blueberry") && (strings.Contains(textNorm, "blueberry") || strings.Contains(textNorm, "bluberi")) {
		return true
	}
	// Word match
	words := strings.Fields(textNorm)
	for _, w := range words {
		cleaned := strings.Trim(w, ",.!?")
		if cleaned == optNameNorm || cleaned == optCodeNorm {
			return true
		}
	}
	return false
}

// findMatchingOptionsInGroup extracts all distinct available options from a group present in the text.
func findMatchingOptionsInGroup(text string, g *catalog.Group) []catalog.Option {
	textNorm := normalizeText(text)
	if textNorm == "" {
		return nil
	}
	var matched []catalog.Option
	seen := make(map[string]bool)

	for _, opt := range g.Options {
		if !opt.Available || seen[opt.ID] {
			continue
		}
		optNorm := normalizeText(opt.Name)
		codeNorm := normalizeText(opt.Code)
		if containsOptionMatch(textNorm, optNorm, codeNorm) {
			matched = append(matched, opt)
			seen[opt.ID] = true
		}
	}
	return matched
}

func (r *CatalogResolver) resolveModifiers(rawModifiers []string, groups []catalog.Group, matchedMenu *catalog.Menu, matchedCat *catalog.Category) ([]SelectedModifier, int64, []string) {
	var selected []SelectedModifier
	var totalDelta int64
	var ambiguities []string

	selectedPerGroup := make(map[string]int)
	selectedOptionIDs := make(map[string]bool)
	matchedRawMods := make(map[int]bool)

	combinedRaw := strings.Join(rawModifiers, " ")

	// 1. First pass: Multi-option group extraction for all active groups
	for _, g := range groups {
		if !g.Active {
			continue
		}
		matchedOpts := findMatchingOptionsInGroup(combinedRaw, &g)
		for _, opt := range matchedOpts {
			if selectedOptionIDs[opt.ID] {
				continue
			}
			selected = append(selected, SelectedModifier{
				GroupID:          g.ID,
				GroupName:        g.Name,
				OptionID:         opt.ID,
				OptionCode:       opt.Code,
				OptionName:       opt.Name,
				PriceDeltaAmount: opt.PriceDeltaAmount,
			})
			totalDelta += opt.PriceDeltaAmount
			selectedPerGroup[g.ID]++
			selectedOptionIDs[opt.ID] = true
		}
	}

	// 2. Mark which rawModifiers were recognized
	for idx, rawMod := range rawModifiers {
		rawModNorm := normalizeText(rawMod)
		if rawModNorm == "" {
			matchedRawMods[idx] = true
			continue
		}
		for _, sm := range selected {
			optNameNorm := normalizeText(sm.OptionName)
			optCodeNorm := normalizeText(sm.OptionCode)
			if containsOptionMatch(rawModNorm, optNameNorm, optCodeNorm) {
				matchedRawMods[idx] = true
				break
			}
		}
		if !matchedRawMods[idx] {
			if !isRedundantModifier(rawMod, matchedMenu, matchedCat) {
				ambiguities = append(ambiguities, fmt.Sprintf("unrecognized_modifier:%s", rawMod))
			}
		}
	}

	// 3. Check modifier group constraints (min_select, max_select)
	for _, g := range groups {
		if !g.Active {
			continue
		}
		minSel, maxSel := expectedToppingCount(matchedMenu.Name, &g)
		count := selectedPerGroup[g.ID]

		// Auto-select standard default option (e.g. Original Base Cake with 0 price delta) if none was chosen
		if minSel >= 1 && count < minSel {
			var defaultOpt *catalog.Option
			for _, opt := range g.Options {
				if !opt.Available {
					continue
				}
				optNorm := normalizeText(opt.Name)
				codeNorm := normalizeText(opt.Code)
				if (optNorm == "original" || codeNorm == "original" || optNorm == "standar" || optNorm == "biasa") && opt.PriceDeltaAmount == 0 {
					optCopy := opt
					defaultOpt = &optCopy
					break
				}
			}
			if defaultOpt != nil {
				selected = append(selected, SelectedModifier{
					GroupID:          g.ID,
					GroupName:        g.Name,
					OptionID:         defaultOpt.ID,
					OptionCode:       defaultOpt.Code,
					OptionName:       defaultOpt.Name,
					PriceDeltaAmount: defaultOpt.PriceDeltaAmount,
				})
				totalDelta += defaultOpt.PriceDeltaAmount
				selectedPerGroup[g.ID]++
				count++
			}
		}

		if minSel >= 1 && count < minSel {
			if count == 0 {
				ambiguities = append(ambiguities, fmt.Sprintf("missing_required_modifier:%s", g.Name))
			} else {
				ambiguities = append(ambiguities, fmt.Sprintf("insufficient_toppings:%s:%d:%d", g.Name, minSel, count))
			}
		}
		if maxSel > 0 && count > maxSel {
			ambiguities = append(ambiguities, fmt.Sprintf("modifier_limit_exceeded:%s:%d:%d", g.Name, maxSel, count))
		}
	}

	return selected, totalDelta, ambiguities
}
