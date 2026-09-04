package notification

import (
	"fmt"
	"strings"
)

const DefaultTemplateVersion = "v1"

// FormatCurrency formats an amount in Rupiah with thousand separators.
func FormatCurrency(amount int64) string {
	sign := ""
	if amount < 0 {
		sign = "-"
		amount = -amount
	}
	s := fmt.Sprintf("%d", amount)
	n := len(s)
	if n <= 3 {
		return fmt.Sprintf("%sRp %s", sign, s)
	}
	var b strings.Builder
	b.WriteString(sign)
	b.WriteString("Rp ")
	rem := n % 3
	if rem > 0 {
		b.WriteString(s[:rem])
		if n > rem {
			b.WriteString(".")
		}
	}
	for i := rem; i < n; i += 3 {
		b.WriteString(s[i : i+3])
		if i+3 < n {
			b.WriteString(".")
		}
	}
	return b.String()
}

// BuildTrackingURL constructs the full tracking link.
func BuildTrackingURL(baseURL, token string) string {
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if baseURL == "" {
		baseURL = "https://pesenhub.id/orders/track"
	}
	token = strings.TrimSpace(token)
	if token == "" {
		return baseURL
	}
	return fmt.Sprintf("%s/%s", baseURL, token)
}

// RenderTemplate renders the approved template for the given notification type.
func RenderTemplate(notifType NotificationType, data OrderNotificationData) (string, error) {
	switch notifType {
	case TypeConfirmation:
		return RenderConfirmation(data), nil
	case TypeAccepted:
		return RenderAccepted(data), nil
	case TypeCompleted:
		return RenderCompleted(data), nil
	default:
		return "", fmt.Errorf("unsupported notification type: %s", notifType)
	}
}

// RenderConfirmation renders the order confirmation message.
func RenderConfirmation(data OrderNotificationData) string {
	var sb strings.Builder
	sb.WriteString("🔔 *Konfirmasi Pesanan PesenHub*\n\n")

	custName := strings.TrimSpace(data.CustomerName)
	if custName == "" {
		custName = "Pelanggan"
	}
	sb.WriteString(fmt.Sprintf("Halo *%s*, pesanan Anda telah berhasil dibuat!\n\n", custName))
	sb.WriteString(fmt.Sprintf("*No. Pesanan:* %s\n", data.OrderNumber))
	sb.WriteString("*Metode:* Ambil di Outlet (PICKUP)\n\n")

	sb.WriteString("*Rincian Pesanan:*\n")
	if len(data.Items) == 0 {
		sb.WriteString("• (Detail item dicatat di kasir)\n")
	} else {
		for _, item := range data.Items {
			modStr := ""
			if len(item.Modifiers) > 0 {
				modStr = fmt.Sprintf(" (%s)", strings.Join(item.Modifiers, ", "))
			}
			lineTotalFormatted := FormatCurrency(item.LineTotal)
			sb.WriteString(fmt.Sprintf("• %dx %s%s — %s\n", item.Quantity, item.Name, modStr, lineTotalFormatted))
			if strings.TrimSpace(item.Notes) != "" {
				sb.WriteString(fmt.Sprintf("  Catatan: %s\n", strings.TrimSpace(item.Notes)))
			}
		}
	}

	sb.WriteString(fmt.Sprintf("\n*Total Pembayaran:* %s\n\n", FormatCurrency(data.TotalAmount)))

	trackingURL := BuildTrackingURL(data.TrackingBaseURL, data.TrackingToken)
	sb.WriteString("Pantau status pesanan Anda melalui tautan berikut:\n")
	sb.WriteString(fmt.Sprintf("%s\n\n", trackingURL))
	sb.WriteString("Terima kasih telah memesan di PesenHub! 🙏")

	return sb.String()
}

// RenderAccepted renders the order accepted / preparing message.
func RenderAccepted(data OrderNotificationData) string {
	var sb strings.Builder
	sb.WriteString("🍳 *Pesanan Diterima — PesenHub*\n\n")

	custName := strings.TrimSpace(data.CustomerName)
	if custName == "" {
		custName = "Pelanggan"
	}
	sb.WriteString(fmt.Sprintf("Halo *%s*, pesanan Anda *%s* telah diterima oleh outlet dan sedang dipersiapkan di dapur.\n\n", custName, data.OrderNumber))

	trackingURL := BuildTrackingURL(data.TrackingBaseURL, data.TrackingToken)
	sb.WriteString("Pantau status pesanan:\n")
	sb.WriteString(fmt.Sprintf("%s\n\n", trackingURL))
	sb.WriteString("Mohon ditunggu, kami akan memberi tahu jika pesanan sudah siap diambil.")

	return sb.String()
}

// RenderCompleted renders the order ready for pickup / completed message.
func RenderCompleted(data OrderNotificationData) string {
	var sb strings.Builder
	sb.WriteString("✅ *Pesanan Siap Diambil — PesenHub*\n\n")

	custName := strings.TrimSpace(data.CustomerName)
	if custName == "" {
		custName = "Pelanggan"
	}
	sb.WriteString(fmt.Sprintf("Halo *%s*, pesanan Anda *%s* telah SELESAI dan siap diambil di outlet!\n\n", custName, data.OrderNumber))
	sb.WriteString("Silakan tunjukkan nomor pesanan ini ke kasir saat pengambilan.\n\n")
	sb.WriteString("Terima kasih telah memesan di PesenHub! 🙏")

	return sb.String()
}
