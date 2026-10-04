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

	foodTerms := []string{
		"martabak", "terang bulan", "terbul", "sosis", "jamur", "ayam", "sapi",
		"moza", "mozarella", "keju", "coklat", "kacang", "pizza", "topping", "toping",
		"biasa", "spesial", "istimewa",
	}
	hasFoodTerm := false
	for _, f := range foodTerms {
		if strings.Contains(normalized, f) {
			hasFoodTerm = true
			break
		}
	}

	// 1. Explicit cancellation takes priority (unless combined with ordering a replacement item)
	cancelPhrases := []string{
		"batal", "batalkan", "batalin", "gak jadi", "ga jadi", "enggak jadi", "gajadi",
		"cancel", "tidak jadi", "ndak jadi", "salah", "jangan", "tunda", "nanti aja", "jangan dulu",
	}
	for _, p := range cancelPhrases {
		if normalized == p || strings.HasPrefix(normalized, p+" ") || strings.HasSuffix(normalized, " "+p) || strings.Contains(normalized, p) {
			if hasFoodTerm {
				return IntentModify
			}
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
		"ya":               {},
		"iya":              {},
		"oke":              {},
		"ok":               {},
		"setuju":           {},
		"benar":            {},
		"betul":            {},
		"bener":            {},
		"siap":             {},
		"lanjut":           {},
		"deal":             {},
		"confirm":          {},
		"yes":              {},
		"y":                {},
		"sudah benar":      {},
		"sudah sesuai":     {},
		"sudah bener":      {},
		"sudah pas":        {},
		"pas":              {},
		"pas kok":          {},
		"pas kak":          {},
		"fix":              {},
		"pesan sekarang":   {},
		"gas":              {},
		"gas bungkus":      {},
		"bungkus":          {},
		"bungkus ya":       {},
		"ok kak":           {},
		"ya kak":           {},
		"iya kak":          {},
		"oke kak":          {},
		"baik kak":         {},
		"baik":             {},
		"sudah":            {},
		"acc":              {},
		"sip":              {},
		"yoi":              {},
		"yep":              {},
		"yap":              {},
		"ok min":           {},
		"ya min":           {},
		"iya min":          {},
		"oke min":          {},
		"siap kak":         {},
		"siap min":         {},
		"lanjut kak":       {},
		"lanjutkan":        {},
		"proses":           {},
		"proses kak":       {},
		"kuy":              {},
		"mantap":           {},
		"tolong dibuatkan": {},
		"buatkan ya":       {},
		"bikin ya":         {},
		"iya betul":        {},
		"iya benar":        {},
		"iya bener":        {},
	}

	if _, ok := exactConfirms[normalized]; ok {
		return IntentConfirm
	}

	if strings.Contains(normalized, "sudah pas") || strings.Contains(normalized, "pas kok") || strings.Contains(normalized, "sudah benar") || strings.Contains(normalized, "sudah betul") || strings.Contains(normalized, "tolong dibuatkan") || strings.Contains(normalized, "bikin ya") || strings.Contains(normalized, "buatkan ya") || strings.Contains(normalized, "siap bungkus") {
		return IntentConfirm
	}

	// Check if first word is a clear affirmative (e.g. "ya proses", "oke tolong dibuatkan")
	if len(fields) > 1 {
		first := fields[0]
		if first == "ya" || first == "iya" || first == "oke" || first == "ok" || first == "siap" || first == "setuju" || first == "bener" || first == "betul" || first == "pas" || first == "gas" || first == "bungkus" || first == "mantap" {
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
func FormatOrderSuccessMessage(orderNumber, trackingToken string, totalAmount int64, customerName ...string) string {
	trackingURL := "https://pesenhub.id/orders/track/" + trackingToken
	var sb strings.Builder
	nameSuffix := ""
	if len(customerName) > 0 && strings.TrimSpace(customerName[0]) != "" {
		nameSuffix = " kak " + strings.TrimSpace(customerName[0])
	} else {
		nameSuffix = " kak"
	}
	sb.WriteString(fmt.Sprintf("Terima kasih%s! Pesanan berhasil kami buat dengan nomor:\n", nameSuffix))
	sb.WriteString(fmt.Sprintf("*%s*\n\n", orderNumber))
	sb.WriteString(fmt.Sprintf("Total: Rp %d\n", totalAmount))
	sb.WriteString("Pengambilan: PICKUP\n")
	sb.WriteString("Status: Menunggu konfirmasi outlet (PENDING)\n\n")
	sb.WriteString("Pantau status pesanan secara berkala di tautan berikut:\n")
	sb.WriteString(fmt.Sprintf("%s\n\n", trackingURL))
	sb.WriteString(fmt.Sprintf("Pesanan sedang disiapkan. Pembayaran dapat dilakukan secara Tunai atau QRIS saat pengambilan di kasir ya%s. Sampai jumpa! 😊", nameSuffix))
	return sb.String()
}
