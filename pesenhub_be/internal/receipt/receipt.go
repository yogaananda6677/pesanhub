package receipt

import (
	"bytes"
	"fmt"
	"strings"
	"time"

	"github.com/go-pdf/fpdf"
)

// ReceiptItem represents one item line on the receipt.
type ReceiptItem struct {
	Name            string
	Modifiers       []string
	Quantity        int
	UnitPriceAmount int64
	LineTotalAmount int64
}

// ReceiptData holds all information required to render an official receipt.
type ReceiptData struct {
	OrderNumber         string
	StoreName           string
	StoreAddress        string
	StorePhone          string
	CustomerName        string
	CustomerPhone       string
	OrderDate           time.Time
	FulfillmentType     string
	Status              string
	Items               []ReceiptItem
	SubtotalAmount      int64
	DiscountAmount      int64
	DiscountName        string
	TotalAmount         int64
	PaymentMethod       string
	PublicTrackingToken string
}

// FormatRupiah formats an int64 amount into Indonesian Rupiah format (e.g. "Rp 45.000").
func FormatRupiah(amount int64) string {
	s := fmt.Sprintf("%d", amount)
	n := len(s)
	if n <= 3 {
		return "Rp " + s
	}
	var sb strings.Builder
	sb.WriteString("Rp ")
	rem := n % 3
	if rem > 0 {
		sb.WriteString(s[:rem])
		if rem < n {
			sb.WriteString(".")
		}
	}
	for i := rem; i < n; i += 3 {
		sb.WriteString(s[i : i+3])
		if i+3 < n {
			sb.WriteString(".")
		}
	}
	return sb.String()
}

