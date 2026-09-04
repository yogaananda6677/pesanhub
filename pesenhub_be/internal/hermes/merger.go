package hermes

import (
	"context"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"pesenhub/backend/internal/catalog"
)

// DraftMerger handles partial updates to DraftCandidate from customer clarification answers.
type DraftMerger struct {
	resolver *CatalogResolver
}

// NewDraftMerger creates a new DraftMerger.
func NewDraftMerger(provider CatalogProvider) *DraftMerger {
	return &DraftMerger{
		resolver: NewCatalogResolver(provider),
	}
}

var quantityRegex = regexp.MustCompile(`\b(\d+)\b`)

// MergeClarification applies customer clarification input to resolve pending ambiguity.
// Returns the updated draft and a boolean indicating whether the pending ambiguity was successfully resolved.
func (m *DraftMerger) MergeClarification(
	ctx context.Context,
	currentDraft *DraftCandidate,
	pendingAmbiguity string,
	customerAnswer string,
	categories []catalog.Category,
) (*DraftCandidate, bool, error) {
	if currentDraft == nil {
		return nil, false, fmt.Errorf("current draft cannot be nil")
	}

	answerNorm := normalizeText(customerAnswer)
	if answerNorm == "" {
		return currentDraft, false, nil
	}

	// Clone draft to avoid corrupting previous state on error
	cloned := cloneDraft(currentDraft)
	resolved := false

	switch {
	case strings.HasPrefix(pendingAmbiguity, "missing_required_modifier:"):
		groupName := strings.TrimPrefix(pendingAmbiguity, "missing_required_modifier:")
		resolved = m.applyModifierAnswer(cloned, groupName, answerNorm, categories)

	case strings.HasPrefix(pendingAmbiguity, "menu_unavailable:"):
		menuName := strings.TrimPrefix(pendingAmbiguity, "menu_unavailable:")
		resolved = m.applyMenuReplacement(ctx, cloned, menuName, answerNorm, categories)

	case strings.HasPrefix(pendingAmbiguity, "menu_not_found:"):
		menuName := strings.TrimPrefix(pendingAmbiguity, "menu_not_found:")
		resolved = m.applyMenuReplacement(ctx, cloned, menuName, answerNorm, categories)

	case strings.HasPrefix(pendingAmbiguity, "invalid_quantity:"):
		menuName := strings.TrimPrefix(pendingAmbiguity, "invalid_quantity:")
		resolved = m.applyQuantityAnswer(cloned, menuName, customerAnswer)

	case strings.HasPrefix(pendingAmbiguity, "unrecognized_modifier:"):
		resolved = m.applyUnrecognizedModifierAnswer(cloned, answerNorm)

	case pendingAmbiguity == "missing_fulfillment_type":
		resolved = m.applyFulfillmentAnswer(cloned, answerNorm)

	case pendingAmbiguity == "missing_payment_method":
		resolved = m.applyPaymentAnswer(cloned, answerNorm)

	case pendingAmbiguity == "no_valid_items_resolved" || pendingAmbiguity == "empty_order_items" || pendingAmbiguity == "empty_draft":
		resolved = m.applyFullOrderAnswer(ctx, cloned, customerAnswer)
	}

	if resolved {
		cloned.AmbiguityReasons = removeAmbiguity(cloned.AmbiguityReasons, pendingAmbiguity)
	}

	// Revalidate active catalog availability
	RevalidateAgainstCatalog(cloned, categories)

	if len(cloned.AmbiguityReasons) == 0 {
		cloned.IsAmbiguous = false
		if cloned.OverallConfidence < 0.75 {
			cloned.OverallConfidence = 0.90
		}
	} else {
		cloned.IsAmbiguous = true
	}

	recalculateTotals(cloned)

	return cloned, resolved, nil
}

// RevalidateAgainstCatalog verifies that all items and selected modifiers in the draft remain available in the catalog.
func RevalidateAgainstCatalog(draft *DraftCandidate, categories []catalog.Category) {
	if draft == nil {
		return
	}

	catalogMap := make(map[string]catalog.Menu)
	for _, cat := range categories {
		for _, m := range cat.Menus {
			catalogMap[m.ID] = m
		}
	}

	for _, it := range draft.Items {
		menu, exists := catalogMap[it.MenuID]
		if !exists || !menu.Available {
			draft.IsAmbiguous = true
			reason := fmt.Sprintf("menu_unavailable:%s", it.Name)
			draft.AmbiguityReasons = addAmbiguityIfMissing(draft.AmbiguityReasons, reason)
			continue
		}

		// Check selected modifiers availability
		optAvailMap := make(map[string]bool)
		for _, g := range menu.Groups {
			for _, opt := range g.Options {
				optAvailMap[opt.ID] = opt.Available
			}
		}

		for _, selMod := range it.SelectedModifiers {
			avail, ok := optAvailMap[selMod.OptionID]
			if !ok || !avail {
				draft.IsAmbiguous = true
				reason := fmt.Sprintf("modifier_unavailable:%s", selMod.OptionName)
				draft.AmbiguityReasons = addAmbiguityIfMissing(draft.AmbiguityReasons, reason)
			}
		}
	}
}

