package hermes

import (
	"context"
	"fmt"
	"regexp"
	"strings"

	"pesenhub/backend/internal/catalog"
)

// ConfirmationIntent represents the classified intent of a customer response during confirmation.
type ConfirmationIntent string

const (
	IntentConfirm ConfirmationIntent = "CONFIRM"
	IntentCancel  ConfirmationIntent = "CANCEL"
	IntentModify  ConfirmationIntent = "MODIFY"
	IntentUnknown ConfirmationIntent = "UNKNOWN"
)

var cleanPunctuationRegex = regexp.MustCompile(`[^a-z0-9\s]`)

// DetectConfirmationIntent classifies the customer's text when in READY_FOR_CONFIRMATION state.
func DetectConfirmationIntent(text string) ConfirmationIntent {
	lower := strings.ToLower(strings.TrimSpace(text))
	cleaned := cleanPunctuationRegex.ReplaceAllString(lower, " ")
	fields := strings.Fields(cleaned)
	if len(fields) == 0 {
		return IntentUnknown
	}
	normalized := strings.Join(fields, " ")

	// 1. Explicit cancellation takes priority
	cancelPhrases := []string{
		"batal", "batalkan", "batalin", "gak jadi", "ga jadi", "enggak jadi",
		"cancel", "tidak jadi", "ndak jadi", "salah", "jangan",
	}
	for _, p := range cancelPhrases {
		if normalized == p || strings.HasPrefix(normalized, p+" ") || strings.HasSuffix(normalized, " "+p) {
			return IntentCancel
		}
	}

	// 2. Explicit modification request
	modifyPhrases := []string{
		"ganti", "ubah", "tambah", "kurang", "tukar", "revisi", "edit",
	}
	for _, p := range modifyPhrases {
		if strings.HasPrefix(normalized, p+" ") || strings.Contains(normalized, " "+p+" ") || normalized == p {
			return IntentModify
		}
	}

	// 3. Explicit confirmation
	exactConfirms := map[string]struct{}{
		"ya":             {},
		"iya":            {},
		"oke":            {},
		"ok":             {},
		"setuju":         {},
		"benar":          {},
		"betul":          {},
		"siap":           {},
		"lanjut":         {},
		"deal":           {},
		"confirm":        {},
		"yes":            {},
		"y":              {},
		"sudah benar":    {},
		"sudah sesuai":   {},
		"pas":            {},
		"fix":            {},
		"pesan sekarang": {},
		"gas":            {},
		"bungkus":        {},
		"ok kak":         {},
		"ya kak":         {},
		"iya kak":        {},
		"oke kak":        {},
		"baik kak":       {},
		"baik":           {},
		"sudah":          {},
		"acc":            {},
		"sip":            {},
		"yoi":            {},
		"yep":            {},
		"yap":            {},
		"ok min":         {},
		"ya min":         {},
		"iya min":        {},
		"oke min":        {},
		"siap kak":       {},
		"siap min":       {},
		"lanjut kak":     {},
		"lanjutkan":      {},
		"proses":         {},
		"proses kak":     {},
	}

	if _, ok := exactConfirms[normalized]; ok {
		return IntentConfirm
	}

	// Check if first word is a clear affirmative (e.g. "ya proses", "oke tolong dibuatkan")
	if len(fields) > 1 {
		first := fields[0]
		if first == "ya" || first == "iya" || first == "oke" || first == "ok" || first == "siap" || first == "setuju" {
			return IntentConfirm
		}
	}

	return IntentUnknown
}

