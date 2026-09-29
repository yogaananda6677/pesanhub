package appauth

import (
	"context"
	"errors"
	"os"
	"sync"
	"testing"
	"time"

	dbx "pesenhub/backend/internal/database"
)

func TestGoogleIdentityApprovalAndBootstrapIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	pool, err := dbx.Open(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	store := NewStore(pool)
	ownerEmail := "admin-139@example.test"
	cashierEmail := "cashier-139@example.test"
	superadminEmail := "superadmin-139@example.test"
	cleanup := func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM user_status_audits WHERE user_id IN (SELECT id FROM app_users WHERE email_normalized = ANY($1::text[])) OR actor_user_id IN (SELECT id FROM app_users WHERE email_normalized = ANY($1::text[]))`, []string{ownerEmail, cashierEmail, superadminEmail})
		_, _ = pool.Exec(context.Background(), `DELETE FROM user_invitations WHERE email_normalized=$1`, cashierEmail)
		_, _ = pool.Exec(context.Background(), `DELETE FROM app_users WHERE email_normalized = ANY($1::text[])`, []string{ownerEmail, cashierEmail, superadminEmail})
	}
	cleanup()
	defer cleanup()

	identity := GoogleIdentity{Subject: "google-admin-139", Email: ownerEmail, DisplayName: "Admin 139", EmailVerified: true}
	const workers = 8
	ids := make(chan string, workers)
	errs := make(chan error, workers)
	var wait sync.WaitGroup
	for range workers {
		wait.Add(1)
		go func() {
			defer wait.Done()
			user, callErr := store.UpsertGoogleIdentity(ctx, identity)
			if callErr != nil {
				errs <- callErr
				return
			}
			ids <- user.ID
		}()
	}
	wait.Wait()
	close(ids)
	close(errs)
	for callErr := range errs {
		t.Fatalf("concurrent identity upsert: %v", callErr)
	}
	var ownerID string
	for id := range ids {
		if ownerID == "" {
			ownerID = id
		} else if id != ownerID {
			t.Fatalf("duplicate users created: %s and %s", ownerID, id)
		}
	}
	owner, err := store.UserByID(ctx, ownerID)
	if err != nil || owner.Status != StatusPending || owner.Role != RoleAdmin || owner.EmailMasked != "ad***@example.test" {
		t.Fatalf("owner=%#v err=%v", owner, err)
	}
	if _, err := store.UpsertGoogleIdentity(ctx, GoogleIdentity{Subject: "different-google-subject", Email: ownerEmail, DisplayName: "Attacker", EmailVerified: true}); !errors.Is(err, ErrIdentityConflict) {
		t.Fatalf("different subject linked to existing email: %v", err)
	}

	expires := time.Now().Add(time.Hour)
	if err := store.CreateSession(ctx, "session-owner-139-abcdefghijkl", ownerID, expires); err != nil {
		t.Fatal(err)
	}
	role, status, ok := store.ValidateSession(ctx, "session-owner-139-abcdefghijkl", ownerID)
	if !ok || role != "ADMIN" || status != "PENDING_APPROVAL" {
		t.Fatalf("pending validation role=%q status=%q ok=%v", role, status, ok)
	}
	if _, err := pool.Exec(ctx, `UPDATE app_users SET status='APPROVED', approved_at=now() WHERE id=$1::uuid`, ownerID); err != nil {
		t.Fatal(err)
	}
	role, status, ok = store.ValidateSession(ctx, "session-owner-139-abcdefghijkl", ownerID)
	if !ok || role != "ADMIN" || status != "APPROVED" {
		t.Fatalf("approved validation role=%q status=%q ok=%v", role, status, ok)
	}

	invitationID := "a1390000-0000-4000-8000-000000000001"
	if _, err := pool.Exec(ctx, `
		INSERT INTO user_invitations
		    (id,email_normalized,invited_by,outlet_name,role,status,expires_at)
		VALUES ($1::uuid,$2,$3::uuid,'Outlet Test','CASHIER','PENDING',$4)`, invitationID, cashierEmail, ownerID, time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	cashier, err := store.UpsertGoogleIdentity(ctx, GoogleIdentity{Subject: "google-cashier-139", Email: cashierEmail, DisplayName: "Cashier 139", EmailVerified: true})
	if err != nil || cashier.Role != RoleCashier || cashier.Status != StatusApproved {
		t.Fatalf("cashier=%#v err=%v", cashier, err)
	}
	var invitationStatus, acceptedUserID string
	if err := pool.QueryRow(ctx, `SELECT status, accepted_user_id FROM user_invitations WHERE id=$1::uuid`, invitationID).Scan(&invitationStatus, &acceptedUserID); err != nil {
		t.Fatal(err)
	}
	if invitationStatus != "ACCEPTED" || acceptedUserID != cashier.ID {
		t.Fatalf("invitation status=%q accepted_user_id=%q", invitationStatus, acceptedUserID)
	}

	superadmin, created, err := store.ProvisionSuperadmin(ctx, superadminEmail, "Root Admin", "bootstrap-test")
	if err != nil || !created || superadmin.Role != RoleSuperadmin || superadmin.Status != StatusApproved {
		t.Fatalf("superadmin=%#v created=%v err=%v", superadmin, created, err)
	}
	again, created, err := store.ProvisionSuperadmin(ctx, superadminEmail, "Root Admin", "bootstrap-test")
	if err != nil || created || again.ID != superadmin.ID {
		t.Fatalf("idempotent bootstrap=%#v created=%v err=%v", again, created, err)
	}
	linked, err := store.UpsertGoogleIdentity(ctx, GoogleIdentity{Subject: "google-superadmin-139", Email: superadminEmail, DisplayName: "Root Admin", EmailVerified: true})
	if err != nil || linked.ID != superadmin.ID || linked.Role != RoleSuperadmin || linked.Status != StatusApproved {
		t.Fatalf("linked superadmin=%#v err=%v", linked, err)
	}
}
