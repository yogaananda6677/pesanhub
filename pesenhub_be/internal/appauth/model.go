package appauth

import "time"

type Role string
type Status string

const (
	RoleOwner      Role = "OWNER"
	RoleSuperadmin Role = "SUPERADMIN"

	StatusPending   Status = "PENDING_APPROVAL"
	StatusApproved  Status = "APPROVED"
	StatusRejected  Status = "REJECTED"
	StatusSuspended Status = "SUSPENDED"
)

type User struct {
	ID          string     `json:"id"`
	EmailMasked string     `json:"email"`
	DisplayName string     `json:"display_name"`
	Role        Role       `json:"role"`
	Status      Status     `json:"status"`
	ApprovedAt  *time.Time `json:"approved_at,omitempty"`
}

type GoogleIdentity struct {
	Subject, Email, DisplayName string
	EmailVerified               bool
}

type SessionResponse struct {
	AccessToken string    `json:"access_token"`
	TokenType   string    `json:"token_type"`
	ExpiresAt   time.Time `json:"expires_at"`
	User        User      `json:"user"`
}