// ValidateDraftFreshness checks if items and modifiers in the draft still match current catalog availability and prices.
// If prices changed or an item is unavailable, isFresh is false, and reason describes the change.
func ValidateDraftFreshness(ctx context.Context, draft *DraftCandidate, categories []catalog.Category) (bool, *DraftCandidate, string) {
	if draft == nil || len(draft.Items) == 0 {
		return false, draft, "Draft pesanan kosong"
	}

	// Map active menus by ID and SKU
	menuMap := make(map[string]catalog.Menu)
	for _, c := range categories {
		for _, m := range c.Menus {
			menuMap[m.ID] = m
			menuMap[m.SKU] = m
		}
	}

	var priceChanged bool
	var changeReason string

	// Clone draft items for updated prices if needed
	updatedItems := make([]ExtractedItem, len(draft.Items))
	copy(updatedItems, draft.Items)

	for i, it := range updatedItems {
		m, exists := menuMap[it.MenuID]
		if !exists {
			m, exists = menuMap[it.SKU]
		}
		if !exists || !m.Available {
			return false, draft, fmt.Sprintf("Menu '%s' saat ini sedang tidak tersedia (habis)", it.Name)
		}

		// Check menu unit price
		if m.PriceAmount != it.UnitPriceAmount {
			priceChanged = true
			changeReason = fmt.Sprintf("Harga menu '%s' telah berubah dari Rp %d menjadi Rp %d", it.Name, it.UnitPriceAmount, m.PriceAmount)
			updatedItems[i].UnitPriceAmount = m.PriceAmount
		}

		// Check modifiers
		optMap := make(map[string]catalog.Option)
		for _, g := range m.Groups {
			for _, o := range g.Options {
				optMap[o.ID] = o
				optMap[o.Code] = o
			}
		}

		var modsTotal int64
		updatedMods := make([]SelectedModifier, len(it.SelectedModifiers))
		copy(updatedMods, it.SelectedModifiers)

		for mi, mod := range updatedMods {
			opt, optExists := optMap[mod.OptionID]
			if !optExists {
				opt, optExists = optMap[mod.OptionCode]
			}
			if !optExists || !opt.Available {
				return false, draft, fmt.Sprintf("Pilihan '%s' untuk menu '%s' saat ini sedang tidak tersedia", mod.OptionName, it.Name)
			}
			if opt.PriceDeltaAmount != mod.PriceDeltaAmount {
				priceChanged = true
				changeReason = fmt.Sprintf("Harga pilihan '%s' untuk menu '%s' telah berubah dari Rp %d menjadi Rp %d", mod.OptionName, it.Name, mod.PriceDeltaAmount, opt.PriceDeltaAmount)
				updatedMods[mi].PriceDeltaAmount = opt.PriceDeltaAmount
			}
			modsTotal += updatedMods[mi].PriceDeltaAmount
		}

		updatedItems[i].SelectedModifiers = updatedMods
		updatedItems[i].ModifiersTotalAmount = modsTotal
		unitWithMods := updatedItems[i].UnitPriceAmount + modsTotal
		updatedItems[i].LineTotalAmount = unitWithMods * int64(it.Quantity)
	}

	if priceChanged {
		var newSubtotal int64
		for _, it := range updatedItems {
			newSubtotal += it.LineTotalAmount
		}
		newDraft := *draft
		newDraft.Items = updatedItems
		newDraft.SubtotalAmount = newSubtotal
		newDraft.TotalAmount = newSubtotal
		return false, &newDraft, changeReason
	}

	return true, draft, ""
}

// FormatOrderSuccessMessage builds the final customer WhatsApp message after order is created.
func FormatOrderSuccessMessage(orderNumber, trackingToken string, totalAmount int64) string {
	trackingURL := "https://pesenhub.id/orders/track/" + trackingToken
	var sb strings.Builder
	sb.WriteString("Terima kasih kak! Pesanan kakak berhasil dibuat dengan nomor pesanan:\n")
	sb.WriteString(fmt.Sprintf("*%s*\n\n", orderNumber))
	sb.WriteString(fmt.Sprintf("Total: Rp %d\n", totalAmount))
	sb.WriteString("Pengambilan: PICKUP\n")
	sb.WriteString("Status: Menunggu konfirmasi outlet (PENDING)\n\n")
	sb.WriteString("Pantau status pesanan kakak secara berkala di tautan berikut:\n")
	sb.WriteString(fmt.Sprintf("%s\n\n", trackingURL))
	sb.WriteString("Pembayaran dapat dilakukan secara Tunai atau QRIS saat pengambilan pesanan di outlet kasir.")
	return sb.String()
}
