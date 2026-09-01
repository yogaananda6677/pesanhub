package config

import (
	"strings"
	"testing"
)

func validEnv(t *testing.T) {
	t.Helper()
	for k, v := range map[string]string{"DATABASE_HOST": "localhost", "DATABASE_NAME": "pesenhub", "DATABASE_USER": "user", "DATABASE_PASSWORD": "secret-value", "WAHA_BASE_URL": "http://localhost:3000", "WAHA_API_KEY": "api-secret"} {
		t.Setenv(k, v)
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
