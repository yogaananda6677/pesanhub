package contractfixture

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCommittedFixtureMatchesProviderTypes(t *testing.T) {
	if err := Check("../../../contracts/backend_flutter_v1.json"); err != nil {
		t.Fatal(err)
	}
}

func TestCheckRejectsStaleFixtureWithActionableCommand(t *testing.T) {
	path := filepath.Join(t.TempDir(), "stale.json")
	if err := os.WriteFile(path, []byte("{}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	err := Check(path)
	if err == nil || !strings.Contains(err.Error(), "go run ./cmd/contractfixture -write") {
		t.Fatalf("expected actionable stale fixture failure, got %v", err)
	}
}

func TestFixtureContainsOnlySyntheticRedactedEvidence(t *testing.T) {
	data, err := Bytes()
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	for _, forbidden := range []string{"+62", "081234567890", "server_key", "authorization"} {
		if strings.Contains(strings.ToLower(text), strings.ToLower(forbidden)) {
			t.Fatalf("fixture contains forbidden value %q", forbidden)
		}
	}
	if !strings.Contains(text, "0812****7890") {
		t.Fatal("fixture must prove that customer phone is masked")
	}
}
