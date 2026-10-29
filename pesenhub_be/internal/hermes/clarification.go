package hermes

import (
	"fmt"
	"strings"

	"pesenhub/backend/internal/catalog"
)

// ClarificationEngine prioritizes ambiguities and builds focused questions.
type ClarificationEngine struct {
	maxAttempts int
}

// NewClarificationEngine creates a new ClarificationEngine.
func NewClarificationEngine(maxAttempts int) *ClarificationEngine {
	if maxAttempts <= 0 {
		maxAttempts = MaxClarificationAttempts
	}
	return &ClarificationEngine{maxAttempts: maxAttempts}
}

// PlanClarification selects the highest priority blocking ambiguity and builds a single targeted question.
func (e *ClarificationEngine) PlanClarification(draft *DraftCandidate, attempts int, categories []catalog.Category) *ClarificationPlan {
	if draft == nil {
		return &ClarificationPlan{
			RequiresClarification: true,
			PriorityAmbiguity:     "empty_draft",
			QuestionText:          "Halo kak! Ada yang bisa kami bantu? Mau pesan makanan atau minuman apa hari ini?",
		}
	}

	// 1. Check if bounded retry limit reached
	if attempts >= e.maxAttempts {
		return &ClarificationPlan{
			RequiresClarification: false,
			RequiresHandoff:       true,
			HandoffReason:         "max_clarification_attempts_exceeded",
			QuestionText:          "Mohon maaf kak, agar pesanannya tidak salah paham, percakapan ini kami teruskan ke staf kami ya. Mohon ditunggu sebentar.",
		}
	}

	// 2. Check for security/prompt injection ambiguity
	for _, r := range draft.AmbiguityReasons {
		if strings.HasPrefix(r, "prompt_injection_detected") {
			return &ClarificationPlan{
				RequiresClarification: false,
				RequiresHandoff:       true,
				HandoffReason:         "prompt_injection_detected",
				QuestionText:          "Mohon maaf kak, permintaan tersebut tidak dapat diproses. Percakapan ini dialihkan ke staf kami.",
			}
		}
	}

	// Filter out non-blocking confidence flags if all items have valid MenuIDs and no missing required modifiers
	allItemsGrounded := len(draft.Items) > 0
	for _, it := range draft.Items {
		if it.MenuID == "" {
			allItemsGrounded = false
			break
		}
	}
	hasHardAmbiguity := false
	var hardReasons []string
	for _, r := range draft.AmbiguityReasons {
		if strings.HasPrefix(r, "menu_unavailable") || strings.HasPrefix(r, "menu_not_found") ||
			strings.HasPrefix(r, "missing_required_modifier") || strings.HasPrefix(r, "insufficient_toppings") ||
			strings.HasPrefix(r, "invalid_quantity") ||
			strings.HasPrefix(r, "unrecognized_modifier") || strings.HasPrefix(r, "modifier_limit_exceeded") ||
			strings.HasPrefix(r, "excess_toppings") ||
			strings.HasPrefix(r, "empty_order_items") || strings.HasPrefix(r, "no_valid_items_resolved") {
			hasHardAmbiguity = true
			hardReasons = append(hardReasons, r)
		} else if !allItemsGrounded {
			hardReasons = append(hardReasons, r)
		}
	}

	if allItemsGrounded && !hasHardAmbiguity {
		draft.AmbiguityReasons = []string{}
		draft.IsAmbiguous = false
	} else if len(hardReasons) > 0 {
		draft.AmbiguityReasons = hardReasons
	}

	// 3. Find highest priority ambiguity from list
	chosenAmbiguity := e.pickPriorityAmbiguity(draft.AmbiguityReasons)

	// If no explicit ambiguity reasons but draft.IsAmbiguous is true
	if chosenAmbiguity == "" && draft.IsAmbiguous {
		if len(draft.Items) == 0 {
			chosenAmbiguity = "empty_order_items"
		} else {
			chosenAmbiguity = "low_overall_confidence"
		}
	}

	// If draft items are unambiguous, fulfillment is always 100% PICKUP (Takeaway / Bawa Pulang). Never ask for Dine In.
	if strings.TrimSpace(draft.FulfillmentType) == "" {
		draft.FulfillmentType = "PICKUP"
	}
	if chosenAmbiguity == "" || chosenAmbiguity == "missing_fulfillment_type" {
		if strings.TrimSpace(draft.PaymentMethod) == "" {
			chosenAmbiguity = "missing_payment_method"
		} else {
			chosenAmbiguity = ""
		}
	}

	if chosenAmbiguity == "" {
		// All details complete and unambiguous!
		return &ClarificationPlan{
			RequiresClarification: false,
		}
	}

	return e.buildQuestion(chosenAmbiguity, draft, categories)
}

