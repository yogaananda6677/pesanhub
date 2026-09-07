package appauth

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrIdentityConflict = errors.New("google identity conflicts with an existing account")
var ErrBootstrapConflict = errors.New("bootstrap identity belongs to a non-superadmin account")

type IdentityStore interface {
	UpsertGoogleIdentity(context.Context, GoogleIdentity) (User, error)
	UserByID(context.Context, string) (User, error)
	CreateSession(context.Context, string, string, time.Time) error
	RevokeSession(context.Context, string, string) error
}

type Store struct{ pool *pgxpool.Pool }

func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

func (s *Store) ProvisionSuperadmin(ctx context.Context, email, displayName, requestID string) (User, bool, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	displayName = strings.TrimSpace(displayName)
	if email == "" || !strings.Contains(email, "@") || len(email) > 320 || displayName == "" || len(displayName) > 160 || strings.TrimSpace(requestID) == "" {
		return User{}, false, errors.New("invalid bootstrap input")
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return User{}, false, err
	}
	defer tx.Rollback(ctx)
	userID, err := newUUID()
	if err != nil {
		return User{}, false, err
	}
	result, err := tx.Exec(ctx, `
		INSERT INTO app_users (id, email_normalized, display_name, role, status, approved_at)
		VALUES ($1::uuid, $2, $3, 'SUPERADMIN', 'APPROVED', now())
		ON CONFLICT (email_normalized) DO NOTHING`, userID, email, displayName)
	if err != nil {
		return User{}, false, err
	}
	created := result.RowsAffected() == 1
	user, err := scanUser(tx.QueryRow(ctx, `SELECT id::text, email_normalized, display_name, role, status, approved_at FROM app_users WHERE email_normalized = $1 FOR UPDATE`, email))
	if err != nil {
		return User{}, false, err
	}
	if user.Role != RoleSuperadmin || user.Status != StatusApproved {
		return User{}, false, ErrBootstrapConflict
	}
	if created {
		auditID, idErr := newUUID()
		if idErr != nil {
			return User{}, false, idErr
		}
		_, err = tx.Exec(ctx, `
			INSERT INTO user_status_audits (id, user_id, from_status, to_status, reason_redacted, request_id)
			VALUES ($1::uuid, $2::uuid, NULL, 'APPROVED', 'CONTROLLED_BOOTSTRAP', $3)`, auditID, user.ID, requestID)
		if err != nil {
			return User{}, false, err
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return User{}, false, err
	}
	return user, created, nil
}

func (s *Store) UpsertGoogleIdentity(ctx context.Context, identity GoogleIdentity) (User, error) {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return User{}, err
	}
	defer tx.Rollback(ctx)

	email := strings.ToLower(strings.TrimSpace(identity.Email))
	var linkedUserID string
	err = tx.QueryRow(ctx, `SELECT user_id::text FROM external_identities WHERE provider = 'GOOGLE' AND provider_subject = $1 FOR UPDATE`, identity.Subject).Scan(&linkedUserID)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return User{}, err
	}
	if errors.Is(err, pgx.ErrNoRows) {
		userID, idErr := newUUID()
		if idErr != nil {
			return User{}, idErr
		}
		err = tx.QueryRow(ctx, `
			INSERT INTO app_users (id, email_normalized, display_name, role, status)
			VALUES ($1::uuid, $2, $3, 'OWNER', 'PENDING_APPROVAL')
			ON CONFLICT (email_normalized) DO UPDATE SET display_name = EXCLUDED.display_name, updated_at = now()
			RETURNING id::text`, userID, email, strings.TrimSpace(identity.DisplayName)).Scan(&linkedUserID)
		if err != nil {
			return User{}, err
		}
		var existingSubject string
		err = tx.QueryRow(ctx, `SELECT provider_subject FROM external_identities WHERE provider = 'GOOGLE' AND user_id = $1::uuid FOR UPDATE`, linkedUserID).Scan(&existingSubject)
		if err == nil && existingSubject != identity.Subject {
			return User{}, ErrIdentityConflict
		}
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return User{}, err
		}
		identityID, idErr := newUUID()
		if idErr != nil {
			return User{}, idErr
		}
		var actualUserID string
		err = tx.QueryRow(ctx, `
			INSERT INTO external_identities (id, user_id, provider, provider_subject, email_at_login)
			VALUES ($1::uuid, $2::uuid, 'GOOGLE', $3, $4)
			ON CONFLICT (provider, provider_subject) DO UPDATE
			SET email_at_login = EXCLUDED.email_at_login, last_login_at = now()
			RETURNING user_id::text`, identityID, linkedUserID, identity.Subject, email).Scan(&actualUserID)
		if err != nil || actualUserID != linkedUserID {
			var constraintError *pgconn.PgError
			if errors.As(err, &constraintError) && constraintError.Code == "23505" {
				err = ErrIdentityConflict
			}
			if err == nil {
				err = ErrIdentityConflict
			}
			return User{}, err
		}
	} else {
		_, err = tx.Exec(ctx, `UPDATE external_identities SET email_at_login = $2, last_login_at = now() WHERE provider = 'GOOGLE' AND provider_subject = $1`, identity.Subject, email)
		if err != nil {
			return User{}, err
		}
	}
	user, err := scanUser(tx.QueryRow(ctx, `SELECT id::text, email_normalized, display_name, role, status, approved_at FROM app_users WHERE id = $1::uuid`, linkedUserID))
	if err != nil {
		return User{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return User{}, err
	}
	return user, nil
}

func (s *Store) UserByID(ctx context.Context, id string) (User, error) {
	return scanUser(s.pool.QueryRow(ctx, `SELECT id::text, email_normalized, display_name, role, status, approved_at FROM app_users WHERE id = $1::uuid`, id))
}

func (s *Store) CreateSession(ctx context.Context, id, userID string, expiresAt time.Time) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO app_sessions (id, user_id, expires_at) VALUES ($1, $2::uuid, $3)`, id, userID, expiresAt)
	return err
}

func (s *Store) RevokeSession(ctx context.Context, id, userID string) error {
	_, err := s.pool.Exec(ctx, `UPDATE app_sessions SET revoked_at = now() WHERE id = $1 AND user_id = $2::uuid AND revoked_at IS NULL`, id, userID)
	return err
}

func (s *Store) ValidateSession(ctx context.Context, id, userID string) (role, status string, ok bool) {
	err := s.pool.QueryRow(ctx, `
		SELECT u.role, u.status
		FROM app_sessions s JOIN app_users u ON u.id = s.user_id
		WHERE s.id = $1 AND s.user_id = $2::uuid AND s.revoked_at IS NULL AND s.expires_at > now()`, id, userID).Scan(&role, &status)
	return role, status, err == nil
}

type rowScanner interface{ Scan(...any) error }

func scanUser(row rowScanner) (User, error) {
	var user User
	var email string
	err := row.Scan(&user.ID, &email, &user.DisplayName, &user.Role, &user.Status, &user.ApprovedAt)
	if err != nil {
		return User{}, err
	}
	user.EmailMasked = maskEmail(email)
	return user, nil
}

func maskEmail(email string) string {
	local, domain, ok := strings.Cut(email, "@")
	if !ok || local == "" || domain == "" {
		return "***"
	}
	prefix := local[:1]
	if len(local) > 2 {
		prefix = local[:2]
	}
	return prefix + "***@" + domain
}
