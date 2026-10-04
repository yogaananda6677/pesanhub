package discount

import (
	"errors"
	"time"
)

const (
	ScopeOrder = "ORDER"
	ScopeItem  = "ITEM"

	ChannelAll         = "ALL"
	ChannelOffline     = "OFFLINE"
	ChannelGoFood      = "GOFOOD"
	ChannelGrabFood    = "GRABFOOD"
	ChannelShopeeFood  = "SHOPEEFOOD"
	ChannelWhatsApp    = "WHATSAPP"
	ChannelCustomerWeb = "CUSTOMER_WEB"

	TypePercentage = "PERCENTAGE"
	TypeFixed      = "FIXED"
)

var (
	ErrDiscountNotFound        = errors.New("discount not found")
	ErrDiscountInactive        = errors.New("discount is inactive")
	ErrDiscountExpired         = errors.New("discount has expired or not started")
	ErrDiscountChannelMismatch = errors.New("discount is not applicable for this channel")
	ErrDiscountBranchMismatch  = errors.New("discount is not applicable for this branch")
	ErrDiscountMinSpendNotMet  = errors.New("order does not meet minimum spend for this discount")
	ErrDiscountNoMatchingItems = errors.New("no items eligible for this discount")
	ErrInvalidInput            = errors.New("invalid discount input")
	ErrVersionConflict         = errors.New("discount version conflict")
)

type Discount struct {
	ID                string     `json:"id"`
	Name              string     `json:"name"`
	Code              *string    `json:"code,omitempty"`
	Scope             string     `json:"scope"`
	Channel           string     `json:"channel"`
	Type              string     `json:"type"`
	Value             int64      `json:"value"`
	MaxDiscountAmount *int64     `json:"max_discount_amount,omitempty"`
	MinOrderAmount    int64      `json:"min_order_amount"`
	BranchID          *string    `json:"branch_id,omitempty"`
	BranchName        string     `json:"branch_name,omitempty"`
	IsActive          bool       `json:"is_active"`
	StartTime         *time.Time `json:"start_time,omitempty"`
	EndTime           *time.Time `json:"end_time,omitempty"`
	MenuIDs           []string   `json:"menu_ids,omitempty"`
	Version           int64      `json:"version"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at"`
}

type CreateDiscountInput struct {
	Name              string     `json:"name"`
	Code              *string    `json:"code,omitempty"`
	Scope             string     `json:"scope"`
	Channel           string     `json:"channel"`
	Type              string     `json:"type"`
	Value             int64      `json:"value"`
	MaxDiscountAmount *int64     `json:"max_discount_amount,omitempty"`
	MinOrderAmount    int64      `json:"min_order_amount"`
	BranchID          *string    `json:"branch_id,omitempty"`
	IsActive          *bool      `json:"is_active,omitempty"`
	StartTime         *time.Time `json:"start_time,omitempty"`
	EndTime           *time.Time `json:"end_time,omitempty"`
	MenuIDs           []string   `json:"menu_ids,omitempty"`
}

type UpdateDiscountInput struct {
	Name              string     `json:"name"`
	Code              *string    `json:"code,omitempty"`
	Scope             string     `json:"scope"`
	Channel           string     `json:"channel"`
	Type              string     `json:"type"`
	Value             int64      `json:"value"`
	MaxDiscountAmount *int64     `json:"max_discount_amount,omitempty"`
	MinOrderAmount    int64      `json:"min_order_amount"`
	BranchID          *string    `json:"branch_id,omitempty"`
	IsActive          *bool      `json:"is_active,omitempty"`
	StartTime         *time.Time `json:"start_time,omitempty"`
	EndTime           *time.Time `json:"end_time,omitempty"`
	MenuIDs           []string   `json:"menu_ids,omitempty"`
	ExpectedVersion   int64      `json:"expected_version,omitempty"`
}

type DiscountFilter struct {
	Channel    string
	BranchID   string
	Scope      string
	ActiveOnly bool
	Query      string
}

type ItemForDiscount struct {
	MenuID    string `json:"menu_id"`
	UnitPrice int64  `json:"unit_price"`
	Quantity  int    `json:"quantity"`
	LineTotal int64  `json:"line_total"`
}

type CalculationInput struct {
	Channel        string            `json:"channel"`
	BranchID       string            `json:"branch_id"`
	SubtotalAmount int64             `json:"subtotal_amount"`
	Items          []ItemForDiscount `json:"items"`
	DiscountID     string            `json:"discount_id"`
	AtTime         *time.Time        `json:"at_time,omitempty"`
}

type CalculationResult struct {
	Discount         *Discount `json:"discount,omitempty"`
	DiscountAmount   int64     `json:"discount_amount"`
	FinalTotalAmount int64     `json:"final_total_amount"`
	Eligible         bool      `json:"eligible"`
	IneligibleReason string    `json:"ineligible_reason,omitempty"`
}
