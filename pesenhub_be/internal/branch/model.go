package branch

import (
	"errors"
	"time"
)

const (
	DefaultBranchID   = "b0000000-0000-0000-0000-000000000001"
	DefaultBranchCode = "BWX"
	DefaultBranchName = "Cabang Utama Banyuwangi"
)

var (
	ErrNotFound       = errors.New("branch not found")
	ErrDuplicateCode  = errors.New("branch code already exists")
	ErrInvalidInput   = errors.New("invalid branch input")
	ErrBranchRequired = errors.New("cabang aktif wajib dipilih")
	ErrCrossBranch    = errors.New("akses lintas cabang tidak diizinkan")
)

type Branch struct {
	ID        string    `json:"id"`
	Code      string    `json:"code"`
	Name      string    `json:"name"`
	Address   string    `json:"address,omitempty"`
	Phone     string    `json:"phone,omitempty"`
	IsDefault bool      `json:"is_default"`
	IsActive  bool      `json:"is_active"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type CreateBranchInput struct {
	Code      string `json:"code"`
	Name      string `json:"name"`
	Address   string `json:"address,omitempty"`
	Phone     string `json:"phone,omitempty"`
	IsDefault bool   `json:"is_default,omitempty"`
}

type UpdateBranchInput struct {
	Code      string `json:"code,omitempty"`
	Name      string `json:"name,omitempty"`
	Address   string `json:"address,omitempty"`
	Phone     string `json:"phone,omitempty"`
	IsDefault *bool  `json:"is_default,omitempty"`
	IsActive  *bool  `json:"is_active,omitempty"`
}

type AssignUserBranchInput struct {
	BranchID string `json:"branch_id"`
}

type Scope struct {
	BranchID string
	All      bool
}
