package config

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	App         App
	Database    Database
	GOWA        GOWA
	Midtrans    Midtrans
	Auth        Auth
	InviteEmail InviteEmail
	Hermes      Hermes
}

type App struct{ Name, Env, Host, Port, Timezone string }
type Database struct{ Host, Port, Name, User, Password, TLS string }
type GOWA struct {
	BaseURL, Username, Password, DeviceID, WebhookSecret string
	Timeout                                              time.Duration
}
type Midtrans struct {
	BaseURL, ServerKey, MerchantID string
	Timeout                        time.Duration
}
type Auth struct {
	StaffToken, KDSToken string
	GoogleClientID       string
	SessionSecret        string
	SessionTTL           time.Duration
	SuperadminUsername   string
	SuperadminPassword   string
}
type InviteEmail struct {
	Enabled     bool
	Username    string
	AppPassword string
	FromName    string
	LoginURL    string
}
type Hermes struct {
	BaseURL             string
	Model               string
	APIKey              string
	ToolAPIKey          string
	Timeout             time.Duration
	ConfidenceThreshold float64
	MaxAttempts         int
}

func Load() (Config, error) {
	c := Config{
		App:      App{get("APP_NAME", "PesenHub"), get("APP_ENV", "development"), get("APP_HOST", "0.0.0.0"), get("APP_PORT", "8080"), get("APP_TIMEZONE", "Asia/Jakarta")},
		Database: Database{os.Getenv("DATABASE_HOST"), get("DATABASE_PORT", "3306"), os.Getenv("DATABASE_NAME"), os.Getenv("DATABASE_USER"), os.Getenv("DATABASE_PASSWORD"), get("DATABASE_TLS", "false")},
		GOWA:     GOWA{BaseURL: os.Getenv("GOWA_BASE_URL"), Username: os.Getenv("GOWA_BASIC_AUTH_USERNAME"), Password: os.Getenv("GOWA_BASIC_AUTH_PASSWORD"), DeviceID: get("GOWA_DEVICE_ID", "pesenhub-dev"), WebhookSecret: os.Getenv("GOWA_WEBHOOK_SECRET")},
		Midtrans: Midtrans{BaseURL: get("MIDTRANS_BASE_URL", "https://api.sandbox.midtrans.com"), ServerKey: os.Getenv("MIDTRANS_SERVER_KEY"), MerchantID: os.Getenv("MIDTRANS_MERCHANT_ID")},
		Auth: Auth{
			StaffToken: os.Getenv("APP_STAFF_TOKEN"), KDSToken: os.Getenv("APP_KDS_TOKEN"),
			GoogleClientID:     os.Getenv("GOOGLE_OAUTH_CLIENT_ID"),
			SessionSecret:      os.Getenv("APP_SESSION_SECRET"),
			SuperadminUsername: get("SUPERADMIN_USERNAME", "superadmin"),
			SuperadminPassword: get("SUPERADMIN_PASSWORD", "superadmin"),
		},
		InviteEmail: InviteEmail{
			Username: os.Getenv("GMAIL_SMTP_USERNAME"), AppPassword: os.Getenv("GMAIL_SMTP_APP_PASSWORD"),
			FromName: get("INVITE_EMAIL_FROM_NAME", "PesenHub"), LoginURL: os.Getenv("INVITE_LOGIN_URL"),
		},
		Hermes: Hermes{
			BaseURL:             get("HERMES_AGENT_BASE_URL", "http://host.docker.internal:8642/v1"),
			Model:               get("HERMES_AGENT_MODEL", "hermes-agent"),
			APIKey:              os.Getenv("HERMES_AGENT_API_KEY"),
			ToolAPIKey:          os.Getenv("HERMES_TOOL_API_KEY"),
			ConfidenceThreshold: 0.75,
			MaxAttempts:         3,
		},
	}
	var err error
	c.InviteEmail.Enabled, err = strconv.ParseBool(get("INVITE_EMAIL_ENABLED", "false"))
	if err != nil {
		return Config{}, errors.New("INVITE_EMAIL_ENABLED must be true or false")
	}
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
	c.Hermes.Timeout, err = time.ParseDuration(get("HERMES_AGENT_TIMEOUT", "60s"))
	if err != nil || c.Hermes.Timeout <= 0 {
		return Config{}, errors.New("HERMES_AGENT_TIMEOUT must be a positive duration")
	}
	if v := os.Getenv("HERMES_CONFIDENCE_THRESHOLD"); v != "" {
		if threshold, err := strconv.ParseFloat(v, 64); err == nil && threshold > 0 && threshold <= 1.0 {
			c.Hermes.ConfidenceThreshold = threshold
		}
	}
	if v := os.Getenv("HERMES_MAX_ATTEMPTS"); v != "" {
		if attempts, err := strconv.Atoi(v); err == nil && attempts > 0 {
			c.Hermes.MaxAttempts = attempts
		}
	}
	missing := []string{}
	for k, v := range map[string]string{"DATABASE_HOST": c.Database.Host, "DATABASE_NAME": c.Database.Name, "DATABASE_USER": c.Database.User, "DATABASE_PASSWORD": c.Database.Password, "GOWA_BASE_URL": c.GOWA.BaseURL, "GOWA_BASIC_AUTH_USERNAME": c.GOWA.Username, "GOWA_BASIC_AUTH_PASSWORD": c.GOWA.Password, "GOWA_DEVICE_ID": c.GOWA.DeviceID, "GOWA_WEBHOOK_SECRET": c.GOWA.WebhookSecret, "MIDTRANS_SERVER_KEY": c.Midtrans.ServerKey, "MIDTRANS_MERCHANT_ID": c.Midtrans.MerchantID, "APP_STAFF_TOKEN": c.Auth.StaffToken, "APP_KDS_TOKEN": c.Auth.KDSToken, "GOOGLE_OAUTH_CLIENT_ID": c.Auth.GoogleClientID, "APP_SESSION_SECRET": c.Auth.SessionSecret} {
		if strings.TrimSpace(v) == "" {
			missing = append(missing, k)
		}
	}
	if len(missing) > 0 {
		return Config{}, fmt.Errorf("missing required environment configuration: %s", strings.Join(missing, ", "))
	}
	if c.App.Env != "test" && (strings.TrimSpace(c.Hermes.APIKey) == "" || strings.TrimSpace(c.Hermes.ToolAPIKey) == "") {
		return Config{}, errors.New("HERMES_AGENT_API_KEY and HERMES_TOOL_API_KEY are required")
	}
	if c.App.Env != "test" && (len(c.Hermes.APIKey) < 32 || len(c.Hermes.ToolAPIKey) < 32 || c.Hermes.APIKey == c.Hermes.ToolAPIKey) {
		return Config{}, errors.New("Hermes agent and tool API keys must be distinct and contain at least 32 characters")
	}
	if len(c.GOWA.WebhookSecret) < 32 {
		return Config{}, errors.New("GOWA_WEBHOOK_SECRET must contain at least 32 characters")
	}
	if len(c.Auth.StaffToken) < 32 || len(c.Auth.KDSToken) < 32 || c.Auth.StaffToken == c.Auth.KDSToken {
		return Config{}, errors.New("APP_STAFF_TOKEN and APP_KDS_TOKEN must be distinct and contain at least 32 characters")
	}
	if len(c.Auth.SessionSecret) < 32 {
		return Config{}, errors.New("APP_SESSION_SECRET must contain at least 32 characters")
	}
	if c.InviteEmail.Enabled {
		if strings.TrimSpace(c.InviteEmail.Username) == "" || strings.TrimSpace(c.InviteEmail.AppPassword) == "" || strings.TrimSpace(c.InviteEmail.LoginURL) == "" {
			return Config{}, errors.New("GMAIL_SMTP_USERNAME, GMAIL_SMTP_APP_PASSWORD, and INVITE_LOGIN_URL are required when invitation email is enabled")
		}
		if strings.ContainsAny(c.InviteEmail.Username+c.InviteEmail.FromName, "\r\n") {
			return Config{}, errors.New("invitation email sender configuration is invalid")
		}
		loginURL, parseErr := url.ParseRequestURI(c.InviteEmail.LoginURL)
		if parseErr != nil || loginURL.Host == "" || (c.App.Env != "development" && c.App.Env != "test" && loginURL.Scheme != "https") {
			return Config{}, errors.New("INVITE_LOGIN_URL must be a valid HTTPS URL outside development")
		}
	}
	if _, err := url.ParseRequestURI(c.GOWA.BaseURL); err != nil {
		return Config{}, errors.New("GOWA_BASE_URL must be a valid URL")
	}
	if parsed, err := url.ParseRequestURI(c.Midtrans.BaseURL); err != nil || parsed.Host == "" || (c.App.Env != "test" && (parsed.Scheme != "https" || parsed.Hostname() != "api.sandbox.midtrans.com")) {
		return Config{}, errors.New("MIDTRANS_BASE_URL must be the sandbox HTTPS URL")
	}
	if parsed, err := url.ParseRequestURI(c.Hermes.BaseURL); err != nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return Config{}, errors.New("HERMES_AGENT_BASE_URL must be a valid HTTP URL")
	}
	if _, err := time.LoadLocation(c.App.Timezone); err != nil {
		return Config{}, errors.New("APP_TIMEZONE must be a valid timezone")
	}
	return c, nil
}

func (c Config) Address() string { return net.JoinHostPort(c.App.Host, c.App.Port) }
func (d Database) DSN() string {
	return fmt.Sprintf("mysql://%s:%s@tcp(%s)/%s?parseTime=true&loc=UTC&multiStatements=true&tls=%s&charset=utf8mb4&collation=utf8mb4_0900_ai_ci", d.User, d.Password, net.JoinHostPort(d.Host, d.Port), d.Name, url.QueryEscape(d.TLS))
}
func get(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
