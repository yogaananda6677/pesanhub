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

// CustomerNameResolver optionally resolves the latest verified customer name by phone number.
type CustomerNameResolver interface {
	Get(ctx context.Context, phone string) (string, error)
}

// WhatsAppNotificationDispatcher implements NotificationDispatcher using the notification.Notifier service.
type WhatsAppNotificationDispatcher struct {
	reader       Reader
	notifier     notification.Notifier
	nameResolver CustomerNameResolver
	logger       *slog.Logger
}

// NewNotificationDispatcher creates a new WhatsAppNotificationDispatcher.
func NewNotificationDispatcher(reader Reader, notifier notification.Notifier, logger *slog.Logger, resolver ...CustomerNameResolver) *WhatsAppNotificationDispatcher {
	if logger == nil {
		logger = slog.Default()
	}
	var res CustomerNameResolver
	if len(resolver) > 0 {
		res = resolver[0]
	}
	return &WhatsAppNotificationDispatcher{
		reader:       reader,
		notifier:     notifier,
		nameResolver: res,
		logger:       logger,
	}
}

// SetCustomerNameResolver sets an optional customer name resolver.
func (d *WhatsAppNotificationDispatcher) SetCustomerNameResolver(resolver CustomerNameResolver) {
	if d != nil {
		d.nameResolver = resolver
	}
}

// NotifyStatusTransition evaluates status transition and dispatches ACCEPTED or COMPLETED notification.
func (d *WhatsAppNotificationDispatcher) NotifyStatusTransition(ctx context.Context, orderID, fromStatus, toStatus string) {
	if d == nil || d.notifier == nil || d.reader == nil {
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

	// Single Communication Channel Policy:
	// 1. If order was created via WhatsApp bot, the customer already received order confirmation & PDF receipt in chat.
	// Suppress ACCEPTED notification so customer is not spammed.
	// Only notify when food is actually ready for pickup (READY_FOR_PICKUP).
	if strings.EqualFold(strings.TrimSpace(detail.Source), "WHATSAPP") && toStatus == "ACCEPTED" {
		d.logger.Info("suppressing ACCEPTED notification for WHATSAPP order", "order_id", orderID)
		return
	}

	var notifType notification.NotificationType
	switch toStatus {
	case "ACCEPTED":
		notifType = notification.TypeAccepted
	case "READY_FOR_PICKUP", "COMPLETED":
		notifType = notification.TypeCompleted
	default:
		return
	}

	notifData := d.buildNotificationData(ctx, detail)
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

	// Single Receipt Policy: If order was created directly via WhatsApp bot conversation,
	// Hermes already sent the success reply text and the PDF receipt in the active chat.
	// Suppress duplicate confirmation message.
	if strings.EqualFold(strings.TrimSpace(detail.Source), "WHATSAPP") {
		d.logger.Info("suppressing duplicate WhatsApp confirmation notification for WHATSAPP order", "order_id", orderID)
		return
	}

	notifData := d.buildNotificationData(ctx, detail)
	_, _ = d.notifier.NotifyConfirmation(ctx, notifData)
}

func (d *WhatsAppNotificationDispatcher) buildNotificationData(ctx context.Context, detail OrderDetail) notification.OrderNotificationData {
	phone := ""
	if detail.CustomerPhone != nil {
		phone = *detail.CustomerPhone
	}

	customerName := detail.CustomerName
	if d != nil && d.nameResolver != nil && phone != "" {
		if resolvedName, err := d.nameResolver.Get(ctx, phone); err == nil && strings.TrimSpace(resolvedName) != "" {
			customerName = strings.TrimSpace(resolvedName)
		}
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
		CustomerName:  customerName,
		CustomerPhone: phone,
		TotalAmount:   detail.TotalAmount,
		TrackingToken: detail.PublicTrackingToken,
		Items:         items,
	}
}
