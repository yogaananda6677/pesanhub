package contact

import (
	"errors"
	"time"
)

const (
	TypeCustomer    = "CUSTOMER"
	TypeNonCustomer = "NON_CUSTOMER"
	TypeVendor      = "VENDOR"
	TypePersonal    = "PERSONAL"
	TypeBlacklist   = "BLACKLIST"
)

var (
	ErrContactNotFound = errors.New("contact not found")
	ErrInvalidPhone    = errors.New("invalid phone number")
	ErrInvalidInput    = errors.New("invalid contact input")
)

type Contact struct {
	ID               string    `json:"id"`
	BranchID         string    `json:"branch_id"`
	PhoneE164        string    `json:"phone_e164"`
	Name             string    `json:"name"`
	ContactType      string    `json:"contact_type"`
	AutoReplyEnabled bool      `json:"auto_reply_enabled"`
	Notes            string    `json:"notes"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type UpsertContactInput struct {
	BranchID         string `json:"branch_id"`
	Phone            string `json:"phone"`
	Name             string `json:"name,omitempty"`
	ContactType      string `json:"contact_type,omitempty"`
	AutoReplyEnabled *bool  `json:"auto_reply_enabled,omitempty"`
	Notes            string `json:"notes,omitempty"`
}

type ToggleReplyInput struct {
	AutoReplyEnabled bool `json:"auto_reply_enabled"`
}

type MarkNonCustomerInput struct {
	ContactType string `json:"contact_type,omitempty"`
	Notes       string `json:"notes,omitempty"`
}

type ListFilter struct {
	BranchID    string
	ContactType string
	Search      string
	Limit       int
}
