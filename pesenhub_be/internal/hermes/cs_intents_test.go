package hermes

import (
	"strings"
	"testing"

	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/order"
)

func TestDetectOrderStatusInquiry(t *testing.T) {
	positives := []string{
		"udah jadi belum?",
		"udah jadi belom",
		"sudah jadi belum kak",
		"pesanan saya sudah siap?",
		"pesanan saya udah siap",
		"pesanan saya sudah jadi",
		"status pesanan saya",
		"status pesanan",
		"cek status pesanan",
		"cek pesanan",
		"cek pesanan saya",
		"gimana pesanan saya kak",
		"pesanan saya sampai mana ya",
		"pesananku sudah sampai mana",
		"masih lama gak ya",
		"udah beres belum kak",
		"bisa diambil belum",
		"posisi pesanan saya gimana",
		"martabak saya sudah di mana",
		"posisi pesanan",
	}

	for _, text := range positives {
		if !DetectOrderStatusInquiry(text) {
			t.Errorf("expected DetectOrderStatusInquiry(%q) = true, got false", text)
		}
		// Ensure that order status inquiry is NEVER classified as store info inquiry
		if ok, infoType := DetectStoreInfoInquiry(text); ok {
			t.Errorf("expected DetectStoreInfoInquiry(%q) = false, got true (type=%s)", text, infoType)
		}
	}

	negatives := []string{
		"halo kak",
		"pesan martabak 1",
		"minta katalognya dong kak",
		"iya pas",
		"batal",
	}

	for _, text := range negatives {
		if DetectOrderStatusInquiry(text) {
			t.Errorf("expected DetectOrderStatusInquiry(%q) = false, got true", text)
		}
	}
}

func TestDetectCatalogInquiry(t *testing.T) {
	positives := []string{
		"halo saya mau order minta katalognya dong kak",
		"minta katalognya dong",
		"minta katalog",
		"katalog dong",
		"katalog",
		"menu apa aja",
		"ada menu apa aja kak?",
		"menunya apa aja",
		"menu nya apa",
		"lihat menu dong",
		"daftar menu",
		"ada makanan apa",
		"pricelist dong",
		"price list",
		"daftar harga",
		"spill menu",
		"pilihan menu",
		"gambarnya ad angga kak?",
		"ada foto menunya?",
		"menu nya",
		"minta gambar menu",
		"ada fotonya kak?",
	}

	for _, text := range positives {
		if !DetectCatalogInquiry(text) {
			t.Errorf("expected DetectCatalogInquiry(%q) = true, got false", text)
		}
	}

	negatives := []string{
		"halo kak",
		"saya mau pesan martabak daging sapi 1",
		"udah jadi belum?",
		"iya bungkus",
	}

	for _, text := range negatives {
		if DetectCatalogInquiry(text) {
			t.Errorf("expected DetectCatalogInquiry(%q) = false, got true", text)
		}
	}
}

func TestDetectRecommendationInquiry(t *testing.T) {
	positives := []string{
		"rekomendasi apa kak?",
		"yang paling enak apa ya?",
		"menu paling laris apa?",
		"menu favorit apa?",
		"best seller nya apa?",
		"sarannya apa?",
	}

	for _, text := range positives {
		if !DetectRecommendationInquiry(text) {
			t.Errorf("expected DetectRecommendationInquiry(%q) = true, got false", text)
		}
	}

	negatives := []string{
		"halo",
		"pesan 1",
		"udah jadi belum",
	}

	for _, text := range negatives {
		if DetectRecommendationInquiry(text) {
			t.Errorf("expected DetectRecommendationInquiry(%q) = false, got true", text)
		}
	}
}

