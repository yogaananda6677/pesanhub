package hermes

import (
	"context"
	"strings"
	"testing"

	"pesenhub/backend/internal/catalog"
)

func TestDetectConfirmationIntent(t *testing.T) {
	tests := []struct {
		input string
		want  ConfirmationIntent
	}{
		// Confirms
		{"Ya", IntentConfirm},
		{"ya", IntentConfirm},
		{"iya", IntentConfirm},
		{"Iya", IntentConfirm},
		{"oke", IntentConfirm},
		{"Oke", IntentConfirm},
		{"ok", IntentConfirm},
		{"OK", IntentConfirm},
		{"setuju", IntentConfirm},
		{"benar", IntentConfirm},
		{"betul", IntentConfirm},
		{"siap", IntentConfirm},
		{"lanjut", IntentConfirm},
		{"deal", IntentConfirm},
		{"confirm", IntentConfirm},
		{"yes", IntentConfirm},
		{"y", IntentConfirm},
		{"sudah benar", IntentConfirm},
		{"sudah sesuai", IntentConfirm},
		{"pas", IntentConfirm},
		{"fix", IntentConfirm},
		{"gas", IntentConfirm},
		{"bungkus", IntentConfirm},
		{"ok kak", IntentConfirm},
		{"ya kak", IntentConfirm},
		{"iya min", IntentConfirm},
		{"oke tolong segera diproses ya", IntentConfirm},
		{"ya proses sekarang", IntentConfirm},

		// Cancels
		{"batal", IntentCancel},
		{"Batal", IntentCancel},
		{"batalkan", IntentCancel},
		{"batalin", IntentCancel},
		{"gak jadi", IntentCancel},
		{"ga jadi", IntentCancel},
		{"enggak jadi", IntentCancel},
		{"cancel", IntentCancel},
		{"tidak jadi", IntentCancel},
		{"salah", IntentCancel},

		// Modifies
		{"ganti jadi 3 porsi", IntentModify},
		{"ubah level pedas", IntentModify},
		{"tambah 1 es teh manis", IntentModify},
		{"kurang satu", IntentModify},
		{"revisi pesanan", IntentModify},

		// Unknown / Ambiguous
		{"halo", IntentUnknown},
		{"berapa lama ya mas?", IntentUnknown},
		{"ada promo?", IntentUnknown},
		{"lokasinya di mana?", IntentUnknown},
		{"", IntentUnknown},
		{"   ", IntentUnknown},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got := DetectConfirmationIntent(tt.input)
			if got != tt.want {
				t.Errorf("DetectConfirmationIntent(%q) = %v, want %v", tt.input, got, tt.want)
			}
		})
	}
}

