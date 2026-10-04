package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"pesenhub/backend/internal/appauth"
	"pesenhub/backend/internal/branch"
	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/config"
	"pesenhub/backend/internal/contact"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/database"
	"pesenhub/backend/internal/discount"
	"pesenhub/backend/internal/evaluation"
	"pesenhub/backend/internal/gowa"
	"pesenhub/backend/internal/health"
	"pesenhub/backend/internal/hermes"
	"pesenhub/backend/internal/httpserver"
	"pesenhub/backend/internal/inviteemail"
	"pesenhub/backend/internal/notification"
	orderapi "pesenhub/backend/internal/order"
	"pesenhub/backend/internal/payment"
	"pesenhub/backend/internal/report"
	"pesenhub/backend/internal/superadmin"
	"pesenhub/backend/internal/ws"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg, err := config.Load()
	if err != nil {
		logger.Error("configuration loading failed", "error", "invalid configuration")
		os.Exit(1)
	}
	sessions, err := appauth.NewSessionManager(cfg.Auth.SessionSecret, cfg.Auth.SessionTTL)
	if err != nil {
		logger.Error("session configuration failed", "error", "invalid configuration")
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	pool, err := database.Open(ctx, cfg.Database.DSN())
	if err != nil {
		logger.Error("database connection failed", "error", "database unavailable", "detail", err.Error())
		os.Exit(1)
	}
	defer pool.Close()
	identityStore := appauth.NewStore(pool)
	sessions.SetValidator(identityStore)
	googleVerifier, err := appauth.NewOIDCGoogleVerifier(ctx, cfg.Auth.GoogleClientID)
	if err != nil {
		logger.Error("Google authentication configuration failed", "error", "invalid configuration")
		os.Exit(1)
	}
	googleAuth, err := appauth.NewGoogleHandler(googleVerifier, identityStore, sessions)
	if err != nil {
		logger.Error("authentication handler configuration failed", "error", "invalid configuration")
		os.Exit(1)
	}
	googleAuth.SetPasswordAuth(appauth.PasswordAuthConfig{
		AdminUsername:   cfg.Auth.AdminUsername,
		AdminPassword:   cfg.Auth.AdminPassword,
		CashierUsername: cfg.Auth.CashierUsername,
		CashierPassword: cfg.Auth.CashierPassword,
		SuperadminUser:  cfg.Auth.SuperadminUsername,
		SuperadminPass:  cfg.Auth.SuperadminPassword,
	})
	wc := gowa.New(cfg.GOWA.BaseURL, cfg.GOWA.Username, cfg.GOWA.Password, cfg.GOWA.DeviceID, cfg.GOWA.Timeout)
	gowaStore := gowa.NewStore(pool)
	h := health.New("pesenhub-api", pool, wc)
	customerStore := customer.NewStore(pool)
	customerService := customer.NewService(customerStore, customer.NewID)
	customers := customer.NewHandler(customerService)
	catalogService := catalog.NewService(catalog.NewStore(pool), customer.NewID)
	catalogHandler := catalog.NewHandler(catalogService)

	orderStore := orderapi.NewStore(pool)
	orderHub := ws.NewHub()
	defer orderHub.Close()
	publisher := orderapi.NewOutboxPublisher(pool, orderapi.NewHubBroadcasterAdapter(orderHub), logger)
	orderStore.SetNotifier(publisher)
	go publisher.Start(ctx, 500*time.Millisecond)
	orderService := orderapi.NewService(orderStore)
	notifStore := notification.NewPGStore(pool)
	notifWorker := notification.NewOutboxWorker(notification.WorkerConfig{
		Store:  notifStore,
		Sender: wc,
		Logger: logger,
	})
	notifService := notification.NewService(notification.Config{
		Store:  notifStore,
		Sender: wc,
		Worker: notifWorker,
		Logger: logger,
	})
	go notifWorker.Start(ctx, 1*time.Second)
	notifDispatcher := orderapi.NewNotificationDispatcher(orderStore, notifService, logger)
	orderService.SetNotificationDispatcher(notifDispatcher)
	orders := orderapi.NewHandler(orderService, orderHub)
	paymentStore := payment.NewStore(pool)
	midtransClient := payment.NewMidtransClient(cfg.Midtrans.BaseURL, cfg.Midtrans.ServerKey, cfg.Midtrans.Timeout)
	paymentService := payment.NewServiceWithMidtrans(paymentStore, midtransClient)
	reconciler := payment.NewReconciler(payment.ReconcilerConfig{Store: paymentStore, Gateway: midtransClient, Logger: logger})
	payments := payment.NewHandlerWithReconciler(paymentService, reconciler)
	midtransWebhook := payment.NewMidtransWebhookHandler(cfg.Midtrans.ServerKey, cfg.Midtrans.MerchantID, paymentStore, logger)
	go reconciler.Start(ctx)

	var llmClient hermes.LLMClient
	if cfg.Hermes.BaseURL != "" && cfg.App.Env != "test" {
		llmClient = hermes.NewAgentClient(cfg.Hermes.BaseURL, cfg.Hermes.APIKey, cfg.Hermes.Model, cfg.Hermes.Timeout)
	} else {
		llmClient = &hermes.MockLLMClient{}
	}

	hermesStore := hermes.NewStore(pool)
	hermesConvStore := hermes.NewPGConversationStore(pool)
	hermesService := hermes.NewService(hermes.Config{
		Client:              llmClient,
		CatalogProvider:     catalogService,
		OrderCreator:        orderService,
		OrderReader:         orderStore,
		CustomerMemory:      customerService,
		Store:               hermesStore,
		ConversationStore:   hermesConvStore,
		ModelName:           cfg.Hermes.Model,
		ConfidenceThreshold: cfg.Hermes.ConfidenceThreshold,
		MaxAttempts:         cfg.Hermes.MaxAttempts,
	})
	hermesHandler := hermes.NewHandler(hermesService)
	hermesTools := hermes.NewToolHandler(catalogService, cfg.Hermes.ToolAPIKey)

	contactStore := contact.NewStore(pool)
	contactHandler := contact.NewHandler(contactStore)
	evaluationStore := evaluation.NewStore(pool)
	evaluationHandler := evaluation.NewHandler(evaluationStore)

	onWhatsAppMessage := func(msgCtx context.Context, msg *gowa.InboundMessage) {
		if msg == nil || strings.TrimSpace(msg.MessageBody) == "" {
			return
		}
		senderPhone := strings.TrimSpace(msg.FromRaw)
		if msg.PhoneE164 != nil && strings.TrimSpace(*msg.PhoneE164) != "" {
			senderPhone = strings.TrimSpace(*msg.PhoneE164)
		}
		if senderPhone == "" {
			return
		}
		session := strings.TrimSpace(msg.SessionID)
		if session == "" {
			session = "default"
		}
		correlationID := strings.TrimSpace(msg.WebhookRequestID)
		if correlationID == "" {
			correlationID = msg.ID
		}

		// Check contact rules: Is this contact marked as NON_CUSTOMER or is auto-reply disabled?
		existingContact, cErr := contactStore.GetByPhone(msgCtx, senderPhone)
		if cErr == nil && existingContact != nil {
			if !existingContact.AutoReplyEnabled || existingContact.ContactType == contact.TypeNonCustomer || existingContact.ContactType == contact.TypeBlacklist {
				logger.Info("Skipping Hermes AI auto-reply for non-customer / disabled contact", "sender", senderPhone, "contact_type", existingContact.ContactType, "auto_reply", existingContact.AutoReplyEnabled)
				return
			}
		} else {
			// Auto-register new contact as CUSTOMER with auto_reply_enabled = true
			_, _ = contactStore.Upsert(msgCtx, contact.UpsertContactInput{
				BranchID:    branch.DefaultBranchID,
				Phone:       senderPhone,
				Name:        msg.SenderName,
				ContactType: contact.TypeCustomer,
			})
		}

		// Show typing presence indicator on customer's WhatsApp while AI processes turn
		_ = wc.SendChatPresence(msgCtx, senderPhone, "start")
		defer func() {
			_ = wc.SendChatPresence(context.Background(), senderPhone, "stop")
		}()

		turnResp, err := hermesService.ProcessTurn(msgCtx, hermes.TurnRequest{
			InboundMessageID: &msg.ID,
			Session:          session,
			SenderPhone:      senderPhone,
			CustomerName:     msg.SenderName,
			MessageText:      msg.MessageBody,
			CorrelationID:    correlationID,
		})
		if err != nil {
			logger.Error("Hermes WhatsApp turn processing error", "error", err, "sender", senderPhone, "msg_id", msg.ID)
			return
		}

		// Record turn for AI evaluation & training dataset
		if turnResp != nil {
			var draftData any = turnResp.Draft
			if draftData == nil && turnResp.State != nil {
				draftData = turnResp.State.CurrentDraft
			}
			extractedJSON, _ := json.Marshal(draftData)
			var convID *string
			if turnResp.State != nil && turnResp.State.ID != "" {
				convID = &turnResp.State.ID
			}
			_, _ = evaluationStore.RecordTurn(msgCtx, evaluation.RecordTurnInput{
				BranchID:         branch.DefaultBranchID,
				InboundMessageID: &msg.ID,
				ConversationID:   convID,
				SenderPhone:      senderPhone,
				CustomerName:     msg.SenderName,
				InputText:        msg.MessageBody,
				AIReply:          turnResp.ReplyText,
				ExtractedDraft:   json.RawMessage(extractedJSON),
			})
		}
		if turnResp != nil {
			if strings.TrimSpace(turnResp.ReplyText) != "" {
				if _, sendErr := wc.SendMessage(msgCtx, senderPhone, turnResp.ReplyText); sendErr != nil {
					logger.Error("Failed to send Hermes reply via WhatsApp", "error", sendErr, "sender", senderPhone)
				} else {
					logger.Info("Sent Hermes text reply via WhatsApp", "sender", senderPhone)
				}
			}
			for _, att := range turnResp.MediaAttachments {
				data := att.Data
				if len(data) == 0 && att.FilePath != "" {
					data, _ = os.ReadFile(att.FilePath)
				}
				if len(data) == 0 {
					logger.Warn("Hermes media attachment has empty data or missing file", "filename", att.Filename, "path", att.FilePath)
					continue
				}
				if att.Type == "image" {
					if _, imgErr := wc.SendImage(msgCtx, senderPhone, att.Caption, data, att.Filename); imgErr != nil {
						logger.Error("Failed to send Hermes image attachment via WhatsApp", "error", imgErr, "filename", att.Filename, "bytes", len(data), "sender", senderPhone)
					} else {
						logger.Info("Sent Hermes image attachment via WhatsApp", "filename", att.Filename, "bytes", len(data), "sender", senderPhone)
					}
				} else if att.Type == "document" {
					if _, docErr := wc.SendFile(msgCtx, senderPhone, att.Caption, data, att.Filename); docErr != nil {
						logger.Error("Failed to send Hermes file attachment via WhatsApp", "error", docErr, "filename", att.Filename, "bytes", len(data), "sender", senderPhone)
					} else {
						logger.Info("Sent Hermes file attachment via WhatsApp", "filename", att.Filename, "bytes", len(data), "sender", senderPhone)
					}
				}
			}
		}
	}
	gowaWebhook := gowa.NewWebhookHandler(
		cfg.GOWA.WebhookSecret,
		logger,
		gowa.WithStore(gowaStore),
		gowa.WithOnMessage(onWhatsAppMessage),
		gowa.WithAsyncOnMessage(cfg.Hermes.Timeout+cfg.GOWA.Timeout+5*time.Second),
	)

	superadminStore := superadmin.NewStore(pool)
	superadminService := superadmin.NewService(superadminStore, pool, wc, orderHub)
	if cfg.InviteEmail.Enabled {
		inviteSender, senderErr := inviteemail.NewGmailSender(cfg.InviteEmail.Username, cfg.InviteEmail.AppPassword, cfg.InviteEmail.FromName, cfg.InviteEmail.LoginURL)
		if senderErr != nil {
			logger.Error("invitation email configuration failed", "error", "invalid configuration")
			os.Exit(1)
		}
		superadminService.SetInvitationSender(inviteSender)
	}
	superadminHandler := superadmin.NewHandler(superadminService)
	superadminHandler.SetAuth(
		superadmin.AuthConfig{
			Username: cfg.Auth.SuperadminUsername,
			Password: cfg.Auth.SuperadminPassword,
		},
		identityStore,
		sessions,
	)
	gowaSettings := gowa.NewSettingsHandler(wc)
	branchStore := branch.NewStore(pool)
	branchService := branch.NewService(branchStore)
	branchHandler := branch.NewHandler(branchService)
	reportStore := report.NewStore(pool)
	reportService := report.NewService(reportStore, branchService)
	reportHandler := report.NewHandler(reportService)
	discountStore := discount.NewStore(pool)
	discountHandler := discount.NewHandler(discountStore)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health/live", h.Live)
	mux.HandleFunc("GET /health/ready", h.Ready)
	mux.HandleFunc("GET /api/v1/reports/summary", reportHandler.Summary)
	mux.HandleFunc("GET /api/v1/branches", branchHandler.List)
	mux.HandleFunc("POST /api/v1/admin/branches", branchHandler.Create)
	mux.HandleFunc("PATCH /api/v1/admin/branches/{id}", branchHandler.Update)
	mux.HandleFunc("PATCH /api/v1/admin/users/{id}/branch", branchHandler.AssignUser)
	mux.HandleFunc("GET /api/v1/settings/whatsapp", gowaSettings.GetSettings)
	mux.HandleFunc("POST /api/v1/settings/whatsapp/pair", gowaSettings.PairDevice)
	mux.HandleFunc("POST /api/v1/settings/whatsapp/disconnect", gowaSettings.DisconnectDevice)
	mux.HandleFunc("GET /api/v1/settings/whatsapp/qr-image", gowaSettings.ProxyQRImage)
	mux.HandleFunc("POST /api/v1/auth/google/challenge", googleAuth.Challenge)
	mux.HandleFunc("POST /api/v1/auth/google", googleAuth.Login)
	mux.HandleFunc("POST /api/v1/auth/login", googleAuth.LoginPassword)
	mux.HandleFunc("GET /api/v1/auth/me", googleAuth.Me)
	mux.HandleFunc("PATCH /api/v1/auth/me", googleAuth.UpdateMe)
	mux.HandleFunc("POST /api/v1/auth/logout", googleAuth.Logout)
	mux.Handle("POST /webhooks/gowa", gowaWebhook)
	mux.Handle("POST /webhooks/midtrans", midtransWebhook)
	mux.HandleFunc("POST /api/v1/customers", customers.Create)
	mux.HandleFunc("PATCH /api/v1/customers/{id}", customers.Update)
	mux.HandleFunc("GET /api/v1/customers/{id}/orders", customers.History)
	mux.HandleFunc("GET /api/v1/public/menu", catalogHandler.Public)
	mux.HandleFunc("POST /api/v1/public/orders/preview", orders.PreviewWeb)
	mux.HandleFunc("POST /api/v1/public/orders", orders.CreateWeb)
	mux.HandleFunc("GET /api/v1/public/orders/{token}", orders.GetByPublicToken)
	mux.HandleFunc("GET /api/v1/hermes/tools/catalog", hermesTools.Catalog)
	mux.HandleFunc("GET /api/v1/agent/status", hermesHandler.GetStatus)
	mux.HandleFunc("POST /api/v1/agent/turn", hermesHandler.Turn)
	mux.HandleFunc("GET /api/v1/agent/handoffs", hermesHandler.ListHandoffs)
	mux.HandleFunc("POST /api/v1/agent/conversations/pause", hermesHandler.Pause)
	mux.HandleFunc("POST /api/v1/agent/conversations/resume", hermesHandler.Resume)
	mux.HandleFunc("POST /api/v1/agent/conversations/assign", hermesHandler.Assign)
	mux.HandleFunc("POST /api/v1/agent/conversations/resolve", hermesHandler.Resolve)
	mux.HandleFunc("GET /api/v1/agent/conversations/{id}/audit-logs", hermesHandler.GetAuditLogs)
	mux.HandleFunc("GET /api/v1/admin/catalog", catalogHandler.Admin)
	mux.HandleFunc("POST /api/v1/admin/categories", catalogHandler.CreateCategory)
	mux.HandleFunc("PATCH /api/v1/admin/categories/{id}", catalogHandler.UpdateCategory)
	mux.HandleFunc("POST /api/v1/admin/menus", catalogHandler.CreateMenu)
	mux.HandleFunc("PATCH /api/v1/admin/menus/{id}", catalogHandler.UpdateMenu)
	mux.HandleFunc("PATCH /api/v1/admin/menus/{id}/availability", catalogHandler.Availability)
	mux.HandleFunc("PATCH /api/v1/admin/modifier-options/{id}/availability", catalogHandler.OptionAvailability)
	mux.HandleFunc("POST /api/v1/admin/menu-images", catalogHandler.UploadImage)
	mux.HandleFunc("POST /api/v1/admin/cashiers/invitations", superadminHandler.InviteCashier)
	mux.HandleFunc("PUT /api/v1/admin/cashiers/{id}/branch", superadminHandler.UpdateCashierBranch)
	mux.HandleFunc("GET /api/v1/admin/employees", superadminHandler.ListEmployees)
	mux.HandleFunc("POST /api/v1/admin/employees", superadminHandler.CreateEmployee)
	mux.HandleFunc("PATCH /api/v1/admin/employees/{id}", superadminHandler.UpdateEmployee)
	mux.HandleFunc("DELETE /api/v1/admin/employees/{id}", superadminHandler.DeleteEmployee)
	mux.HandleFunc("GET /api/v1/admin/discounts", discountHandler.List)
	mux.HandleFunc("GET /api/v1/admin/discounts/applicable", discountHandler.Applicable)
	mux.HandleFunc("POST /api/v1/admin/discounts", discountHandler.Create)
	mux.HandleFunc("GET /api/v1/admin/discounts/{id}", discountHandler.GetByID)
	mux.HandleFunc("PUT /api/v1/admin/discounts/{id}", discountHandler.Update)
	mux.HandleFunc("PATCH /api/v1/admin/discounts/{id}/toggle", discountHandler.ToggleActive)
	mux.HandleFunc("DELETE /api/v1/admin/discounts/{id}", discountHandler.Delete)
	mux.HandleFunc("GET /api/v1/contacts", contactHandler.List)
	mux.HandleFunc("POST /api/v1/contacts", contactHandler.Upsert)
	mux.HandleFunc("POST /api/v1/contacts/{id}/toggle-reply", contactHandler.ToggleReply)
	mux.HandleFunc("POST /api/v1/contacts/{id}/mark-non-customer", contactHandler.MarkNonCustomer)
	mux.HandleFunc("GET /api/v1/agent/evaluations", evaluationHandler.List)
	mux.HandleFunc("POST /api/v1/agent/evaluations/{id}/review", evaluationHandler.SubmitReview)
	mux.HandleFunc("GET /api/v1/agent/evaluations/export", evaluationHandler.Export)
	mux.HandleFunc("GET /api/v1/orders", orders.List)
	mux.HandleFunc("GET /api/v1/orders/queue", orders.Queue)
	mux.HandleFunc("GET /api/v1/orders/{id}", orders.GetByID)
	mux.HandleFunc("GET /api/v1/orders/{id}/audit-logs", orders.GetAuditLogs)
	mux.HandleFunc("GET /api/v1/ws/orders", orders.WS)
	mux.HandleFunc("POST /api/v1/orders", orders.CreateManual)
	mux.HandleFunc("POST /api/v1/orders/{id}/status-transitions", orders.TransitionStatus)
	mux.HandleFunc("POST /api/v1/orders/{id}/payments/cash", payments.RecordCash)
	mux.HandleFunc("POST /api/v1/orders/{id}/payments/qris", payments.CreateQRIS)
	mux.HandleFunc("POST /api/v1/payments/{id}/reconcile", payments.Reconcile)
	mux.HandleFunc("POST /api/v1/superadmin/login", superadminHandler.Login)
	mux.HandleFunc("GET /api/v1/superadmin/health/snapshot", superadminHandler.HealthSnapshot)
	mux.HandleFunc("GET /api/v1/superadmin/telemetry/traffic", superadminHandler.TrafficTelemetry)
	mux.HandleFunc("GET /api/v1/superadmin/users", superadminHandler.ListUsers)
	mux.HandleFunc("GET /api/v1/superadmin/users/{id}/whatsapp", superadminHandler.UserWhatsAppStatus)
	mux.HandleFunc("GET /api/v1/superadmin/whatsapp/status", superadminHandler.WhatsAppOverview)
	mux.HandleFunc("GET /api/v1/superadmin/users/invitations", superadminHandler.ListInvitations)
	mux.HandleFunc("POST /api/v1/superadmin/users/invite", superadminHandler.Invite)
	mux.HandleFunc("DELETE /api/v1/superadmin/users/invitations/{id}", superadminHandler.RevokeInvitation)
	mux.HandleFunc("POST /api/v1/superadmin/users/{id}/approve", superadminHandler.Approve)
	mux.HandleFunc("POST /api/v1/superadmin/users/{id}/reject", superadminHandler.Reject)
	mux.HandleFunc("POST /api/v1/superadmin/users/{id}/suspend", superadminHandler.Suspend)
	mux.HandleFunc("POST /api/v1/superadmin/users/{id}/reactivate", superadminHandler.Reactivate)
	mux.HandleFunc("POST /api/v1/superadmin/users/{id}/revoke-sessions", superadminHandler.RevokeSessions)
	mux.HandleFunc("GET /api/v1/superadmin/audits", superadminHandler.ListAudits)
	mux.Handle("GET /", http.FileServer(http.Dir("web")))
	authenticatedMux := customer.Authenticate(cfg.Auth.StaffToken, cfg.Auth.KDSToken, sessions, branch.Middleware(branchService)(mux))
	server := &http.Server{Addr: cfg.Address(), Handler: httpserver.Middleware(logger, authenticatedMux), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second}
	go func() {
		logger.Info("API listening", "address", server.Addr, "environment", cfg.App.Env)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("HTTP server failed", "error", err)
			stop()
		}
	}()
	<-ctx.Done()
	shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdown); err != nil {
		logger.Error("graceful shutdown failed", "error", err)
	}
	logger.Info("API stopped")
}