func TestDetectStoreInfoInquiry(t *testing.T) {
	hoursQueries := []string{
		"buka jam berapa kak?",
		"tutup jam berapa?",
		"jam buka outlet kapan?",
		"jam operasional nya?",
	}
	for _, q := range hoursQueries {
		ok, infoType := DetectStoreInfoInquiry(q)
		if !ok || infoType != "hours" {
			t.Errorf("expected hours info for %q, got ok=%v, type=%s", q, ok, infoType)
		}
	}

	locationQueries := []string{
		"lokasi di mana kak?",
		"alamat nya di mana?",
		"posisi di mana",
		"alamat outlet di mana ya",
		"lokasi nya kak mana",
		"lokasi outletnya mana",
		"lokasi outlet",
		"lokasi mana kak",
		"bisa shareloc ngga",
		"shareloc",
		"posisinya dimana ya",
	}
	for _, q := range locationQueries {
		ok, infoType := DetectStoreInfoInquiry(q)
		if !ok || infoType != "location" {
			t.Errorf("expected location info for %q, got ok=%v, type=%s", q, ok, infoType)
		}
	}
}

func TestDetectGreetingInquiry(t *testing.T) {
	positives := []string{
		"halo",
		"halo mas",
		"halo kak",
		"halo min",
		"hai",
		"selamat sore",
		"selamat malam",
		"p",
	}
	for _, text := range positives {
		if !DetectGreetingInquiry(text) {
			t.Errorf("expected DetectGreetingInquiry(%q) = true, got false", text)
		}
	}

	negatives := []string{
		"pesan martabak 1",
		"minta katalog dong",
		"buka jam berapa?",
	}
	for _, text := range negatives {
		if DetectGreetingInquiry(text) {
			t.Errorf("expected DetectGreetingInquiry(%q) = false, got true", text)
		}
	}
}

func TestFormatOrderStatusMessage(t *testing.T) {
	ord := order.OrderDetail{
		OrderNumber:         "BWX-001",
		Status:              "PREPARING",
		PublicTrackingToken: "track-123",
		Items: []order.OrderItemDetail{
			{Name: "Martel Daging Sapi", Quantity: 1},
		},
	}

	msg := formatOrderStatusMessage(ord, "Yoga")
	if !strings.Contains(msg, "kak Yoga") {
		t.Errorf("expected customer name in message: %s", msg)
	}
	if !strings.Contains(msg, "Sedang Dimasak / Disiapkan") {
		t.Errorf("expected status description in message: %s", msg)
	}
	if !strings.Contains(msg, "track-123") {
		t.Errorf("expected tracking link in message: %s", msg)
	}
}

func TestFormatCatalogMenuMessage(t *testing.T) {
	cats := []catalog.Category{
		{
			Name:   "Terang Bulan",
			Active: true,
			Menus: []catalog.Menu{
				{Name: "Terang Bulan Manis", PriceAmount: 18000, Available: true},
			},
		},
	}

	msg := formatCatalogMenuMessage(cats, "Yoga")
	if !strings.Contains(msg, "kak Yoga") {
		t.Errorf("expected customer name in message: %s", msg)
	}
	if !strings.Contains(msg, "Terang Bulan Manis") {
		t.Errorf("expected menu name in message: %s", msg)
	}
	if !strings.Contains(msg, "18000") {
		t.Errorf("expected price in message: %s", msg)
	}
}

func TestDetectCategoryInquiry(t *testing.T) {
	terbulQueries := []string{
		"mau pesen terangbulan",
		"pesen terang bulan",
		"mau beli terangbulan",
		"terangbulan",
		"terang bulan dong",
		"terbul",
	}
	for _, q := range terbulQueries {
		ok, catType := DetectCategoryInquiry(q)
		if !ok || catType != "terang_bulan" {
			t.Errorf("expected terang_bulan inquiry for %q, got ok=%v, type=%s", q, ok, catType)
		}
	}

	martabakQueries := []string{
		"mau pesen martabak",
		"pesan martabak",
		"mau beli martabak telur",
		"martabak telor",
		"martel dong",
	}
	for _, q := range martabakQueries {
		ok, catType := DetectCategoryInquiry(q)
		if !ok || catType != "martabak_telur" {
			t.Errorf("expected martabak_telur inquiry for %q, got ok=%v, type=%s", q, ok, catType)
		}
	}

	negatives := []string{
		"terangbulan 2 topping biasa rasa coklat dan keju",
		"martabak telur daging sapi biasa 1",
		"minta katalog",
	}
	for _, q := range negatives {
		ok, _ := DetectCategoryInquiry(q)
		if ok {
			t.Errorf("expected false for specific order %q, got true", q)
		}
	}
}
