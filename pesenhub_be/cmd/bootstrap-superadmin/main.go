package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	"pesenhub/backend/internal/appauth"
	"pesenhub/backend/internal/config"
	"pesenhub/backend/internal/database"
)

func main() {
	email := flag.String("email", "", "Google email to pre-authorize as Superadmin")
	displayName := flag.String("display-name", "Superadmin", "display name stored for the account")
	flag.Parse()
	if *email == "" || flag.NArg() != 0 {
		fmt.Fprintln(os.Stderr, "usage: bootstrap-superadmin --email <google-email> [--display-name <name>]")
		os.Exit(2)
	}
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintln(os.Stderr, "invalid configuration")
		os.Exit(1)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pool, err := database.Open(ctx, cfg.Database.DSN())
	if err != nil {
		fmt.Fprintln(os.Stderr, "database unavailable")
		os.Exit(1)
	}
	defer pool.Close()
	user, created, err := appauth.NewStore(pool).ProvisionSuperadmin(ctx, *email, *displayName, "controlled-bootstrap")
	if err != nil {
		fmt.Fprintln(os.Stderr, "Superadmin bootstrap failed")
		os.Exit(1)
	}
	if created {
		fmt.Println("Superadmin pre-authorization created")
	} else {
		fmt.Println("Superadmin pre-authorization already exists")
	}

	sessionMgr, err := appauth.NewSessionManager(cfg.Auth.SessionSecret, cfg.Auth.SessionTTL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "session manager init failed: %v\n", err)
		os.Exit(1)
	}
	token, sessionID, expiresAt, err := sessionMgr.IssuePersistent(user.ID, string(appauth.RoleSuperadmin))
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to issue session: %v\n", err)
		os.Exit(1)
	}
	if err := appauth.NewStore(pool).CreateSession(ctx, sessionID, user.ID, expiresAt); err != nil {
		fmt.Fprintf(os.Stderr, "failed to store session: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("\nToken Sesi Superadmin (berlaku %s):\n%s\n", cfg.Auth.SessionTTL, token)
}
