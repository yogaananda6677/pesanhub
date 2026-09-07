package superadmin

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestSuperadminStoreIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()

	store := NewStore(pool)
	actorEmail := "superadmin-itest@pesenhub.id"
	targetEmail := "owner-itest@pesenhub.id"
	invitedEmail := "invited-itest@pesenhub.id"

	cleanup := func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM user_invitations WHERE email_normalized = ANY($1::text[])`, []string{invitedEmail, targetEmail})
		_, _ = pool.Exec(context.Background(), `DELETE FROM app_users WHERE email_normalized = ANY($1::text[])`, []string{actorEmail, targetEmail})
	}
	cleanup()
	defer cleanup()

	// 1. Setup superadmin and test target user in app_users
	var superadminID, targetUserID string
	err = pool.QueryRow(ctx, `
		INSERT INTO app_users (id, email_normalized, display_name, role, status, approved_at, created_at, updated_at)
		VALUES (gen_random_uuid(), $1, 'Super Admin', 'SUPERADMIN', 'APPROVED', now(), now(), now())
		RETURNING id::text`, actorEmail).Scan(&superadminID)
	if err != nil {
		t.Fatalf("failed to insert superadmin: %v", err)
	}

	err = pool.QueryRow(ctx, `
		INSERT INTO app_users (id, email_normalized, display_name, role, status, created_at, updated_at)
		VALUES (gen_random_uuid(), $1, 'Test Owner', 'OWNER', 'PENDING_APPROVAL', now(), now())
		RETURNING id::text`, targetEmail).Scan(&targetUserID)
	if err != nil {
		t.Fatalf("failed to insert target user: %v", err)
	}

	// 2. Test CreateInvitation & ListInvitations & RevokeInvitation
	t.Run("InvitationLifecycle", func(t *testing.T) {
		inv, err := store.CreateInvitation(ctx, superadminID, invitedEmail, "Outlet Barat", 24*time.Hour)
		if err != nil {
			t.Fatalf("CreateInvitation failed: %v", err)
		}
		if inv.ID == "" || inv.Status != "PENDING" {
			t.Fatalf("unexpected invitation: %+v", inv)
		}

		invs, err := store.ListInvitations(ctx, 10, 0)
		if err != nil {
			t.Fatalf("ListInvitations failed: %v", err)
		}
		found := false
		for _, item := range invs {
			if item.ID == inv.ID {
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("created invitation %s not found in list", inv.ID)
		}

		// Try creating invitation for existing registered user -> should error ErrUserAlreadyExists
		_, err = store.CreateInvitation(ctx, superadminID, targetEmail, "Outlet Timur", 24*time.Hour)
		if err != ErrUserAlreadyExists {
			t.Fatalf("expected ErrUserAlreadyExists, got: %v", err)
		}

		// Revoke invitation
		if err := store.RevokeInvitation(ctx, inv.ID); err != nil {
			t.Fatalf("RevokeInvitation failed: %v", err)
		}
	})

	// 3. Test UpdateUserStatus: PENDING_APPROVAL -> APPROVED
	t.Run("ApproveUser", func(t *testing.T) {
		err := store.UpdateUserStatus(ctx, superadminID, targetUserID, StatusApproved, "KTP verified", "req-app-1")
		if err != nil {
			t.Fatalf("UpdateUserStatus to APPROVED failed: %v", err)
		}

		users, err := store.ListUsers(ctx, StatusApproved, "owner-itest", 10, 0)
		if err != nil {
			t.Fatalf("ListUsers failed: %v", err)
		}
		if len(users) != 1 || users[0].ID != targetUserID {
			t.Fatalf("expected 1 approved user, got: %v", users)
		}
	})

	// 4. Test SuspendUser & Session Revocation
	t.Run("SuspendAndRevokeSessions", func(t *testing.T) {
		// Insert active session for target user
		_, err := pool.Exec(ctx, `
			INSERT INTO app_sessions (id, user_id, expires_at, created_at)
			VALUES ('session-test-integration-12345', $1::uuid, now() + interval '1 hour', now())`, targetUserID)
		if err != nil {
			t.Fatalf("failed to insert session: %v", err)
		}

		err = store.UpdateUserStatus(ctx, superadminID, targetUserID, StatusSuspended, "Violation of terms", "req-susp-1")
		if err != nil {
			t.Fatalf("UpdateUserStatus to SUSPENDED failed: %v", err)
		}

		// Verify session was revoked
		var revokedAt *time.Time
		err = pool.QueryRow(ctx, `SELECT revoked_at FROM app_sessions WHERE id = 'session-test-integration-12345'`).Scan(&revokedAt)
		if err != nil || revokedAt == nil {
			t.Fatalf("expected session to be revoked, got err=%v, revoked_at=%v", err, revokedAt)
		}

		// Reactivate
		err = store.UpdateUserStatus(ctx, superadminID, targetUserID, StatusApproved, "Appeal accepted", "req-react-1")
		if err != nil {
			t.Fatalf("Reactivate failed: %v", err)
		}
	})

	// 5. Test ListAudits
	t.Run("AuditLogTracking", func(t *testing.T) {
		audits, err := store.ListAudits(ctx, targetUserID, 10, 0)
		if err != nil {
			t.Fatalf("ListAudits failed: %v", err)
		}
		if len(audits) < 3 {
			t.Fatalf("expected at least 3 audit entries, got %d", len(audits))
		}
	})

	// 6. Test Traffic Metrics
	t.Run("TrafficMetricsQuery", func(t *testing.T) {
		metrics, err := store.GetTrafficMetrics(ctx, "24h")
		if err != nil {
			t.Fatalf("GetTrafficMetrics failed: %v", err)
		}
		if metrics.TimeRange != "24h" {
			t.Fatalf("expected 24h, got %s", metrics.TimeRange)
		}
	})
}
