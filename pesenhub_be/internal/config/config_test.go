package config

import (
	"strings"
	"testing"
)

func validEnv(t *testing.T) {
	t.Helper()
	for k, v := range map[string]string{"APP_ENV": "development", "DATABASE_HOST": "localhost", "DATABASE_NAME": "pesenhub", "DATABASE_USER": "user", "DATABASE_PASSWORD": "secret-value", "GOWA_BASE_URL": "http://localhost:3000", "GOWA_BASIC_AUTH_USERNAME": "pesenhub", "GOWA_BASIC_AUTH_PASSWORD": "api-secret", "GOWA_DEVICE_ID": "pesenhub-dev", "GOWA_WEBHOOK_SECRET": "webhook-secret-at-least-32-characters", "MIDTRANS_SERVER_KEY": "SB-Mid-server-dummy", "MIDTRANS_MERCHANT_ID": "G123456789", "MIDTRANS_BASE_URL": "https://api.sandbox.midtrans.com", "APP_STAFF_TOKEN": "staff-test-token-at-least-32-characters", "APP_KDS_TOKEN": "kds-test-token-at-least-32-charactersxx"} {
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
