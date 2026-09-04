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

func (m *mockCatalogProvider) ListPublic(ctx context.Context, categoryID string) ([]catalog.Category, error) {
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