// GenerateReceiptPDF generates an official receipt PDF formatted for standard 80mm thermal/mobile view.
func GenerateReceiptPDF(data ReceiptData) ([]byte, error) {
	if data.StoreName == "" {
		data.StoreName = "Martabak & Terang Bulan Jenggirat"
	}
	if data.StoreAddress == "" {
		data.StoreAddress = "Timur Gg. Ketoprak Katang, Kediri"
	}
	if data.StorePhone == "" {
		data.StorePhone = "0822 4350 9775"
	}
	if data.OrderDate.IsZero() {
		data.OrderDate = time.Now()
	}
	if data.PaymentMethod == "" {
		data.PaymentMethod = "Tunai / QRIS Kasir"
	}
	if data.FulfillmentType == "" {
		data.FulfillmentType = "Takeaway (Pickup)"
	}

	// Calculate dynamic height based on item count
	calcHeight := 140.0 + float64(len(data.Items)*10)
	if calcHeight < 160 {
		calcHeight = 160
	}

	pdf := fpdf.NewCustom(&fpdf.InitType{
		UnitStr: "mm",
		Size:    fpdf.SizeType{Wd: 80, Ht: calcHeight},
	})
	pdf.SetMargins(5, 6, 5)
	pdf.SetAutoPageBreak(false, 0)
	pdf.AddPage()

	const printableWd = 70.0

	// 1. Header
	pdf.SetFont("Helvetica", "B", 12)
	pdf.CellFormat(printableWd, 6, "PESENHUB", "", 1, "C", false, 0, "")
	pdf.SetFont("Helvetica", "B", 9)
	pdf.CellFormat(printableWd, 4.5, data.StoreName, "", 1, "C", false, 0, "")
	pdf.SetFont("Helvetica", "", 7.5)
	pdf.CellFormat(printableWd, 3.8, data.StoreAddress, "", 1, "C", false, 0, "")
	pdf.CellFormat(printableWd, 3.8, "Telp/WA: "+data.StorePhone, "", 1, "C", false, 0, "")
	pdf.CellFormat(printableWd, 3, "----------------------------------------------------------------", "", 1, "C", false, 0, "")

	// 2. Receipt Title & Metadata
	pdf.SetFont("Helvetica", "B", 8)
	pdf.CellFormat(printableWd, 4.5, "STRUK PESANAN RESMI", "", 1, "C", false, 0, "")
	pdf.SetFont("Helvetica", "", 7)

	printRow := func(label, value string) {
		pdf.CellFormat(24, 3.6, label, "", 0, "L", false, 0, "")
		pdf.CellFormat(46, 3.6, ": "+value, "", 1, "L", false, 0, "")
	}

	printRow("No. Pesanan", data.OrderNumber)
	loc, _ := time.LoadLocation("Asia/Jakarta")
	if loc == nil {
		loc = time.Local
	}
	printRow("Waktu", data.OrderDate.In(loc).Format("02/01/2006 15:04 WIB"))
	custDisplay := data.CustomerName
	if custDisplay == "" {
		custDisplay = "Pelanggan"
	}
	if data.CustomerPhone != "" {
		custDisplay += fmt.Sprintf(" (%s)", data.CustomerPhone)
	}
	printRow("Pelanggan", custDisplay)
	printRow("Layanan", data.FulfillmentType)

	statusDesc := data.Status
	switch data.Status {
	case "PENDING":
		statusDesc = "Menunggu Konfirmasi Kasir"
	case "ACCEPTED":
		statusDesc = "Dikonfirmasi / Antre Dapur"
	case "PREPARING":
		statusDesc = "Sedang Dimasak / Disiapkan"
	case "READY_FOR_PICKUP":
		statusDesc = "Sudah Siap Diambil"
	case "COMPLETED":
		statusDesc = "Selesai"
	}
	printRow("Status", statusDesc)
	pdf.CellFormat(printableWd, 3, "----------------------------------------------------------------", "", 1, "C", false, 0, "")

	// 3. Items Table Header
	pdf.SetFont("Helvetica", "B", 7)
	pdf.CellFormat(42, 4, "Menu", "", 0, "L", false, 0, "")
	pdf.CellFormat(10, 4, "Qty", "", 0, "C", false, 0, "")
	pdf.CellFormat(18, 4, "Total", "", 1, "R", false, 0, "")

	// 4. Items Table Rows
	pdf.SetFont("Helvetica", "", 7)
	for _, it := range data.Items {
		pdf.SetFont("Helvetica", "B", 7)
		pdf.CellFormat(42, 3.8, it.Name, "", 0, "L", false, 0, "")
		pdf.SetFont("Helvetica", "", 7)
		pdf.CellFormat(10, 3.8, fmt.Sprintf("%d", it.Quantity), "", 0, "C", false, 0, "")
		pdf.CellFormat(18, 3.8, FormatRupiah(it.LineTotalAmount), "", 1, "R", false, 0, "")

		if len(it.Modifiers) > 0 {
			pdf.SetFont("Helvetica", "I", 6)
			modText := "  + " + strings.Join(it.Modifiers, ", ")
			pdf.CellFormat(printableWd, 3, modText, "", 1, "L", false, 0, "")
		}
	}
	pdf.CellFormat(printableWd, 3, "----------------------------------------------------------------", "", 1, "C", false, 0, "")

	// 5. Total & Payment
	if data.DiscountAmount > 0 {
		pdf.SetFont("Helvetica", "", 7.5)
		subtotal := data.SubtotalAmount
		if subtotal == 0 {
			subtotal = data.TotalAmount + data.DiscountAmount
		}
		pdf.CellFormat(40, 4, "Subtotal", "", 0, "L", false, 0, "")
		pdf.CellFormat(30, 4, FormatRupiah(subtotal), "", 1, "R", false, 0, "")

		discLabel := "Diskon"
		if data.DiscountName != "" {
			discLabel = fmt.Sprintf("Diskon (%s)", data.DiscountName)
		}
		pdf.CellFormat(40, 4, discLabel, "", 0, "L", false, 0, "")
		pdf.CellFormat(30, 4, "-"+FormatRupiah(data.DiscountAmount), "", 1, "R", false, 0, "")
	}

	pdf.SetFont("Helvetica", "B", 8)
	pdf.CellFormat(40, 4.5, "TOTAL PEMBAYARAN", "", 0, "L", false, 0, "")
	pdf.CellFormat(30, 4.5, FormatRupiah(data.TotalAmount), "", 1, "R", false, 0, "")

	pdf.SetFont("Helvetica", "", 7)
	pdf.CellFormat(24, 3.6, "Pembayaran", "", 0, "L", false, 0, "")
	pdf.CellFormat(46, 3.6, ": "+data.PaymentMethod, "", 1, "L", false, 0, "")

	pdf.CellFormat(printableWd, 3, "----------------------------------------------------------------", "", 1, "C", false, 0, "")

	// 6. Footer & Tracking
	if data.PublicTrackingToken != "" {
		pdf.SetFont("Helvetica", "I", 6.5)
		pdf.CellFormat(printableWd, 3.2, "Pantau status pesanan secara real-time di:", "", 1, "C", false, 0, "")
		pdf.SetFont("Helvetica", "U", 6.5)
		pdf.CellFormat(printableWd, 3.2, "http://localhost:3000/orders/track/"+data.PublicTrackingToken, "", 1, "C", false, 0, "")
	}

	pdf.SetFont("Helvetica", "B", 7)
	pdf.CellFormat(printableWd, 4.5, "Terima kasih atas pesanan Anda!", "", 1, "C", false, 0, "")
	pdf.SetFont("Helvetica", "I", 6.5)
	pdf.CellFormat(printableWd, 3.2, "Simpan struk digital ini sebagai bukti pemesanan.", "", 1, "C", false, 0, "")

	var buf bytes.Buffer
	if err := pdf.Output(&buf); err != nil {
		return nil, fmt.Errorf("failed to output receipt PDF: %w", err)
	}

	return buf.Bytes(), nil
}
