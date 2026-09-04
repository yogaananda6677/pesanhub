package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"pesenhub/backend/internal/config"
)

func main() {
	if len(os.Args) != 2 || (os.Args[1] != "up" && os.Args[1] != "down" && os.Args[1] != "status") {
		fmt.Fprintln(os.Stderr, "usage: pesenhub-migrate [up|down|status]")
		os.Exit(2)
	}
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintln(os.Stderr, "invalid configuration:", err)
		os.Exit(1)
	}
	m, err := migrate.New("file://migrations", cfg.Database.DSN())
	if err != nil {
		fmt.Fprintln(os.Stderr, "initialize migration failed:", err)
		os.Exit(1)
	}
	if os.Args[1] == "status" {
		version, dirty, versionErr := m.Version()
		if errors.Is(versionErr, migrate.ErrNilVersion) {
			fmt.Println("migration status: no migration applied")
			return
		}
		if versionErr != nil {
			fmt.Fprintln(os.Stderr, "read migration status failed")
			os.Exit(1)
		}
		fmt.Printf("migration status: version=%d dirty=%t\n", version, dirty)
		return
	}
	if os.Args[1] == "up" {
		err = m.Up()
	} else {
		err = m.Steps(-1)
	}
	if err != nil && !errors.Is(err, migrate.ErrNoChange) {
		fmt.Fprintln(os.Stderr, "migration failed")
		os.Exit(1)
	}
	fmt.Println("migration", os.Args[1], "complete")
}
