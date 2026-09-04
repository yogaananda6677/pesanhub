package order

import (
	"context"
	"log/slog"
	"strings"

	"pesenhub/backend/internal/notification"
)

// NotificationDispatcher triggers external customer notifications based on domain events.
type NotificationDispatcher interface {
	NotifyStatusTransition(ctx context.Context, orderID, fromStatus, toStatus string)
	NotifyOrderCreated(ctx context.Context, orderID string)
}

// WhatsAppNotificationDispatcher implements NotificationDispatcher using the notification.Notifier service.
type WhatsAppNotificationDispatcher struct {
	reader   Reader
	notifier notification.Notifier
	logger   *slog.Logger
}

// NewNotificationDispatcher creates a new WhatsAppNotificationDispatcher.
func NewNotificationDispatcher(reader Reader, notifier notification.Notifier, logger *slog.Logger) *WhatsAppNotificationDispatcher {
	if logger == nil {
		logger = slog.Default()
	}
	return &WhatsAppNotificationDispatcher{
		reader:   reader,
		notifier: notifier,
		logger:   logger,
	}
}

// NotifyStatusTransition evaluates status transition and dispatches ACCEPTED or COMPLETED notification.
func (d *WhatsAppNotificationDispatcher) NotifyStatusTransition(ctx context.Context, orderID, fromStatus, toStatus string) {
	if d == nil || d.notifier == nil || d.reader == nil {
		return
	}

	var notifType notification.NotificationType
	switch toStatus {
	case "ACCEPTED":
		notifType = notification.TypeAccepted
	case "COMPLETED":
		notifType = notification.TypeCompleted
	default:
		return
	}

	detail, err := d.reader.GetByID(ctx, orderID)
	if err != nil {
		d.logger.Warn("failed to fetch order details for status transition notification", "order_id", orderID, "error", err)
		return
	}

	if detail.CustomerPhone == nil || strings.TrimSpace(*detail.CustomerPhone) == "" {
		return
	}

	notifData := buildNotificationData(detail)
	_, _ = d.notifier.Dispatch(ctx, notifType, notifData)
}

// NotifyOrderCreated dispatches an order confirmation notification.
func (d *WhatsAppNotificationDispatcher) NotifyOrderCreated(ctx context.Context, orderID string) {
	if d == nil || d.notifier == nil || d.reader == nil {
		return
	}

	detail, err := d.reader.GetByID(ctx, orderID)
	if err != nil {
		d.logger.Warn("failed to fetch order details for creation notification", "order_id", orderID, "error", err)
		return
	}

	if detail.CustomerPhone == nil || strings.TrimSpace(*detail.CustomerPhone) == "" {
		return
	}

	notifData := buildNotificationData(detail)
	_, _ = d.notifier.NotifyConfirmation(ctx, notifData)
}

func buildNotificationData(detail OrderDetail) notification.OrderNotificationData {
	phone := ""
	if detail.CustomerPhone != nil {
		phone = *detail.CustomerPhone
	}

	items := make([]notification.OrderItemSummary, len(detail.Items))
	for i, it := range detail.Items {
		mods := make([]string, len(it.Modifiers))
		for j, m := range it.Modifiers {
			mods[j] = m.Name
		}
		items[i] = notification.OrderItemSummary{
			Name:      it.Name,
			Quantity:  it.Quantity,
			UnitPrice: it.UnitPriceAmount,
			LineTotal: it.LineTotalAmount,
			Modifiers: mods,
			Notes:     it.Notes,
		}
	}

	return notification.OrderNotificationData{
		OrderID:       detail.ID,
		OrderNumber:   detail.OrderNumber,
		CustomerName:  detail.CustomerName,
		CustomerPhone: phone,
		TotalAmount:   detail.TotalAmount,
		TrackingToken: detail.PublicTrackingToken,
		Items:         items,
	}
}
