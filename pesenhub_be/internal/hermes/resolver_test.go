package hermes

import (
	"context"
	"testing"

	"pesenhub/backend/internal/catalog"
)

type mockCatalogProvider struct {
	categories []catalog.Category
	err        error
}

func (m *mockCatalogProvider) ListPublic(ctx context.Context, categoryID string, branchID ...string) ([]catalog.Category, error) {
	if m.err != nil {
		return nil, m.err
	}
	return m.categories, nil
}

func sampleCatalog() []catalog.Category {
	return []catalog.Category{
		{
			ID:     "cat-1",
			Name:   "Makanan",
			Active: true,
			Menus: []catalog.Menu{
				{
					ID:          "menu-nasgor",
					CategoryID:  "cat-1",
					SKU:         "NASGOR",
					Name:        "Nasi Goreng Spesial",
					PriceAmount: 20000,
					Available:   true,
					Groups: []catalog.Group{
						{
							ID:        "grp-pedas",
							Code:      "spice",
							Name:      "Level Pedas",
							MinSelect: 1,
							MaxSelect: 1,
							Active:    true,
							Options: []catalog.Option{
								{ID: "opt-tidak-pedas", Code: "mild", Name: "Tidak Pedas", PriceDeltaAmount: 0, Available: true},
								{ID: "opt-sedang", Code: "med", Name: "Sedang", PriceDeltaAmount: 0, Available: true},
								{ID: "opt-pedas", Code: "hot", Name: "Pedas", PriceDeltaAmount: 0, Available: true},
							},
						},
						{
							ID:        "grp-topping",
							Code:      "topping",
							Name:      "Topping Tambahan",
							MinSelect: 0,
							MaxSelect: 3,
							Active:    true,
							Options: []catalog.Option{
								{ID: "opt-telur", Code: "egg", Name: "Telur Dadar", PriceDeltaAmount: 4000, Available: true},
								{ID: "opt-kerupuk", Code: "cracker", Name: "Kerupuk", PriceDeltaAmount: 2000, Available: true},
							},
						},
					},
				},
				{
					ID:          "menu-miegor",
					CategoryID:  "cat-1",
					SKU:         "MIEGOR",
					Name:        "Mie Goreng Jawa",
					PriceAmount: 18000,
					Available:   false, // Out of stock
					Groups:      []catalog.Group{},
				},
			},
		},
		{
			ID:     "cat-2",
			Name:   "Minuman",
			Active: true,
			Menus: []catalog.Menu{
				{
					ID:          "menu-esteh",
					CategoryID:  "cat-2",
					SKU:         "ESTEH",
					Name:        "Es Teh Manis",
					PriceAmount: 5000,
					Available:   true,
					Groups:      []catalog.Group{},
				},
			},
		},
	}
}

func TestCatalogResolver_Success(t *testing.T) {
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	resolver := NewCatalogResolver(provider)

	raw := &RawExtractedOrder{
		Items: []RawExtractedItem{
			{
				MenuName:   "Nasi Goreng Spesial",
				Quantity:   2,
				Modifiers:  []string{"Pedas", "Telur Dadar"},
				Confidence: 0.95,
			},
			{
				MenuName:   "esteh",
				Quantity:   2,
				Confidence: 0.90,
			},
		},
	}

	result, err := resolver.ResolveOrder(context.Background(), raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.IsAmbiguous {
		t.Fatalf("expected not ambiguous, got reasons: %v", result.AmbiguityReasons)
	}

	if len(result.Items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(result.Items))
	}

	// First item check: Nasi Goreng Spesial (20000 + 4000) * 2 = 48000
	nasgor := result.Items[0]
	if nasgor.MenuID != "menu-nasgor" || nasgor.SKU != "NASGOR" {
		t.Errorf("expected menu-nasgor, got ID=%s SKU=%s", nasgor.MenuID, nasgor.SKU)
	}
	if nasgor.UnitPriceAmount != 20000 {
		t.Errorf("expected unit price 20000, got %d", nasgor.UnitPriceAmount)
	}
	if nasgor.ModifiersTotalAmount != 4000 {
		t.Errorf("expected modifier total 4000, got %d", nasgor.ModifiersTotalAmount)
	}
	if nasgor.LineTotalAmount != 48000 {
		t.Errorf("expected line total 48000, got %d", nasgor.LineTotalAmount)
	}

	// Second item check: Es Teh Manis 5000 * 2 = 10000
	esteh := result.Items[1]
	if esteh.MenuID != "menu-esteh" {
		t.Errorf("expected menu-esteh, got %s", esteh.MenuID)
	}
	if esteh.LineTotalAmount != 10000 {
		t.Errorf("expected line total 10000, got %d", esteh.LineTotalAmount)
	}
}

