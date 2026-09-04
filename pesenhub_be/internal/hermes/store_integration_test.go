package hermes

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestStoreIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set; skipping PostgreSQL integration test")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	store := NewStore(db)
	now := time.Now().UTC().Truncate(time.Microsecond)
	corrID := "corr-integ-" + newID()
	errMsg := "sample error for audit"

	run := &AgentRun{
		ID:               newID(),
		Session:          "default",
		CustomerPhone:    "+6281234567890",
		Model:            "hermes-3-llama-3.1-8b",
		PromptVersion:    "v1.0.0",
		ConfidenceScore:  0.88,
		IsAmbiguous:      false,
		AmbiguityReasons: []string{},
		ExtractedDraft:   json.RawMessage(`{"subtotal_amount":35000}`),
		ToolCalls:        json.RawMessage(`[{"tool_name":"llm_extract_order","duration_ms":120}]`),
		DurationMs:       150,
		Status:           StatusSuccess,
		ErrorMessage:     &errMsg,
		CorrelationID:    corrID,
		CreatedAt:        now,
	}

	// 1. Record run
	if err := store.RecordRun(ctx, run); err != nil {
		t.Fatalf("RecordRun failed: %v", err)
	}

	// 2. Fetch by ID
	fetched, err := store.GetByID(ctx, run.ID)
	if err != nil {
		t.Fatalf("GetByID failed: %v", err)
	}
	if fetched.ID != run.ID {
		t.Errorf("expected ID %s, got %s", run.ID, fetched.ID)
	}
	if fetched.CorrelationID != corrID {
		t.Errorf("expected CorrelationID %s, got %s", corrID, fetched.CorrelationID)
	}
	if fetched.Status != StatusSuccess {
		t.Errorf("expected Status SUCCESS, got %s", fetched.Status)
	}
	if fetched.ConfidenceScore != 0.88 {
		t.Errorf("expected ConfidenceScore 0.88, got %.2f", fetched.ConfidenceScore)
	}
	if fetched.ErrorMessage == nil || *fetched.ErrorMessage != errMsg {
		t.Errorf("expected ErrorMessage %q, got %v", errMsg, fetched.ErrorMessage)
	}

	// 3. Fetch by CorrelationID
	fetchedByCorr, err := store.GetByCorrelationID(ctx, corrID)
	if err != nil {
		t.Fatalf("GetByCorrelationID failed: %v", err)
	}
	if fetchedByCorr.ID != run.ID {
		t.Errorf("expected ID %s, got %s", run.ID, fetchedByCorr.ID)
	}

	// 4. Not found case
	nonExistentID := newID()
	_, err = store.GetByID(ctx, nonExistentID)
	if !errors.Is(err, ErrRunNotFound) {
		t.Errorf("expected ErrRunNotFound, got %v", err)
	}
}