// pickPriorityAmbiguity sorts ambiguities and returns the single most blocking one.
func (e *ClarificationEngine) pickPriorityAmbiguity(reasons []string) string {
	// Priority hierarchy:
	// 1. menu_unavailable
	// 2. menu_not_found
	// 3. missing_required_modifier / insufficient_toppings
	// 4. invalid_quantity
	// 5. unrecognized_modifier / modifier_limit_exceeded / excess_toppings
	// 6. empty_order_items / no_valid_items_resolved
	// 7. low_item_confidence / uncertainty_detected / confidence_below_threshold

	var topReason string
	topRank := 999

	for _, r := range reasons {
		rank := 100
		if strings.HasPrefix(r, "menu_unavailable") {
			rank = 1
		} else if strings.HasPrefix(r, "menu_not_found") {
			rank = 2
		} else if strings.HasPrefix(r, "missing_required_modifier") || strings.HasPrefix(r, "insufficient_toppings") {
			rank = 3
		} else if strings.HasPrefix(r, "invalid_quantity") {
			rank = 4
		} else if strings.HasPrefix(r, "unrecognized_modifier") || strings.HasPrefix(r, "modifier_limit_exceeded") || strings.HasPrefix(r, "excess_toppings") {
			rank = 5
		} else if strings.HasPrefix(r, "empty_order_items") || strings.HasPrefix(r, "no_valid_items_resolved") {
			rank = 6
		} else if strings.HasPrefix(r, "low_item_confidence") || strings.HasPrefix(r, "uncertainty_detected") || strings.HasPrefix(r, "confidence_below_threshold") {
			rank = 7
		}

		if rank < topRank {
			topRank = rank
			topReason = r
		}
	}

	return topReason
}