func (m *DraftMerger) applyModifierAnswer(draft *DraftCandidate, groupName, answerNorm string, categories []catalog.Category) bool {
	groupNameLower := strings.ToLower(groupName)

	// Find the item with this modifier group
	for i := range draft.Items {
		it := &draft.Items[i]
		for _, cat := range categories {
			for _, menu := range cat.Menus {
				if menu.ID != it.MenuID && !strings.EqualFold(menu.Name, it.Name) {
					continue
				}
				var bestOpt *catalog.Option
				var bestGroup *catalog.Group
				bestScore := 0

				for _, g := range menu.Groups {
					if !g.Active || (!strings.EqualFold(g.Name, groupName) && !strings.EqualFold(g.Code, groupName) && !strings.Contains(strings.ToLower(g.Name), groupNameLower)) {
						continue
					}
					for _, opt := range g.Options {
						if !opt.Available {
							continue
						}
						optNameNorm := normalizeText(opt.Name)
						optCodeNorm := normalizeText(opt.Code)
						score := matchOptionScore(answerNorm, optNameNorm, optCodeNorm)
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
					it.SelectedModifiers = append(it.SelectedModifiers, SelectedModifier{
						GroupID:          bestGroup.ID,
						GroupName:        bestGroup.Name,
						OptionID:         bestOpt.ID,
						OptionCode:       bestOpt.Code,
						OptionName:       bestOpt.Name,
						PriceDeltaAmount: bestOpt.PriceDeltaAmount,
					})
					it.ModifiersTotalAmount += bestOpt.PriceDeltaAmount
					it.LineTotalAmount = (it.UnitPriceAmount + it.ModifiersTotalAmount) * int64(it.Quantity)
					return true
				}
			}
		}
	}
	return false
}

func matchOptionScore(inputNorm, optNameNorm, optCodeNorm string) int {
	if inputNorm == optNameNorm || inputNorm == optCodeNorm {
		return 100
	}
	inputHasTidak := strings.Contains(inputNorm, "tidak") || strings.Contains(inputNorm, "gak") || strings.Contains(inputNorm, "nggak")
	optHasTidak := strings.Contains(optNameNorm, "tidak") || strings.Contains(optNameNorm, "gak") || strings.Contains(optNameNorm, "nggak")
	if inputHasTidak != optHasTidak {
		return 0
	}
	if strings.Contains(inputNorm, optNameNorm) || strings.Contains(optNameNorm, inputNorm) {
		return 50
	}
	return 0
}

func (m *DraftMerger) applyMenuReplacement(ctx context.Context, draft *DraftCandidate, oldMenuName, answerNorm string, categories []catalog.Category) bool {
	// If customer wants to cancel or drop this item
	cancelKeywords := []string{"batal", "batalin", "hapus", "cancel", "gak jadi", "nggak jadi"}
	for _, kw := range cancelKeywords {
		if strings.Contains(answerNorm, kw) {
			// Remove the item matching oldMenuName
			var newItems []ExtractedItem
			for _, it := range draft.Items {
				if !strings.EqualFold(it.Name, oldMenuName) && !strings.Contains(strings.ToLower(it.Name), normalizeText(oldMenuName)) {
					newItems = append(newItems, it)
				}
			}
			draft.Items = newItems
			return true
		}
	}

	// Customer specified a replacement menu
	raw := &RawExtractedOrder{
		Items: []RawExtractedItem{
			{
				MenuName:   answerNorm,
				Quantity:   1,
				Confidence: 0.90,
			},
		},
	}

	res, err := m.resolver.ResolveOrder(ctx, raw)
	if err != nil || len(res.Items) == 0 {
		return false
	}

	// Replace the old item or append
	replaced := false
	for i := range draft.Items {
		if strings.EqualFold(draft.Items[i].Name, oldMenuName) {
			draft.Items[i] = res.Items[0]
			replaced = true
			break
		}
	}
	if !replaced {
		draft.Items = append(draft.Items, res.Items[0])
	}

	if len(res.AmbiguityReasons) > 0 {
		draft.AmbiguityReasons = append(draft.AmbiguityReasons, res.AmbiguityReasons...)
	}

	return true
}

func (m *DraftMerger) applyQuantityAnswer(draft *DraftCandidate, menuName, rawAnswer string) bool {
	matches := quantityRegex.FindStringSubmatch(rawAnswer)
	var qty int
	if len(matches) >= 2 {
		qty, _ = strconv.Atoi(matches[1])
	} else {
		// Word numbers in Indonesian
		norm := normalizeText(rawAnswer)
		switch {
		case strings.Contains(norm, "satu"):
			qty = 1
		case strings.Contains(norm, "dua"):
			qty = 2
		case strings.Contains(norm, "tiga"):
			qty = 3
		case strings.Contains(norm, "empat"):
			qty = 4
		case strings.Contains(norm, "lima"):
			qty = 5
		}
	}

	if qty <= 0 {
		return false
	}

	for i := range draft.Items {
		if draft.Items[i].Name == menuName || strings.EqualFold(draft.Items[i].Name, menuName) || len(draft.Items) == 1 {
			draft.Items[i].Quantity = qty
			draft.Items[i].LineTotalAmount = (draft.Items[i].UnitPriceAmount + draft.Items[i].ModifiersTotalAmount) * int64(qty)
			return true
		}
	}
	return false
}

func (m *DraftMerger) applyUnrecognizedModifierAnswer(draft *DraftCandidate, answerNorm string) bool {
	acceptSkip := []string{"iya", "ya", "oke", "ok", "tanpa", "skip", "gapapa", "gak apa"}
	for _, kw := range acceptSkip {
		if strings.Contains(answerNorm, kw) {
			return true
		}
	}
	return false
}

func (m *DraftMerger) applyFulfillmentAnswer(draft *DraftCandidate, answerNorm string) bool {
	switch {
	case strings.Contains(answerNorm, "takeaway") || strings.Contains(answerNorm, "pickup") || strings.Contains(answerNorm, "bungkus") || strings.Contains(answerNorm, "bawa pulang") || strings.Contains(answerNorm, "ambil sendiri"):
		draft.FulfillmentType = "PICKUP"
		return true
	case strings.Contains(answerNorm, "dine in") || strings.Contains(answerNorm, "makan di tempat") || strings.Contains(answerNorm, "disini") || strings.Contains(answerNorm, "di tempat"):
		draft.FulfillmentType = "DINE_IN"
		return true
	case strings.Contains(answerNorm, "delivery") || strings.Contains(answerNorm, "antar") || strings.Contains(answerNorm, "kirim") || strings.Contains(answerNorm, "ojek"):
		draft.FulfillmentType = "DELIVERY"
		return true
	}
	return false
}

func (m *DraftMerger) applyPaymentAnswer(draft *DraftCandidate, answerNorm string) bool {
	switch {
	case strings.Contains(answerNorm, "tunai") || strings.Contains(answerNorm, "cash") || strings.Contains(answerNorm, "kasir"):
		draft.PaymentMethod = "CASH"
		return true
	case strings.Contains(answerNorm, "qris") || strings.Contains(answerNorm, "scan") || strings.Contains(answerNorm, "gopay") || strings.Contains(answerNorm, "ovo") || strings.Contains(answerNorm, "dana") || strings.Contains(answerNorm, "shopee"):
		draft.PaymentMethod = "QRIS"
		return true
	case strings.Contains(answerNorm, "transfer") || strings.Contains(answerNorm, "tf") || strings.Contains(answerNorm, "bca") || strings.Contains(answerNorm, "mandiri"):
		draft.PaymentMethod = "TRANSFER"
		return true
	}
	return false
}

func (m *DraftMerger) applyFullOrderAnswer(ctx context.Context, draft *DraftCandidate, rawMessage string) bool {
	raw := &RawExtractedOrder{
		Items: []RawExtractedItem{
			{
				MenuName:   rawMessage,
				Quantity:   1,
				Confidence: 0.90,
			},
		},
	}
	res, err := m.resolver.ResolveOrder(ctx, raw)
	if err != nil || len(res.Items) == 0 {
		return false
	}
	draft.Items = res.Items
	draft.AmbiguityReasons = res.AmbiguityReasons
	return true
}

func cloneDraft(d *DraftCandidate) *DraftCandidate {
	cloned := *d
	cloned.Items = make([]ExtractedItem, len(d.Items))
	for i, it := range d.Items {
		itemCopy := it
		itemCopy.SelectedModifiers = make([]SelectedModifier, len(it.SelectedModifiers))
		copy(itemCopy.SelectedModifiers, it.SelectedModifiers)
		cloned.Items[i] = itemCopy
	}
	cloned.AmbiguityReasons = make([]string, len(d.AmbiguityReasons))
	copy(cloned.AmbiguityReasons, d.AmbiguityReasons)
	return &cloned
}

func removeAmbiguity(reasons []string, target string) []string {
	var result []string
	for _, r := range reasons {
		if r != target {
			result = append(result, r)
		}
	}
	return result
}

func addAmbiguityIfMissing(reasons []string, target string) []string {
	for _, r := range reasons {
		if r == target {
			return reasons
		}
	}
	return append(reasons, target)
}

func recalculateTotals(d *DraftCandidate) {
	var subtotal int64
	for _, it := range d.Items {
		subtotal += it.LineTotalAmount
	}
	d.SubtotalAmount = subtotal
	d.TotalAmount = subtotal
}
