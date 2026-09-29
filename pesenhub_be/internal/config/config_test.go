package config

import (
	"strings"
	"testing"
)

func validEnv(t *testing.T) {
	t.Helper()
	for k, v := range map[string]string{"APP_ENV": "development", "DATABASE_HOST": "localhost", "DATABASE_NAME": "pesenhub", "DATABASE_USER": "user", "DATABASE_PASSWORD": "secret-value", "GOWA_BASE_URL": "http://localhost:3000", "GOWA_BASIC_AUTH_USERNAME": "pesenhub", "GOWA_BASIC_AUTH_PASSWORD": "api-secret", "GOWA_DEVICE_ID": "pesenhub-dev", "GOWA_WEBHOOK_SECRET": "webhook-secret-at-least-32-characters", "MIDTRANS_SERVER_KEY": "SB-Mid-server-dummy", "MIDTRANS_MERCHANT_ID": "G123456789", "MIDTRANS_BASE_URL": "https://api.sandbox.midtrans.com", "APP_STAFF_TOKEN": "staff-test-token-at-least-32-characters", "APP_KDS_TOKEN": "kds-test-token-at-least-32-charactersxx", "APP_LOGIN_USERNAME": "outlet", "APP_LOGIN_PASSWORD_HASH": "$2b$12$Hh3DcQ1Vtgt8PCVFA2oG3uLZ5nhlXvGDk90Rq.8hLr.4poYps/5tK", "GOOGLE_OAUTH_CLIENT_ID": "google-web-client.apps.googleusercontent.com", "APP_SESSION_SECRET": "session-test-secret-at-least-32-characters", "APP_SESSION_TTL": "8h", "HERMES_AGENT_API_KEY": "hermes-agent-test-key-at-least-32-characters", "HERMES_TOOL_API_KEY": "hermes-tool-test-key-at-least-32-charactersx"} {
		t.Setenv(k, v)
	}
}

func TestLoadRejectsWeakOrSharedAppTokensWithoutLeaking(t *testing.T) {
	validEnv(t)
	t.Setenv("APP_STAFF_TOKEN", "shared-sensitive-token-at-least-32-chars")
	t.Setenv("APP_KDS_TOKEN", "shared-sensitive-token-at-least-32-chars")
	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "distinct") || strings.Contains(err.Error(), "shared-sensitive") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestLoadRejectsWeakWebhookSecretWithoutLeakingIt(t *testing.T) {
	validEnv(t)
	t.Setenv("GOWA_WEBHOOK_SECRET", "too-short-secret")
	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "at least 32") {
		t.Fatalf("unexpected error: %v", err)
	}
	if strings.Contains(err.Error(), "too-short-secret") {
		t.Fatal("secret leaked")
	}
}

func TestLoadValid(t *testing.T) {
	validEnv(t)
	c, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if c.App.Port != "8080" {
		t.Fatalf("port = %q", c.App.Port)
	}
}

func TestLoadReportsMissingWithoutValues(t *testing.T) {
	validEnv(t)
	t.Setenv("DATABASE_PASSWORD", "")
	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "DATABASE_PASSWORD") {
		t.Fatalf("unexpected error: %v", err)
	}
	if strings.Contains(err.Error(), "secret-value") {
		t.Fatal("secret leaked")
	}
}

func TestLoadRejectsNonSandboxMidtransEndpoint(t *testing.T) {
	validEnv(t)
	t.Setenv("MIDTRANS_BASE_URL", "https://api.midtrans.com")
	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "MIDTRANS_BASE_URL") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestLoadDoesNotLeakMidtransServerKey(t *testing.T) {
	validEnv(t)
	t.Setenv("MIDTRANS_SERVER_KEY", "sensitive-midtrans-key")
	t.Setenv("MIDTRANS_REQUEST_TIMEOUT", "invalid")
	_, err := Load()
	if err == nil || strings.Contains(err.Error(), "sensitive-midtrans-key") {
		t.Fatalf("unsafe error: %v", err)
	}
}

