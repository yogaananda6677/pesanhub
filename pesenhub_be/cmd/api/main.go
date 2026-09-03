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
	"pesenhub/backend/internal/httpserver"
	orderapi "pesenhub/backend/internal/order"
	"pesenhub/backend/internal/waha"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg, err := config.Load()
	if err != nil {
		logger.Error("invalid configuration", "error", err)
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
	h := health.New("pesenhub-api", pool, wc)
	customers := customer.NewHandler(customer.NewService(customer.NewStore(pool), customer.NewID))
	catalogHandler := catalog.NewHandler(catalog.NewService(catalog.NewStore(pool), customer.NewID))
	orders := orderapi.NewHandler(orderapi.NewService(orderapi.NewStore(pool)))
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health/live", h.Live)
	mux.HandleFunc("GET /health/ready", h.Ready)
	mux.HandleFunc("POST /api/v1/customers", customers.Create)
	mux.HandleFunc("PATCH /api/v1/customers/{id}", customers.Update)
	mux.HandleFunc("GET /api/v1/customers/{id}/orders", customers.History)
	mux.HandleFunc("GET /api/v1/public/menu", catalogHandler.Public)
	mux.HandleFunc("GET /api/v1/agent/menu", catalogHandler.Public)
	mux.HandleFunc("POST /api/v1/admin/categories", catalogHandler.CreateCategory)
	mux.HandleFunc("POST /api/v1/admin/menus", catalogHandler.CreateMenu)
	mux.HandleFunc("PATCH /api/v1/admin/menus/{id}/availability", catalogHandler.Availability)
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