func (e *ClarificationEngine) buildQuestion(ambiguity string, draft *DraftCandidate, categories []catalog.Category) *ClarificationPlan {
	plan := &ClarificationPlan{
		RequiresClarification: true,
		PriorityAmbiguity:     ambiguity,
	}

	switch {
	case strings.HasPrefix(ambiguity, "menu_unavailable:"):
		menuName := strings.TrimPrefix(ambiguity, "menu_unavailable:")
		plan.TargetMenuName = menuName
		plan.QuestionText = fmt.Sprintf("Mohon maaf kak, menu %s saat ini sedang habis. Apakah mau diganti dengan menu lain atau dibatalkan kak?", menuName)

	case strings.HasPrefix(ambiguity, "menu_not_found:"):
		menuName := strings.TrimPrefix(ambiguity, "menu_not_found:")
		plan.TargetMenuName = menuName
		plan.QuestionText = fmt.Sprintf("Mohon maaf kak, menu %s belum ada di daftar menu kami. Bisa tolong sebutkan pilihan menu lainnya kak?", menuName)

	case strings.HasPrefix(ambiguity, "insufficient_toppings:") || strings.HasPrefix(ambiguity, "missing_required_modifier:"):
		groupName := strings.TrimPrefix(ambiguity, "insufficient_toppings:")
		groupName = strings.TrimPrefix(groupName, "missing_required_modifier:")
		options, menuName, selectedMods, minSel, _ := findModifierGroupDetails(groupName, draft, categories)
		plan.TargetMenuName = menuName
		plan.Options = options

		isToppingGroup := strings.Contains(strings.ToLower(groupName), "toping") || strings.Contains(strings.ToLower(groupName), "topping")

		if len(selectedMods) > 0 && minSel > len(selectedMods) {
			needed := minSel - len(selectedMods)
			selectedStr := strings.Join(selectedMods, ", ")
			var remainingOpts []string
			for _, o := range options {
				alreadySelected := false
				for _, s := range selectedMods {
					if strings.EqualFold(o, s) {
						alreadySelected = true
						break
					}
				}
				if !alreadySelected {
					remainingOpts = append(remainingOpts, o)
				}
			}
			optionsStr := strings.Join(remainingOpts, ", ")
			plan.QuestionText = fmt.Sprintf("Untuk %s, kakak baru memilih %d topping (%s). Mau tambah %d topping lagi apa kak? Pilihan: %s 😊", menuName, len(selectedMods), selectedStr, needed, optionsStr)
		} else if isToppingGroup && minSel > 1 {
			optionsStr := strings.Join(options, " / ")
			plan.QuestionText = fmt.Sprintf("Untuk %s, mau pilih %d varian %s apa kak? (%s) 😊", menuName, minSel, groupName, optionsStr)
		} else if len(options) > 0 {
			optionsStr := strings.Join(options, " / ")
			if menuName != "" {
				plan.QuestionText = fmt.Sprintf("Untuk %s, mau pilih varian %s apa kak? (%s)", menuName, groupName, optionsStr)
			} else {
				plan.QuestionText = fmt.Sprintf("Mau pilih varian %s apa kak? (%s)", groupName, optionsStr)
			}
		} else {
			if menuName != "" {
				plan.QuestionText = fmt.Sprintf("Untuk %s, mau pilih varian %s apa kak?", menuName, groupName)
			} else {
				plan.QuestionText = fmt.Sprintf("Mau pilih varian %s apa kak?", groupName)
			}
		}

	case strings.HasPrefix(ambiguity, "invalid_quantity:"):
		menuName := strings.TrimPrefix(ambiguity, "invalid_quantity:")
		plan.TargetMenuName = menuName
		plan.QuestionText = fmt.Sprintf("Mau pesan %s berapa porsi kak?", menuName)

	case strings.HasPrefix(ambiguity, "unrecognized_modifier:"):
		modName := strings.TrimPrefix(ambiguity, "unrecognized_modifier:")
		plan.QuestionText = fmt.Sprintf("Untuk pilihan %s, saat ini tidak tersedia di menu kami. Apakah mau tetap pesan tanpa %s kak?", modName, modName)

	case strings.HasPrefix(ambiguity, "modifier_limit_exceeded:") || strings.HasPrefix(ambiguity, "excess_toppings:"):
		groupName := strings.TrimPrefix(ambiguity, "modifier_limit_exceeded:")
		groupName = strings.TrimPrefix(groupName, "excess_toppings:")
		options, menuName, selectedMods, _, maxSel := findModifierGroupDetails(groupName, draft, categories)
		plan.TargetMenuName = menuName
		plan.Options = options
		selectedStr := strings.Join(selectedMods, ", ")

		if maxSel == 1 && len(selectedMods) > 1 {
			plan.QuestionText = fmt.Sprintf("Untuk %s, kakak menyebutkan %d pilihan topping (%s). Mau pilih salah satu topping, atau mau diubah ke menu Terang Bulan 2 Toping kak?", menuName, len(selectedMods), selectedStr)
		} else if maxSel > 0 && len(selectedMods) > maxSel {
			plan.QuestionText = fmt.Sprintf("Untuk %s, kakak menyebutkan %d pilihan topping (%s). Mau pilih %d topping yang mana kak?", menuName, len(selectedMods), selectedStr, maxSel)
		} else {
			plan.QuestionText = fmt.Sprintf("Untuk varian %s melebihi batas pilihan maksimal. Bisa tolong kurangi pilihannya kak?", groupName)
		}

	case ambiguity == "missing_fulfillment_type":
		plan.Options = []string{"Takeaway / Pickup", "Dine In"}
		plan.QuestionText = "Pesanannya mau diambil sendiri (Takeaway/Pickup) atau makan di tempat (Dine In) kak?"

	case ambiguity == "missing_payment_method":
		plan.Options = []string{"Tunai / Cash", "QRIS"}
		plan.QuestionText = "Untuk pembayarannya mau pakai Tunai (Cash) di kasir atau QRIS kak?"

	case ambiguity == "empty_order_items" || ambiguity == "empty_draft" || ambiguity == "no_valid_items_resolved":
		plan.QuestionText = "Halo kak! Selamat datang di Martabak & Terang Bulan Jenggirat. Saya Asisten Jenggirat AI, ada yang bisa kami bantu? Silakan sebutkan pesanan atau hal yang ingin ditanyakan ya kak 😊"

	case strings.HasPrefix(ambiguity, "low_item_confidence") || strings.HasPrefix(ambiguity, "confidence_below_threshold") || ambiguity == "low_overall_confidence" || ambiguity == "uncertainty_detected":
		if draft != nil && len(draft.Items) > 0 {
			plan.QuestionText = fmt.Sprintf("Mohon maaf kak, kami ingin memastikan: apakah pesanan kakak adalah %d porsi %s? 😊", draft.Items[0].Quantity, draft.Items[0].Name)
		} else {
			plan.QuestionText = "Halo kak, boleh tolong sebutkan kembali nama menu dan jumlah porsi yang ingin dipesan agar tidak salah paham kak?"
		}

	default: // low confidence, uncertainty, or empty
		if draft != nil && len(draft.Items) > 0 {
			plan.QuestionText = fmt.Sprintf("Mohon maaf kak, kami ingin memastikan: apakah pesanan kakak adalah %d porsi %s? 😊", draft.Items[0].Quantity, draft.Items[0].Name)
		} else {
			plan.QuestionText = "Halo kak, boleh tolong sebutkan kembali nama menu dan jumlah porsi yang ingin dipesan agar tidak salah paham kak?"
		}
	}

	return plan
}