func TestLoadRequiresMidtransMerchantID(t *testing.T) {
	validEnv(t)
	t.Setenv("MIDTRANS_MERCHANT_ID", "")
	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "MIDTRANS_MERCHANT_ID") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestLoadRejectsUnsafeLoginSessionConfiguration(t *testing.T) {
	tests := []struct{ key, value, message string }{
		{"APP_SESSION_SECRET", "too-short", "32 characters"},
		{"APP_SESSION_TTL", "25h", "24h"},
	}
	for _, tt := range tests {
		t.Run(tt.key, func(t *testing.T) {
			validEnv(t)
			t.Setenv(tt.key, tt.value)
			_, err := Load()
			if err == nil || !strings.Contains(err.Error(), tt.message) || strings.Contains(err.Error(), tt.value) {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestLoadHermesConfiguration(t *testing.T) {
	validEnv(t)
	t.Setenv("HERMES_AGENT_BASE_URL", "http://127.0.0.1:8642/v1")
	t.Setenv("HERMES_AGENT_MODEL", "hermes-agent")
	t.Setenv("HERMES_AGENT_API_KEY", "test-agent-key-at-least-32-characters")
	t.Setenv("HERMES_TOOL_API_KEY", "test-tool-key-at-least-32-charactersx")
	t.Setenv("HERMES_AGENT_TIMEOUT", "45s")
	t.Setenv("HERMES_CONFIDENCE_THRESHOLD", "0.85")
	t.Setenv("HERMES_MAX_ATTEMPTS", "5")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if cfg.Hermes.BaseURL != "http://127.0.0.1:8642/v1" {
		t.Errorf("expected Hermes Agent base URL, got %s", cfg.Hermes.BaseURL)
	}
	if cfg.Hermes.Model != "hermes-agent" {
		t.Errorf("expected model hermes-agent, got %s", cfg.Hermes.Model)
	}
	if cfg.Hermes.APIKey != "test-agent-key-at-least-32-characters" || cfg.Hermes.ToolAPIKey != "test-tool-key-at-least-32-charactersx" {
		t.Errorf("unexpected Hermes API key configuration")
	}
	if cfg.Hermes.ConfidenceThreshold != 0.85 {
		t.Errorf("expected threshold 0.85, got %f", cfg.Hermes.ConfidenceThreshold)
	}
	if cfg.Hermes.MaxAttempts != 5 {
		t.Errorf("expected max attempts 5, got %d", cfg.Hermes.MaxAttempts)
	}
}

func TestLoadInvitationEmailConfiguration(t *testing.T) {
	validEnv(t)
	t.Setenv("INVITE_EMAIL_ENABLED", "true")
	t.Setenv("GMAIL_SMTP_USERNAME", "sender@gmail.com")
	t.Setenv("GMAIL_SMTP_APP_PASSWORD", "sixteen-char-app-password")
	t.Setenv("INVITE_EMAIL_FROM_NAME", "PesenHub Test")
	t.Setenv("INVITE_LOGIN_URL", "https://app.example.test/login")

	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.InviteEmail.Enabled || cfg.InviteEmail.Username != "sender@gmail.com" {
		t.Fatalf("unexpected invitation email config: %#v", cfg.InviteEmail)
	}
}

func TestLoadRequiresInvitationEmailSecretsOnlyWhenEnabled(t *testing.T) {
	validEnv(t)
	t.Setenv("INVITE_EMAIL_ENABLED", "true")
	t.Setenv("GMAIL_SMTP_USERNAME", "")
	t.Setenv("GMAIL_SMTP_APP_PASSWORD", "")
	t.Setenv("INVITE_LOGIN_URL", "")
	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), "GMAIL_SMTP_USERNAME") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestLoadSuperadminConfiguration(t *testing.T) {
	validEnv(t)
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Auth.SuperadminUsername != "superadmin" || cfg.Auth.SuperadminPassword != "superadmin" {
		t.Fatalf("expected default superadmin credentials, got username=%q password=%q", cfg.Auth.SuperadminUsername, cfg.Auth.SuperadminPassword)
	}

	t.Setenv("SUPERADMIN_USERNAME", "custom_admin")
	t.Setenv("SUPERADMIN_PASSWORD", "custom_secret_123")
	cfgCustom, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfgCustom.Auth.SuperadminUsername != "custom_admin" || cfgCustom.Auth.SuperadminPassword != "custom_secret_123" {
		t.Fatalf("expected custom superadmin credentials, got username=%q password=%q", cfgCustom.Auth.SuperadminUsername, cfgCustom.Auth.SuperadminPassword)
	}
}
