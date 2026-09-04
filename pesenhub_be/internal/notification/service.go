package notification

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"

	"pesenhub/backend/internal/waha"
)

// Notifier defines the interface for triggering notifications.
type Notifier interface {
	Dispatch(ctx context.Context, notifType NotificationType, data OrderNotificationData) (*NotificationResult, error)
	NotifyConfirmation(ctx context.Context, data OrderNotificationData) (*NotificationResult, error)
	NotifyAccepted(ctx context.Context, data OrderNotificationData) (*NotificationResult, error)
	NotifyCompleted(ctx context.Context, data OrderNotificationData) (*NotificationResult, error)
}

// Service coordinates notification dispatch, template rendering, idempotency, and guard checks.
type Service struct {
	store           Store
	sender          waha.Sender
	trackingBaseURL string
	logger          *slog.Logger
}

// Config configures the Notification Service.
type Config struct {
	Store           Store
	Sender          waha.Sender
	TrackingBaseURL string
	Logger          *slog.Logger
}

// NewService creates a new Notification Service.
func NewService(cfg Config) *Service {
	logger := cfg.Logger
	if logger == nil {
		logger = slog.Default()
	}
	baseURL := strings.TrimSpace(cfg.TrackingBaseURL)
	if baseURL == "" {
		baseURL = "https://pesenhub.id/orders/track"
	}
	return &Service{
		store:           cfg.Store,
		sender:          cfg.Sender,
		trackingBaseURL: baseURL,
		logger:          logger,
	}
}

// NotifyConfirmation sends an order confirmation notification.
func (s *Service) NotifyConfirmation(ctx context.Context, data OrderNotificationData) (*NotificationResult, error) {
	return s.Dispatch(ctx, TypeConfirmation, data)
}

// NotifyAccepted sends an order accepted / kitchen preparing notification.
func (s *Service) NotifyAccepted(ctx context.Context, data OrderNotificationData) (*NotificationResult, error) {
	return s.Dispatch(ctx, TypeAccepted, data)
}

// NotifyCompleted sends an order completed / ready for pickup notification.
func (s *Service) NotifyCompleted(ctx context.Context, data OrderNotificationData) (*NotificationResult, error) {
	return s.Dispatch(ctx, TypeCompleted, data)
}

