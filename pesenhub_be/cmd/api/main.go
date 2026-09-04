package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/config"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/database"
	"pesenhub/backend/internal/health"
	"pesenhub/backend/internal/hermes"
	"pesenhub/backend/internal/httpserver"
	"pesenhub/backend/internal/notification"
	orderapi "pesenhub/backend/internal/order"
	"pesenhub/backend/internal/waha"
	"pesenhub/backend/internal/ws"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg, err := config.Load()
	if err != nil {
		logger.Error("configuration loading failed", "error", "invalid configuration")
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	pool, err := database.Open(ctx, cfg.Database.DSN())
	if err != nil {
		logger.Error("database connection failed", "error", "database unavailable")
		os.Exit(1)
	}
	defer pool.Close()
	wc := waha.New(cfg.WAHA.BaseURL, cfg.WAHA.APIKey, cfg.WAHA.Session, cfg.WAHA.Timeout)
	wahaStore := waha.NewStore(pool)
	wahaWebhook := waha.NewWebhookHandler(cfg.WAHA.WebhookHMACKey, logger, waha.WithStore(wahaStore))
	h := health.New("pesenhub-api", pool, wc)
	customers := customer.NewHandler(customer.NewService(customer.NewStore(pool), customer.NewID))
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
	notifService := notification.NewService(notification.Config{
		Store:  notifStore,
		Sender: wc,
		Logger: logger,
	})
	notifDispatcher := orderapi.NewNotificationDispatcher(orderStore, notifService, logger)
	orderService.SetNotificationDispatcher(notifDispatcher)
	orders := orderapi.NewHandler(orderService, orderHub)

	hermesStore := hermes.NewStore(pool)
	hermesConvStore := hermes.NewPGConversationStore(pool)
	hermesService := hermes.NewService(hermes.Config{
		Client:            &hermes.MockLLMClient{},
		CatalogProvider:   catalogService,
		OrderCreator:      orderService,
		Store:             hermesStore,
		ConversationStore: hermesConvStore,
	})
	hermesHandler := hermes.NewHandler(hermesService)
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health/live", h.Live)
	mux.HandleFunc("GET /health/ready", h.Ready)
	mux.Handle("POST /webhooks/waha", wahaWebhook)
	mux.HandleFunc("POST /api/v1/customers", customers.Create)
	mux.HandleFunc("PATCH /api/v1/customers/{id}", customers.Update)
	mux.HandleFunc("GET /api/v1/customers/{id}/orders", customers.History)
	mux.HandleFunc("GET /api/v1/public/menu", catalogHandler.Public)
	mux.HandleFunc("POST /api/v1/public/orders/preview", orders.PreviewWeb)
	mux.HandleFunc("POST /api/v1/public/orders", orders.CreateWeb)
	mux.HandleFunc("GET /api/v1/public/orders/{token}", orders.GetByPublicToken)
	mux.HandleFunc("GET /api/v1/agent/menu", catalogHandler.Public)
	mux.HandleFunc("GET /api/v1/agent/handoffs", hermesHandler.ListHandoffs)
	mux.HandleFunc("POST /api/v1/agent/conversations/pause", hermesHandler.Pause)
	mux.HandleFunc("POST /api/v1/agent/conversations/resume", hermesHandler.Resume)
	mux.HandleFunc("POST /api/v1/agent/conversations/assign", hermesHandler.Assign)
	mux.HandleFunc("POST /api/v1/agent/conversations/resolve", hermesHandler.Resolve)
	mux.HandleFunc("GET /api/v1/agent/conversations/{id}/audit-logs", hermesHandler.GetAuditLogs)
	mux.HandleFunc("POST /api/v1/admin/categories", catalogHandler.CreateCategory)
	mux.HandleFunc("POST /api/v1/admin/menus", catalogHandler.CreateMenu)
	mux.HandleFunc("PATCH /api/v1/admin/menus/{id}/availability", catalogHandler.Availability)
	mux.HandleFunc("GET /api/v1/orders", orders.List)
	mux.HandleFunc("GET /api/v1/orders/queue", orders.Queue)
	mux.HandleFunc("GET /api/v1/orders/{id}", orders.GetByID)
	mux.HandleFunc("GET /api/v1/orders/{id}/audit-logs", orders.GetAuditLogs)
	mux.HandleFunc("GET /api/v1/ws/orders", orders.WS)
	mux.HandleFunc("POST /api/v1/orders", orders.CreateManual)
	mux.HandleFunc("POST /api/v1/orders/{id}/status-transitions", orders.TransitionStatus)
	mux.Handle("GET /", http.FileServer(http.Dir("web")))
	server := &http.Server{Addr: cfg.Address(), Handler: httpserver.Middleware(logger, mux), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second}
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
