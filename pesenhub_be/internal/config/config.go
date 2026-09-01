package config

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"strings"
	"time"
)

type Config struct {
	App      App
	Database Database
	WAHA     WAHA
}

type App struct{ Name, Env, Host, Port, Timezone string }
type Database struct{ Host, Port, Name, User, Password, SSLMode string }
type WAHA struct {
	BaseURL, APIKey, Session string
	Timeout                  time.Duration
}

func Load() (Config, error) {
	c := Config{
		App:      App{get("APP_NAME", "PesenHub"), get("APP_ENV", "development"), get("APP_HOST", "0.0.0.0"), get("APP_PORT", "8080"), get("APP_TIMEZONE", "Asia/Jakarta")},
		Database: Database{os.Getenv("DATABASE_HOST"), get("DATABASE_PORT", "5432"), os.Getenv("DATABASE_NAME"), os.Getenv("DATABASE_USER"), os.Getenv("DATABASE_PASSWORD"), get("DATABASE_SSLMODE", "disable")},
		WAHA:     WAHA{BaseURL: os.Getenv("WAHA_BASE_URL"), APIKey: os.Getenv("WAHA_API_KEY"), Session: get("WAHA_SESSION", "default")},
	}
	var err error
	c.WAHA.Timeout, err = time.ParseDuration(get("WAHA_REQUEST_TIMEOUT", "3s"))
	if err != nil || c.WAHA.Timeout <= 0 {
		return Config{}, errors.New("WAHA_REQUEST_TIMEOUT must be a positive duration")
	}
	missing := []string{}
	for k, v := range map[string]string{"DATABASE_HOST": c.Database.Host, "DATABASE_NAME": c.Database.Name, "DATABASE_USER": c.Database.User, "DATABASE_PASSWORD": c.Database.Password, "WAHA_BASE_URL": c.WAHA.BaseURL, "WAHA_API_KEY": c.WAHA.APIKey} {
		if strings.TrimSpace(v) == "" {
			missing = append(missing, k)
		}
	}
	if len(missing) > 0 {
		return Config{}, fmt.Errorf("missing required environment configuration: %s", strings.Join(missing, ", "))
	}
	if _, err := url.ParseRequestURI(c.WAHA.BaseURL); err != nil {
		return Config{}, errors.New("WAHA_BASE_URL must be a valid URL")
	}
	if _, err := time.LoadLocation(c.App.Timezone); err != nil {
		return Config{}, errors.New("APP_TIMEZONE must be a valid timezone")
	}
	return c, nil
}

func (c Config) Address() string { return net.JoinHostPort(c.App.Host, c.App.Port) }
func (d Database) DSN() string {
	return fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=%s", url.QueryEscape(d.User), url.QueryEscape(d.Password), d.Host, d.Port, d.Name, url.QueryEscape(d.SSLMode))
}
func get(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
