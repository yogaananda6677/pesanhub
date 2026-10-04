package hermes

import (
	"fmt"
	"regexp"
	"strings"

	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/order"
)

var (
	orderStatusPatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)\b(udah|sudah)\s+(jadi|siap|beres|kelar|bisa\s+diambil)(\s+belum|\s+belom|\s+gak|\s+ngga|\?)?`),
		regexp.MustCompile(`(?i)\b(bisa\s+diambil\s+belum|sudah\s+bisa\s+diambil|udah\s+bisa\s+diambil)\b`),
		regexp.MustCompile(`(?i)\b(status\s+pesanan|cek\s+pesanan|cek\s+status|gimana\s+pesanan|pantau\s+pesanan|lacak\s+pesanan|posisi\s+pesanan)\b`),
		regexp.MustCompile(`(?i)\b(pesanan|makanan|martabak|terang\s*bulan)(ku|\s+saya)?\s+(udah|sudah|sampai\s+mana|di\s*mana|dimana|masih\s+lama)\b`),
		regexp.MustCompile(`(?i)\b(sampai\s+mana|masih\s+lama\s+(gak|ngga|ya)|kapan\s+selesai|kapan\s+jadi)\b`),
	}

	catalogPatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)\b(minta\s+katalog|katalognya|katalog\s+dong|katalog\s+menu|lihat\s+katalog|kirim\s+katalog|minta\s+menu|lihat\s+menu|daftar\s+menu|spill\s+menu|pilihan\s+menu)\b`),
		regexp.MustCompile(`(?i)\b(ada\s+menu\s+apa|menu\s+apa\s+aja|menunya\s+apa|menu\s+nya\s+apa|ada\s+makanan\s+apa|makanan\s+apa\s+aja)\b`),
		regexp.MustCompile(`(?i)\b(daftar\s+harga|pricelist|price\s+list)\b`),
		regexp.MustCompile(`(?i)\b(gambar(nya)?|foto(nya)?|brosur)\b`),
		regexp.MustCompile(`(?i)\b(ada\s+(gambar|foto)|minta\s+(gambar|foto)|kirim\s+(gambar|foto)|lihat\s+(gambar|foto)|gambarnya\s+ad(a)?)\b`),
		regexp.MustCompile(`(?i)^\s*(katalog|menu|list\s+menu|daftar\s+menu|gambar|foto|menunya|menu\s+nya)(\s+(dong|kak|min|nya))*\s*[\.!?]*\s*$`),
	}

	recommendationPatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)\b(rekomendasi|rekomendasinya|sarannya|menu\s+andalan|menu\s+favorit|best\s+seller)\b`),
		regexp.MustCompile(`(?i)\b(paling\s+(enak|laris|favorit|populer|bestseller))\b`),
	}

	hoursPatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)\b(buka\s+jam\s+berapa|tutup\s+jam\s+berapa|jam\s+buka|jam\s+tutup|jam\s+operasional|sampai\s+jam\s+berapa)\b`),
		regexp.MustCompile(`(?i)\b(hari\s+ini\s+buka|masih\s+buka|udah\s+buka|sudah\s+buka|buka\s+(gak|ngga|nggak|kah|ta|kan))\b`),
		regexp.MustCompile(`(?i)^\s*(jam\s+buka|jam\s+operasional|buka\s+sampai\s+jam\s+berapa)(\s+(kak|mas|min|nya))*\s*[\.!?]*\s*$`),
	}

	locationPatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)\b(lokasi(nya)?|alamat(nya)?|tempat(nya)?|shareloc|share\s*loc|gmaps|google\s*maps?)\b`),
		regexp.MustCompile(`(?i)\bposisi(nya)?\s*(di\s*mana|dimana)\b`),
		regexp.MustCompile(`(?i)\b(di\s*mana|dimana)\b.*(outlet|toko|kedai|gerai|jenggirat|tempat\s+jualan)\b`),
		regexp.MustCompile(`(?i)\b(outlet|toko|kedai|gerai|jenggirat|tempat\s+jualan)\b.*(di\s*mana|dimana|lokasi|alamat)\b`),
		regexp.MustCompile(`(?i)\bposisi\s*(outlet|toko|kedai|gerai|jenggirat)\b`),
		regexp.MustCompile(`(?i)^\s*(lokasi(nya)?|alamat(nya)?|posisi(nya)?|tempat(nya)?|dimana|di\s+mana)(\s+(outlet|toko|kedai|gerai|jenggirat|kak|mas|min|nya|ya))*\s*[\.!?]*\s*$`),
	}

	greetingPatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)^\s*(halo|hallo|hai|hi|hey|hei|p|ping|assalamualaikum|assalamu'alaikum|kulonuwun|permisi|pagi|siang|sore|malam)(\s+(kak|mas|min|admin|om|gan|bos|bang|mbak|jenggirat))*[\.!?~]*\s*$`),
		regexp.MustCompile(`(?i)^\s*(selamat\s+(pagi|siang|sore|malam))(\s+(kak|mas|min|admin|jenggirat))*[\.!?~]*\s*$`),
	}

	receiptPatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)\b(minta\s+struk|kirim\s+struk|struknya|struk\s+pesanan|struk\s+pembelian|cetak\s+struk)\b`),
		regexp.MustCompile(`(?i)\b(minta\s+nota|kirim\s+nota|notanya|nota\s+pesanan|minta\s+bon|kirim\s+bon)\b`),
		regexp.MustCompile(`(?i)^\s*(struk|nota|bon)(\s+(dong|kak|min|nya))*\s*[\.!?]*\s*$`),
	}

	broadTerangBulanPattern = regexp.MustCompile(`(?i)^\s*(mau|ingin|bisa|tolong)?\s*(pesen|pesan|beli|order)?\s*(terang\s*bulan|terangbulan|terbul)(\s*(dong|kak|min|ya|aja))*\s*[\.!?]*\s*$`)
	broadMartabakPattern    = regexp.MustCompile(`(?i)^\s*(mau|ingin|bisa|tolong)?\s*(pesen|pesan|beli|order)?\s*(martabak(\s+telur|\s+telor)?|martel)(\s*(dong|kak|min|ya|aja))*\s*[\.!?]*\s*$`)
)

// DetectCategoryInquiry detects whether the message is a general category inquiry without variant or toppings.
func DetectCategoryInquiry(text string) (bool, string) {
	trimmed := strings.TrimSpace(text)
	if broadTerangBulanPattern.MatchString(trimmed) {
		return true, "terang_bulan"
	}
	if broadMartabakPattern.MatchString(trimmed) {
		return true, "martabak_telur"
	}
	return false, ""
}

// DetectReceiptInquiry detects whether the customer is asking for the order receipt / struk.
func DetectReceiptInquiry(text string) bool {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return false
	}
	for _, p := range receiptPatterns {
		if p.MatchString(trimmed) {
			return true
		}
	}
	return false
}

// DetectOrderStatusInquiry detects whether the message is inquiring about an order status.
func DetectOrderStatusInquiry(text string) bool {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return false
	}
	for _, p := range orderStatusPatterns {
		if p.MatchString(trimmed) {
			return true
		}
	}
	return false
}

// DetectCatalogInquiry detects whether the customer is asking for the catalog or menu list.
func DetectCatalogInquiry(text string) bool {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return false
	}
	for _, p := range catalogPatterns {
		if p.MatchString(trimmed) {
			return true
		}
	}
	return false
}

// DetectRecommendationInquiry detects whether the customer is asking for menu recommendations.
func DetectRecommendationInquiry(text string) bool {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return false
	}
	for _, p := range recommendationPatterns {
		if p.MatchString(trimmed) {
			return true
		}
	}
	return false
}

// DetectStoreInfoInquiry detects questions about store hours or location.
func DetectStoreInfoInquiry(text string) (bool, string) {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return false, ""
	}
	if DetectOrderStatusInquiry(trimmed) {
		return false, ""
	}
	for _, p := range hoursPatterns {
		if p.MatchString(trimmed) {
			return true, "hours"
		}
	}
	for _, p := range locationPatterns {
		if p.MatchString(trimmed) {
			return true, "location"
		}
	}
	return false, ""
}

// DetectGreetingInquiry detects whether the message is a casual opening greeting.
func DetectGreetingInquiry(text string) bool {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return false
	}
	for _, p := range greetingPatterns {
		if p.MatchString(trimmed) {
			return true
		}
	}
	return false
}

func formatOrderStatusMessage(o order.OrderDetail, customerName string) string {
	greeting := "kak"
	if strings.TrimSpace(customerName) != "" {
		greeting = "kak " + strings.TrimSpace(customerName)
	}

	var statusDesc string
	switch o.Status {
	case "PENDING":
		statusDesc = "saat ini berstatus *Menunggu Konfirmasi Kasir* 😊 Pesanan akan segera diproses begitu kasir mengonfirmasi."
	case "ACCEPTED":
		statusDesc = "sudah *Dikonfirmasi Kasir* dan sedang dalam antrean persiapan dapur ya!"
	case "PREPARING":
		statusDesc = "saat ini *Sedang Dimasak / Disiapkan* di dapur 👨‍🍳 Mohon ditunggu sebentar ya!"
	case "READY_FOR_PICKUP":
		statusDesc = "*SUDAH JADI & SIAP DIAMBIL* di kasir outlet kami 🎉 Silakan langsung ke kasir untuk pengambilan ya kak!"
	case "COMPLETED":
		statusDesc = "sudah *Selesai* dan telah diambil. Terima kasih banyak sudah berbelanja di Martabak & Terang Bulan Jenggirat! Ada yang bisa kami bantu lagi?"
	case "CANCELLED":
		statusDesc = "berstatus *Dibatalkan*."
	default:
		statusDesc = fmt.Sprintf("saat ini berstatus *%s*.", o.Status)
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Pesanan #%s atas nama %s %s\n", o.OrderNumber, greeting, statusDesc))

	if len(o.Items) > 0 {
		sb.WriteString("\nDetail Menu:\n")
		for _, it := range o.Items {
			sb.WriteString(fmt.Sprintf("- %d %s\n", it.Quantity, it.Name))
		}
	}

	if o.PublicTrackingToken != "" {
		sb.WriteString(fmt.Sprintf("\nKakak juga bisa pantau status terkini di tautan ini:\nhttp://localhost:3000/orders/track/%s", o.PublicTrackingToken))
	}

	return sb.String()
}

func formatNoActiveOrderMessage(customerName string) string {
	greeting := "kak"
	if strings.TrimSpace(customerName) != "" {
		greeting = "kak " + strings.TrimSpace(customerName)
	}
	return fmt.Sprintf("Saat ini belum ada pesanan aktif atas nomor ini %s 😊\n\nMau pesan martabak telur atau terang bulan hari ini? Silakan sebutkan pesanan yang diinginkan, atau ketik 'katalog' untuk melihat daftar menu ya!", greeting)
}

func formatCatalogMenuMessage(categories []catalog.Category, customerName string) string {
	greeting := "kak"
	if strings.TrimSpace(customerName) != "" {
		greeting = "kak " + strings.TrimSpace(customerName)
	}

	var martabakSb strings.Builder
	var terbulSb strings.Builder

	hasMartabak := false
	hasTerbul := false

	for _, cat := range categories {
		if !cat.Active || len(cat.Menus) == 0 {
			continue
		}
		catLower := strings.ToLower(cat.Name)
		isTerbul := strings.Contains(catLower, "terang bulan") || strings.Contains(catLower, "terbul")

		if isTerbul {
			hasTerbul = true
			for _, m := range cat.Menus {
				if !m.Available {
					continue
				}
				terbulSb.WriteString(fmt.Sprintf("• *%s* : Rp %d\n", m.Name, m.PriceAmount))
			}
		} else {
			hasMartabak = true
			martabakSb.WriteString(fmt.Sprintf("\n📋 *%s*\n", strings.ToUpper(cat.Name)))
			for _, m := range cat.Menus {
				if !m.Available {
					continue
				}
				martabakSb.WriteString(fmt.Sprintf("• *%s* (Rp %d)\n", m.Name, m.PriceAmount))
			}
		}
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Halo %s! Berikut daftar menu lezat di Martabak & Terang Bulan Jenggirat:\n", greeting))

	if hasMartabak {
		sb.WriteString("\n🥞 *MARTABAK TELUR SPESIAL (GURIH / ASIN)*\n")
		sb.WriteString("_(Sudah termasuk kuah cuka & acar segar)_\n")
		sb.WriteString(martabakSb.String())
		sb.WriteString("• Pilihan Pedas: Tidak Pedas / Sedang / Pedas\n")
	}

	if hasTerbul {
		sb.WriteString("\n────────────────────────\n")
		sb.WriteString("🧇 *TERANG BULAN MANIS*\n")
		sb.WriteString("_(Adonan lembut bersarang, mentega gurih & susu melimpah)_\n\n")
		sb.WriteString(terbulSb.String())
		sb.WriteString("\n✨ *Bebas Pilih Topping:* Coklat, Keju, Kacang, Pisang, Oreo, Goldenfill, Selai Strawberry, Selai Blueberry\n")
		sb.WriteString("✨ *Pilihan Adonan (Base Cake):* Original (Default), Pandan, Red Velvet, Black Forest, Taro, Mocca, Green Tea\n")
	}

	if !hasMartabak && !hasTerbul {
		sb.WriteString("\n• Terang Bulan Manis (Mulai Rp 18.000)\n• Martabak Telur Spesial (Mulai Rp 20.000)\n")
	}

	sb.WriteString(fmt.Sprintf("\n💡 *Contoh Pemesanan:*\n- _\"Pesan Martabak Sapi Spesial 1\"_\n- _\"Terang Bulan 2 Topping Biasa (Coklat Keju) 1\"_\n\nKakak mau pesan menu yang mana? Langsung sebutkan pesanannya ya %s 😊", greeting))
	return sb.String()
}

func formatRecommendationMessage(customerName string) string {
	greeting := "kak"
	if strings.TrimSpace(customerName) != "" {
		greeting = "kak " + strings.TrimSpace(customerName)
	}
	return fmt.Sprintf("Halo %s! Menu paling favorit dan best seller di outlet kami:\n\n🌟 *Terang Bulan Manis Coklat Keju* - Lembut, legit, dan kejunya melimpah!\n🌟 *Martel Daging Sapi Spesial (3 Telur)* - Gurih, renyah di luar, dan dagingnya tebal!\n\nDijamin bikin nagih %s! Mau coba pesan yang mana hari ini? 😊", greeting, greeting)
}

func formatGreetingMessage(customerName string) string {
	greeting := "kak"
	if strings.TrimSpace(customerName) != "" {
		greeting = "kak " + strings.TrimSpace(customerName)
	}
	return fmt.Sprintf("Halo %s! Selamat datang di Martabak & Terang Bulan Jenggirat. Ada yang bisa kami bantu? Silakan sebutkan pesanan makanan atau minuman yang diinginkan ya kak 😊", greeting)
}

func formatStoreInfoMessage(infoType, customerName string) string {
	greeting := "kak"
	if strings.TrimSpace(customerName) != "" {
		greeting = "kak " + strings.TrimSpace(customerName)
	}
	switch infoType {
	case "hours":
		return fmt.Sprintf("Kedai Martabak & Terang Bulan Jenggirat buka setiap hari pukul *16:00 - 23:00 WIB* ya %s! Silakan jika ingin pesan martabak atau terang bulan untuk menemani malam kakak 😊", greeting)
	case "location":
		return fmt.Sprintf("Kedai Martabak & Terang Bulan Jenggirat berlokasi di *Jl. Ahmad Yani No. 45* (Kediri / Banyuwangi) ya %s 📍\n\nPesanan bisa diambil langsung ke kasir (Pickup / Takeaway) atau pesan lewat WhatsApp ini 😊\n\n📌 *Link Lokasi Google Maps:*\nhttps://maps.google.com/?q=Martabak+Terang+Bulan+Jenggirat", greeting)
	default:
		return fmt.Sprintf("Ada yang bisa kami bantu seputar kedai atau menu Martabak & Terang Bulan Jenggirat %s? 😊", greeting)
	}
}

func formatCategoryInquiryMessage(catType, customerName string) string {
	greeting := "kak"
	if strings.TrimSpace(customerName) != "" {
		greeting = "kak " + strings.TrimSpace(customerName)
	}

	if catType == "terang_bulan" {
		return fmt.Sprintf(`Halo %s! Untuk *Terang Bulan Manis*, mau pesan ukuran apa dan berapa varian topping kak? 😊

