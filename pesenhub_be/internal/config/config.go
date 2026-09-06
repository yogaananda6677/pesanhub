package config

import (
	"encoding/base64"
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
)

type Config struct {
	App      App
	Database Database
	GOWA     GOWA
	Midtrans Midtrans
	Auth     Auth
}

type App struct{ Name, Env, Host, Port, Timezone string }
type Database struct{ Host, Port, Name, User, Password, SSLMode string }
type GOWA struct {
	BaseURL, Username, Password, DeviceID, WebhookSecret string
	Timeout                                              time.Duration
}
type Midtrans struct {
	BaseURL, ServerKey, MerchantID string
	Timeout                        time.Duration
}
type Auth struct {
	StaffToken, KDSToken             string
	LoginUsername, LoginPasswordHash string
	SessionSecret                    string
	SessionTTL                       time.Duration
}

func Load() (Config, error) {
	c := Config{
		App:      App{get("APP_NAME", "PesenHub"), get("APP_ENV", "development"), get("APP_HOST", "0.0.0.0"), get("APP_PORT", "8080"), get("APP_TIMEZONE", "Asia/Jakarta")},
		Database: Database{os.Getenv("DATABASE_HOST"), get("DATABASE_PORT", "5432"), os.Getenv("DATABASE_NAME"), os.Getenv("DATABASE_USER"), os.Getenv("DATABASE_PASSWORD"), get("DATABASE_SSLMODE", "disable")},
		GOWA:     GOWA{BaseURL: os.Getenv("GOWA_BASE_URL"), Username: os.Getenv("GOWA_BASIC_AUTH_USERNAME"), Password: os.Getenv("GOWA_BASIC_AUTH_PASSWORD"), DeviceID: get("GOWA_DEVICE_ID", "pesenhub-dev"), WebhookSecret: os.Getenv("GOWA_WEBHOOK_SECRET")},
		Midtrans: Midtrans{BaseURL: get("MIDTRANS_BASE_URL", "https://api.sandbox.midtrans.com"), ServerKey: os.Getenv("MIDTRANS_SERVER_KEY"), MerchantID: os.Getenv("MIDTRANS_MERCHANT_ID")},
		Auth: Auth{
			StaffToken: os.Getenv("APP_STAFF_TOKEN"), KDSToken: os.Getenv("APP_KDS_TOKEN"),
			LoginUsername: os.Getenv("APP_LOGIN_USERNAME"), LoginPasswordHash: os.Getenv("APP_LOGIN_PASSWORD_HASH"),
			SessionSecret: os.Getenv("APP_SESSION_SECRET"),
		},
	}
	var err error
	c.GOWA.Timeout, err = time.ParseDuration(get("GOWA_REQUEST_TIMEOUT", "3s"))
	if err != nil || c.GOWA.Timeout <= 0 {
		return Config{}, errors.New("GOWA_REQUEST_TIMEOUT must be a positive duration")
	}
	c.Midtrans.Timeout, err = time.ParseDuration(get("MIDTRANS_REQUEST_TIMEOUT", "5s"))
	if err != nil || c.Midtrans.Timeout <= 0 {
		return Config{}, errors.New("MIDTRANS_REQUEST_TIMEOUT must be a positive duration")
	}
	c.Auth.SessionTTL, err = time.ParseDuration(get("APP_SESSION_TTL", "8h"))
	if err != nil || c.Auth.SessionTTL <= 0 || c.Auth.SessionTTL > 24*time.Hour {
		return Config{}, errors.New("APP_SESSION_TTL must be a positive duration no longer than 24h")
	}
	if strings.HasPrefix(c.Auth.LoginPasswordHash, "base64:") {
		decoded, decodeErr := base64.StdEncoding.DecodeString(strings.TrimPrefix(c.Auth.LoginPasswordHash, "base64:"))
		if decodeErr != nil {
			return Config{}, errors.New("APP_LOGIN_PASSWORD_HASH must contain a valid bcrypt hash")
		}
		c.Auth.LoginPasswordHash = string(decoded)
	}
	missing := []string{}
	for k, v := range map[string]string{"DATABASE_HOST": c.Database.Host, "DATABASE_NAME": c.Database.Name, "DATABASE_USER": c.Database.User, "DATABASE_PASSWORD": c.Database.Password, "GOWA_BASE_URL": c.GOWA.BaseURL, "GOWA_BASIC_AUTH_USERNAME": c.GOWA.Username, "GOWA_BASIC_AUTH_PASSWORD": c.GOWA.Password, "GOWA_DEVICE_ID": c.GOWA.DeviceID, "GOWA_WEBHOOK_SECRET": c.GOWA.WebhookSecret, "MIDTRANS_SERVER_KEY": c.Midtrans.ServerKey, "MIDTRANS_MERCHANT_ID": c.Midtrans.MerchantID, "APP_STAFF_TOKEN": c.Auth.StaffToken, "APP_KDS_TOKEN": c.Auth.KDSToken, "APP_LOGIN_USERNAME": c.Auth.LoginUsername, "APP_LOGIN_PASSWORD_HASH": c.Auth.LoginPasswordHash, "APP_SESSION_SECRET": c.Auth.SessionSecret} {
		if strings.TrimSpace(v) == "" {
			missing = append(missing, k)
		}
	}
	if len(missing) > 0 {
		return Config{}, fmt.Errorf("missing required environment configuration: %s", strings.Join(missing, ", "))
	}
	if len(c.GOWA.WebhookSecret) < 32 {
		return Config{}, errors.New("GOWA_WEBHOOK_SECRET must contain at least 32 characters")
	}
	if len(c.Auth.StaffToken) < 32 || len(c.Auth.KDSToken) < 32 || c.Auth.StaffToken == c.Auth.KDSToken {
		return Config{}, errors.New("APP_STAFF_TOKEN and APP_KDS_TOKEN must be distinct and contain at least 32 characters")
	}
	if _, err := bcrypt.Cost([]byte(c.Auth.LoginPasswordHash)); err != nil {
		return Config{}, errors.New("APP_LOGIN_PASSWORD_HASH must be a bcrypt hash")
	}
	if len(c.Auth.SessionSecret) < 32 {
		return Config{}, errors.New("APP_SESSION_SECRET must contain at least 32 characters")
	}
	if _, err := url.ParseRequestURI(c.GOWA.BaseURL); err != nil {
		return Config{}, errors.New("GOWA_BASE_URL must be a valid URL")
	}
	if parsed, err := url.ParseRequestURI(c.Midtrans.BaseURL); err != nil || parsed.Host == "" || (c.App.Env != "test" && (parsed.Scheme != "https" || parsed.Hostname() != "api.sandbox.midtrans.com")) {
		return Config{}, errors.New("MIDTRANS_BASE_URL must be the sandbox HTTPS URL")
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