// Dispatch processes and sends a single order notification with idempotency and guard verification.
// Even if sending to WAHA fails, this returns a structured result without rolling back domain state.
func (s *Service) Dispatch(ctx context.Context, notifType NotificationType, data OrderNotificationData) (*NotificationResult, error) {
	if strings.TrimSpace(data.OrderID) == "" {
		return nil, errors.New("order_id is required")
	}

	// 1. Recipient phone normalization
	phone, quarantined, reason := waha.NormalizeSenderPhone(data.CustomerPhone)
	if quarantined || phone == "" {
		s.logger.Warn("notification suppressed: invalid customer phone",
			"order_id", data.OrderID,
			"masked_phone", waha.MaskPhone(data.CustomerPhone),
			"quarantine_reason", reason,
		)
		return &NotificationResult{
			OrderID:          data.OrderID,
			NotificationType: notifType,
			Status:           StatusFailed,
			Error:            fmt.Errorf("%w: %s", ErrInvalidRecipient, reason),
		}, nil
	}
	data.CustomerPhone = phone

	if strings.TrimSpace(data.TrackingBaseURL) == "" {
		data.TrackingBaseURL = s.trackingBaseURL
	}

	// 2. Render approved template
	msgText, err := RenderTemplate(notifType, data)
	if err != nil {
		return nil, fmt.Errorf("failed to render template: %w", err)
	}

	// 3. At-most-once idempotency check via unique key
	templateVersion := DefaultTemplateVersion
	idempotencyKey := fmt.Sprintf("order:%s:type:%s:v:%s", data.OrderID, notifType, templateVersion)

	rec := &NotificationRecord{
		OrderID:          data.OrderID,
		CustomerPhone:    data.CustomerPhone,
		NotificationType: notifType,
		TemplateVersion:  templateVersion,
		IdempotencyKey:   idempotencyKey,
		MessageText:      msgText,
	}

	pending, isNew, err := s.store.CreatePending(ctx, rec)
	if err != nil {
		return nil, fmt.Errorf("failed to create pending notification: %w", err)
	}

	if !isNew {
		// Existing notification found
		if pending.Status == StatusSent || pending.Status == StatusSuppressed {
			s.logger.Info("notification deduplicated: already dispatched",
				"order_id", data.OrderID,
				"masked_phone", waha.MaskPhone(data.CustomerPhone),
				"type", notifType,
				"status", pending.Status,
			)
			return &NotificationResult{
				RecordID:          pending.ID,
				OrderID:           pending.OrderID,
				NotificationType:  pending.NotificationType,
				Status:            pending.Status,
				SuppressReason:    derefString(pending.SuppressReason),
				ProviderMessageID: derefString(pending.ProviderMessageID),
				IsDuplicate:       true,
			}, nil
		}
	}
	recordID := pending.ID

	// 4. Opt-Out Guard
	optedOut, err := s.store.IsOptedOut(ctx, data.CustomerPhone)
	if err != nil {
		s.logger.Error("error checking opt-out status", "error", err, "phone", waha.MaskPhone(data.CustomerPhone))
	} else if optedOut {
		_ = s.store.MarkSuppressed(ctx, recordID, SuppressCustomerOptedOut)
		s.logger.Info("notification suppressed: customer opted out",
			"order_id", data.OrderID,
			"masked_phone", waha.MaskPhone(data.CustomerPhone),
			"type", notifType,
		)
		return &NotificationResult{
			RecordID:         recordID,
			OrderID:          data.OrderID,
			NotificationType: notifType,
			Status:           StatusSuppressed,
			SuppressReason:   string(SuppressCustomerOptedOut),
		}, nil
	}

	// 5. Conversation Paused & Handoff Guard
	isPaused, pauseReason, err := s.store.IsConversationPaused(ctx, data.CustomerPhone)
	if err != nil {
		s.logger.Error("error checking conversation pause status", "error", err, "phone", waha.MaskPhone(data.CustomerPhone))
	} else if isPaused {
		_ = s.store.MarkSuppressed(ctx, recordID, pauseReason)
		s.logger.Info("notification suppressed: conversation paused or handoff active",
			"order_id", data.OrderID,
			"masked_phone", waha.MaskPhone(data.CustomerPhone),
			"type", notifType,
			"reason", pauseReason,
		)
		return &NotificationResult{
			RecordID:         recordID,
			OrderID:          data.OrderID,
			NotificationType: notifType,
			Status:           StatusSuppressed,
			SuppressReason:   string(pauseReason),
		}, nil
	}

	// 6. External transport dispatch via WAHA
	if s.sender == nil {
		_ = s.store.MarkFailed(ctx, recordID, "sender_not_configured")
		return &NotificationResult{
			RecordID:         recordID,
			OrderID:          data.OrderID,
			NotificationType: notifType,
			Status:           StatusFailed,
			Error:            errors.New("sender_not_configured"),
		}, nil
	}

	providerMsgID, sendErr := s.sender.SendMessage(ctx, data.CustomerPhone, msgText)
	if sendErr != nil {
		_ = s.store.MarkFailed(ctx, recordID, sendErr.Error())
		s.logger.Warn("failed to send WhatsApp message via WAHA",
			"order_id", data.OrderID,
			"masked_phone", waha.MaskPhone(data.CustomerPhone),
			"type", notifType,
			"error", sendErr.Error(),
		)
		return &NotificationResult{
			RecordID:         recordID,
			OrderID:          data.OrderID,
			NotificationType: notifType,
			Status:           StatusFailed,
			Error:            sendErr,
		}, nil
	}

	_ = s.store.MarkSent(ctx, recordID, providerMsgID)
	s.logger.Info("successfully sent WhatsApp notification via WAHA",
		"order_id", data.OrderID,
		"masked_phone", waha.MaskPhone(data.CustomerPhone),
		"type", notifType,
		"provider_message_id", providerMsgID,
	)

	return &NotificationResult{
		RecordID:          recordID,
		OrderID:           data.OrderID,
		NotificationType:  notifType,
		Status:            StatusSent,
		ProviderMessageID: providerMsgID,
	}, nil
}

func derefString(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