func findModifierGroupDetails(groupName string, draft *DraftCandidate, categories []catalog.Category) ([]string, string, []string, int, int) {
	if idx := strings.Index(groupName, ":"); idx != -1 {
		groupName = groupName[:idx]
	}
	groupNameLower := strings.ToLower(strings.TrimSpace(groupName))

	var matchedMenuName string
	var options []string
	var selectedMods []string
	var minSel int = 1
	var maxSel int = 1

	if draft != nil {
		for _, it := range draft.Items {
			for _, cat := range categories {
				for _, m := range cat.Menus {
					if m.ID == it.MenuID || strings.EqualFold(m.Name, it.Name) {
						for _, g := range m.Groups {
							if strings.EqualFold(g.Name, groupName) || strings.EqualFold(g.Code, groupName) || strings.Contains(strings.ToLower(g.Name), groupNameLower) {
								matchedMenuName = it.Name
								minSel, maxSel = expectedToppingCount(it.Name, &g)
								for _, opt := range g.Options {
									if opt.Available {
										options = append(options, opt.Name)
									}
								}
								for _, sm := range it.SelectedModifiers {
									if sm.GroupID == g.ID || strings.EqualFold(sm.GroupName, g.Name) {
										selectedMods = append(selectedMods, sm.OptionName)
									}
								}
								if len(options) > 0 {
									return options, matchedMenuName, selectedMods, minSel, maxSel
								}
							}
						}
					}
				}
			}
		}
	}

	// Fallback: search anywhere in catalog
	for _, cat := range categories {
		for _, m := range cat.Menus {
			for _, g := range m.Groups {
				if strings.EqualFold(g.Name, groupName) || strings.EqualFold(g.Code, groupName) || strings.Contains(strings.ToLower(g.Name), groupNameLower) {
					minSel, maxSel = expectedToppingCount(m.Name, &g)
					for _, opt := range g.Options {
						if opt.Available {
							options = append(options, opt.Name)
						}
					}
					return options, m.Name, selectedMods, minSel, maxSel
				}
			}
		}
	}

	return options, matchedMenuName, selectedMods, minSel, maxSel
}

func findModifierGroupOptions(groupName string, draft *DraftCandidate, categories []catalog.Category) ([]string, string) {
	opts, menuName, _, _, _ := findModifierGroupDetails(groupName, draft, categories)
	return opts, menuName
}