func TestValidateDraftFreshness(t *testing.T) {
	ctx := context.Background()

	cat := []catalog.Category{
		{
			ID:     "cat-1",
			Name:   "Makanan",
			Active: true,
			Menus: []catalog.Menu{
				{
					ID:          "menu-1",
					SKU:         "NASGOR-SPESIAL",
					Name:        "Nasi Goreng Spesial",
					PriceAmount: 25000,
					Available:   true,
					Groups: []catalog.Group{
						{
							ID:   "grp-1",
							Code: "pedas",
							Name: "Level Pedas",
							Options: []catalog.Option{
								{
									ID:               "opt-1",
									Code:             "pedas-sedang",
									Name:             "Sedang",
									PriceDeltaAmount: 0,
									Available:        true,
								},
								{
									ID:               "opt-2",
									Code:             "pedas-ekstra",
									Name:             "Ekstra Pedas",
									PriceDeltaAmount: 3000,
									Available:        true,
								},
							},
						},
					},
				},
			},
		},
	}

	baseDraft := &DraftCandidate{
		CustomerPhone: "+628123456789",
		Items: []ExtractedItem{
			{
				MenuID:               "menu-1",
				SKU:                  "NASGOR-SPESIAL",
				Name:                 "Nasi Goreng Spesial",
				Quantity:             2,
				UnitPriceAmount:      25000,
				ModifiersTotalAmount: 0,
				LineTotalAmount:      50000,
				SelectedModifiers: []SelectedModifier{
					{
						GroupID:          "grp-1",
						GroupName:        "Level Pedas",
						OptionID:         "opt-1",
						OptionCode:       "pedas-sedang",
						OptionName:       "Sedang",
						PriceDeltaAmount: 0,
					},
				},
			},
		},
		SubtotalAmount: 50000,
		TotalAmount:    50000,
	}

	// 1. Fresh draft matches perfectly
	isFresh, _, reason := ValidateDraftFreshness(ctx, baseDraft, cat)
	if !isFresh {
		t.Fatalf("expected fresh draft, got reason: %s", reason)
	}

	// 2. Menu became unavailable
	unavailCat := []catalog.Category{
		{
			ID:     "cat-1",
			Name:   "Makanan",
			Active: true,
			Menus: []catalog.Menu{
				{
					ID:          "menu-1",
					SKU:         "NASGOR-SPESIAL",
					Name:        "Nasi Goreng Spesial",
					PriceAmount: 25000,
					Available:   false, // Out of stock!
				},
			},
		},
	}
	isFresh, _, reason = ValidateDraftFreshness(ctx, baseDraft, unavailCat)
	if isFresh {
		t.Fatal("expected stale draft when menu is unavailable")
	}
	if !strings.Contains(reason, "tidak tersedia") {
		t.Fatalf("expected unavailable reason, got: %s", reason)
	}

	// 3. Menu price changed (e.g. price increased to 28000)
	priceChangedCat := []catalog.Category{
		{
			ID:     "cat-1",
			Name:   "Makanan",
			Active: true,
			Menus: []catalog.Menu{
				{
					ID:          "menu-1",
					SKU:         "NASGOR-SPESIAL",
					Name:        "Nasi Goreng Spesial",
					PriceAmount: 28000, // Price increased!
					Available:   true,
					Groups:      cat[0].Menus[0].Groups,
				},
			},
		},
	}
	isFresh, updatedDraft, reason := ValidateDraftFreshness(ctx, baseDraft, priceChangedCat)
	if isFresh {
		t.Fatal("expected stale draft when menu price changed")
	}
	if !strings.Contains(reason, "telah berubah") {
		t.Fatalf("expected price changed reason, got: %s", reason)
	}
	expectedNewTotal := int64(28000 * 2) // 56000
	if updatedDraft.TotalAmount != expectedNewTotal {
		t.Fatalf("expected updated draft total %d, got %d", expectedNewTotal, updatedDraft.TotalAmount)
	}
	if updatedDraft.Items[0].UnitPriceAmount != 28000 {
		t.Fatalf("expected updated item unit price 28000, got %d", updatedDraft.Items[0].UnitPriceAmount)
	}

	// 4. Modifier price changed
	modPriceChangedCat := []catalog.Category{
		{
			ID:     "cat-1",
			Name:   "Makanan",
			Active: true,
			Menus: []catalog.Menu{
				{
					ID:          "menu-1",
					SKU:         "NASGOR-SPESIAL",
					Name:        "Nasi Goreng Spesial",
					PriceAmount: 25000,
					Available:   true,
					Groups: []catalog.Group{
						{
							ID:   "grp-1",
							Code: "pedas",
							Name: "Level Pedas",
							Options: []catalog.Option{
								{
									ID:               "opt-1",
									Code:             "pedas-sedang",
									Name:             "Sedang",
									PriceDeltaAmount: 2000, // Price delta increased!
									Available:        true,
								},
							},
						},
					},
				},
			},
		},
	}
	isFresh, updatedDraft, reason = ValidateDraftFreshness(ctx, baseDraft, modPriceChangedCat)
	if isFresh {
		t.Fatal("expected stale draft when modifier price delta changed")
	}
	if !strings.Contains(reason, "telah berubah") {
		t.Fatalf("expected modifier price changed reason, got: %s", reason)
	}
	expectedModTotal := int64((25000 + 2000) * 2) // 54000
	if updatedDraft.TotalAmount != expectedModTotal {
		t.Fatalf("expected updated draft total %d, got %d", expectedModTotal, updatedDraft.TotalAmount)
	}
}