func TestCatalogResolver_MissingRequiredModifier(t *testing.T) {
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	resolver := NewCatalogResolver(provider)

	// User ordered Nasi Goreng but forgot level pedas (required min_select=1)
	raw := &RawExtractedOrder{
		Items: []RawExtractedItem{
			{
				MenuName:   "Nasi Goreng",
				Quantity:   1,
				Modifiers:  []string{},
				Confidence: 0.90,
			},
		},
	}

	result, err := resolver.ResolveOrder(context.Background(), raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !result.IsAmbiguous {
		t.Fatalf("expected ambiguous due to missing required modifier, got none")
	}

	foundReason := false
	for _, reason := range result.AmbiguityReasons {
		if reason == "missing_required_modifier:Level Pedas" {
			foundReason = true
			break
		}
	}
	if !foundReason {
		t.Errorf("expected 'missing_required_modifier:Level Pedas', got %v", result.AmbiguityReasons)
	}
}

func TestCatalogResolver_UnavailableMenu(t *testing.T) {
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	resolver := NewCatalogResolver(provider)

	// User ordered Mie Goreng Jawa which has Available = false
	raw := &RawExtractedOrder{
		Items: []RawExtractedItem{
			{
				MenuName:   "Mie Goreng Jawa",
				Quantity:   1,
				Confidence: 0.95,
			},
		},
	}

	result, err := resolver.ResolveOrder(context.Background(), raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !result.IsAmbiguous {
		t.Fatalf("expected ambiguous due to unavailable menu")
	}

	foundReason := false
	for _, reason := range result.AmbiguityReasons {
		if reason == "menu_unavailable:Mie Goreng Jawa" {
			foundReason = true
			break
		}
	}
	if !foundReason {
		t.Errorf("expected 'menu_unavailable:Mie Goreng Jawa', got %v", result.AmbiguityReasons)
	}
}

func TestCatalogResolver_MenuNotFound(t *testing.T) {
	provider := &mockCatalogProvider{categories: sampleCatalog()}
	resolver := NewCatalogResolver(provider)

	raw := &RawExtractedOrder{
		Items: []RawExtractedItem{
			{
				MenuName:   "Pizza Super Supreme",
				Quantity:   1,
				Confidence: 0.85,
			},
		},
	}

	result, err := resolver.ResolveOrder(context.Background(), raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !result.IsAmbiguous {
		t.Fatalf("expected ambiguous due to menu not found")
	}

	foundReason := false
	for _, reason := range result.AmbiguityReasons {
		if reason == "menu_not_found:Pizza Super Supreme" {
			foundReason = true
			break
		}
	}
	if !foundReason {
		t.Errorf("expected 'menu_not_found:Pizza Super Supreme', got %v", result.AmbiguityReasons)
	}
}

func TestCatalogResolver_JenggiratMenus(t *testing.T) {
	jenggiratCatalog := []catalog.Category{
		{
			ID:     "cat-sj",
			Name:   "Sosis / Jamur",
			Active: true,
			Menus: []catalog.Menu{
				{ID: "m-sj-biasa", SKU: "MT-SJ-BIASA", Name: "Biasa", PriceAmount: 20000, Available: true},
				{ID: "m-sj-spesial", SKU: "MT-SJ-SPESIAL", Name: "Spesial", PriceAmount: 30000, Available: true},
			},
		},
		{
			ID:     "cat-sapi",
			Name:   "Daging Sapi",
			Active: true,
			Menus: []catalog.Menu{
				{ID: "m-sapi-biasa", SKU: "MT-SAPI-BIASA", Name: "Biasa", PriceAmount: 30000, Available: true},
				{ID: "m-sapi-spesial", SKU: "MT-SAPI-SPESIAL", Name: "Spesial", PriceAmount: 40000, Available: true},
			},
		},
		{
			ID:     "cat-tb",
			Name:   "Terang Bulan Manis",
			Active: true,
			Menus: []catalog.Menu{
				{
					ID:          "m-tb-1-biasa",
					SKU:         "TB-1TOPING-BIASA",
					Name:        "1 Toping - Biasa",
					PriceAmount: 18000,
					Available:   true,
					Groups: []catalog.Group{
						{
							ID:        "grp-base",
							Name:      "Pilihan Base Cake",
							MinSelect: 1,
							MaxSelect: 1,
							Active:    true,
							Options: []catalog.Option{
								{ID: "opt-orig", Code: "original", Name: "Original", PriceDeltaAmount: 0, Available: true},
								{ID: "opt-pandan", Code: "pandan", Name: "Pandan", PriceDeltaAmount: 0, Available: true},
							},
						},
						{
							ID:        "grp-top",
							Name:      "Pilihan Toping",
							MinSelect: 1,
							MaxSelect: 8,
							Active:    true,
							Options: []catalog.Option{
								{ID: "opt-coklat", Code: "coklat", Name: "Coklat", PriceDeltaAmount: 0, Available: true},
								{ID: "opt-keju", Code: "keju", Name: "Keju", PriceDeltaAmount: 0, Available: true},
							},
						},
					},
				},
			},
		},
	}

	resolver := NewCatalogResolver(&mockCatalogProvider{categories: jenggiratCatalog})

	// 1. Test "martabak sosis biasa 1"
	raw1 := &RawExtractedOrder{
		Items: []RawExtractedItem{
			{MenuName: "martabak sosis biasa", Quantity: 1, Confidence: 0.95},
		},
	}
	res1, err := resolver.ResolveOrder(context.Background(), raw1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res1.IsAmbiguous {
		t.Fatalf("expected unambiguous for martabak sosis biasa, got: %v", res1.AmbiguityReasons)
	}
	if len(res1.Items) != 1 || res1.Items[0].SKU != "MT-SJ-BIASA" {
		t.Errorf("expected SKU MT-SJ-BIASA, got %+v", res1.Items)
	}

	// 2. Test "terang bulan 1 topping coklat" -> should auto-default Base Cake to Original!
	raw2 := &RawExtractedOrder{
		Items: []RawExtractedItem{
			{MenuName: "terang bulan 1 topping", Modifiers: []string{"coklat"}, Quantity: 1, Confidence: 0.95},
		},
	}
	res2, err := resolver.ResolveOrder(context.Background(), raw2)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res2.IsAmbiguous {
		t.Fatalf("expected unambiguous with auto-defaulted Original base cake, got: %v", res2.AmbiguityReasons)
	}
	if len(res2.Items) != 1 || res2.Items[0].SKU != "TB-1TOPING-BIASA" {
		t.Errorf("expected SKU TB-1TOPING-BIASA, got %+v", res2.Items)
	}
	hasOriginal := false
	hasCoklat := false
	for _, mod := range res2.Items[0].SelectedModifiers {
		if mod.OptionName == "Original" {
			hasOriginal = true
		}
		if mod.OptionName == "Coklat" {
			hasCoklat = true
		}
	}
	if !hasOriginal || !hasCoklat {
		t.Errorf("expected both Original and Coklat selected, got: %+v", res2.Items[0].SelectedModifiers)
	}

	// 3. Test "martabak telur daging sapi biasa 1" with Modifiers: ["Biasa"] (redundant modifier)
	raw3 := &RawExtractedOrder{
		Items: []RawExtractedItem{
			{MenuName: "martabak telur daging sapi", Modifiers: []string{"Biasa"}, Quantity: 1, Confidence: 0.95},
		},
	}
	res3, err := resolver.ResolveOrder(context.Background(), raw3)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res3.IsAmbiguous {
		t.Fatalf("expected unambiguous for martabak telur daging sapi with redundant modifier 'Biasa', got: %v", res3.AmbiguityReasons)
	}
	if len(res3.Items) != 1 || res3.Items[0].SKU != "MT-SAPI-BIASA" {
		t.Errorf("expected SKU MT-SAPI-BIASA, got %+v", res3.Items)
	}

	// 4. Test "terangbulan 2 topping biasa rasa coklat dan keju" with Modifiers: ["2 Toping - Biasa", "coklat", "keju"]
	jenggiratCatalogWith2Toping := append(jenggiratCatalog, catalog.Category{
		ID:     "cat-tb2",
		Name:   "Terang Bulan Manis",
		Active: true,
		Menus: []catalog.Menu{
			{
				ID:          "m-tb-2-biasa",
				SKU:         "TB-2TOPING-BIASA",
				Name:        "2 Toping - Biasa",
				PriceAmount: 23000,
				Available:   true,
				Groups: []catalog.Group{
					{
						ID:        "grp-base",
						Name:      "Pilihan Base Cake",
						MinSelect: 1,
						MaxSelect: 1,
						Active:    true,
						Options: []catalog.Option{
							{ID: "opt-orig", Code: "original", Name: "Original", PriceDeltaAmount: 0, Available: true},
						},
					},
					{
						ID:        "grp-top",
						Name:      "Pilihan Toping",
						MinSelect: 1,
						MaxSelect: 8,
						Active:    true,
						Options: []catalog.Option{
							{ID: "opt-coklat", Code: "coklat", Name: "Coklat", PriceDeltaAmount: 0, Available: true},
							{ID: "opt-keju", Code: "keju", Name: "Keju", PriceDeltaAmount: 0, Available: true},
						},
					},
				},
			},
		},
	})
	resolver2 := NewCatalogResolver(&mockCatalogProvider{categories: jenggiratCatalogWith2Toping})
	raw4 := &RawExtractedOrder{
		Items: []RawExtractedItem{
			{MenuName: "terangbulan 2 topping biasa", Modifiers: []string{"2 Toping - Biasa", "coklat", "keju"}, Quantity: 1, Confidence: 0.95},
		},
	}
	res4, err := resolver2.ResolveOrder(context.Background(), raw4)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res4.IsAmbiguous {
		t.Fatalf("expected unambiguous for 2 toping terangbulan, got: %v", res4.AmbiguityReasons)
	}
	if len(res4.Items) != 1 || res4.Items[0].SKU != "TB-2TOPING-BIASA" {
		t.Errorf("expected SKU TB-2TOPING-BIASA, got %+v", res4.Items)
	}
}