Di Jenggirat tersedia ukuran *Biasa* & *Besar*:
🧇 *1 Toping*: Biasa Rp 18.000 / Besar Rp 25.000
🧇 *2 Toping*: Biasa Rp 23.000 / Besar Rp 30.000
🧇 *3 Toping*: Biasa Rp 28.000 / Besar Rp 35.000
🍕 *Cut Pizza All In One*: Rp 45.000

✨ *Pilihan Topping*: Coklat, Keju, Kacang, Pisang, Oreo, Goldenfill, Selai Strawberry, Selai Blueberry.
*(Adonan standar Original Rp 0, atau pilihan Pandan/Red Velvet/Taro +Rp 2.000)*

Kakak mau pesan ukuran apa dan topping rasa apa?`, greeting)
	}

	return fmt.Sprintf(`Halo %s! Untuk *Martabak Telur Spesial*, mau pesan isian apa dan tingkatan berapa telur kak? 😊

Pilihan isian gurih:
🥞 *Sosis / Jamur*: Biasa Rp 20.000 | Spesial Rp 30.000 | Istimewa Rp 40.000
🥞 *Daging Ayam*: Biasa Rp 25.000 | Spesial Rp 35.000 | Istimewa Rp 45.000
🥞 *Daging Sapi*: Biasa Rp 30.000 | Spesial Rp 40.000 | Istimewa Rp 50.000
🧀 *Martel Mozarella*: Mulai Rp 50.000 (1 Isian s/d Mix 4)

Tingkat kepedasan: Tidak Pedas, Sedang, Pedas, Extra Pedas.
Kakak mau pesan isian yang mana?`, greeting)
}
