package discount

import (
	"strings"
	"time"
)

// MatchChannel checks whether the discount's channel applies to the given order channel/source.
func MatchChannel(discountChannel, orderSource string) bool {
	dc := strings.ToUpper(strings.TrimSpace(discountChannel))
	if dc == "" || dc == ChannelAll {
		return true
	}

	src := strings.ToUpper(strings.TrimSpace(orderSource))
	switch src {
	case "CASHIER_MANUAL", "OFFLINE":
		return dc == ChannelOffline
	case "WHATSAPP", "WHATSAPP_BOT":
		return dc == ChannelWhatsApp
	case "CUSTOMER_WEB":
		return dc == ChannelCustomerWeb
	case "GOFOOD":
		return dc == ChannelGoFood
	case "GRABFOOD":
		return dc == ChannelGrabFood
	case "SHOPEEFOOD":
		return dc == ChannelShopeeFood
	default:
		return dc == src
	}
}

// Calculate applies a discount to the given input and returns the CalculationResult.
func Calculate(d *Discount, input CalculationInput) CalculationResult {
	if d == nil {
		return CalculationResult{
			DiscountAmount:   0,
			FinalTotalAmount: input.SubtotalAmount,
			Eligible:         false,
			IneligibleReason: ErrDiscountNotFound.Error(),
		}
	}

	if !d.IsActive {
		return CalculationResult{
			Discount:         d,
			DiscountAmount:   0,
			FinalTotalAmount: input.SubtotalAmount,
			Eligible:         false,
			IneligibleReason: ErrDiscountInactive.Error(),
		}
	}

	now := time.Now().UTC()
	if input.AtTime != nil {
		now = input.AtTime.UTC()
	}

	if d.StartTime != nil && now.Before(*d.StartTime) {
		return CalculationResult{
			Discount:         d,
			DiscountAmount:   0,
			FinalTotalAmount: input.SubtotalAmount,
			Eligible:         false,
			IneligibleReason: ErrDiscountExpired.Error(),
		}
	}

	if d.EndTime != nil && now.After(*d.EndTime) {
		return CalculationResult{
			Discount:         d,
			DiscountAmount:   0,
			FinalTotalAmount: input.SubtotalAmount,
			Eligible:         false,
			IneligibleReason: ErrDiscountExpired.Error(),
		}
	}

	if !MatchChannel(d.Channel, input.Channel) {
		return CalculationResult{
			Discount:         d,
			DiscountAmount:   0,
			FinalTotalAmount: input.SubtotalAmount,
			Eligible:         false,
			IneligibleReason: ErrDiscountChannelMismatch.Error(),
		}
	}

	if d.BranchID != nil && *d.BranchID != "" && input.BranchID != "" {
		if *d.BranchID != input.BranchID {
			return CalculationResult{
				Discount:         d,
				DiscountAmount:   0,
				FinalTotalAmount: input.SubtotalAmount,
				Eligible:         false,
				IneligibleReason: ErrDiscountBranchMismatch.Error(),
			}
		}
	}

	if input.SubtotalAmount < d.MinOrderAmount {
		return CalculationResult{
			Discount:         d,
			DiscountAmount:   0,
			FinalTotalAmount: input.SubtotalAmount,
			Eligible:         false,
			IneligibleReason: ErrDiscountMinSpendNotMet.Error(),
		}
	}

	var discountAmount int64
	switch d.Scope {
	case ScopeItem:
		menuSet := make(map[string]bool, len(d.MenuIDs))
		for _, mID := range d.MenuIDs {
			menuSet[mID] = true
		}

		var eligibleSubtotal int64
		for _, it := range input.Items {
			if menuSet[it.MenuID] {
				eligibleSubtotal += it.LineTotal
			}
		}

		if eligibleSubtotal <= 0 {
			return CalculationResult{
				Discount:         d,
				DiscountAmount:   0,
				FinalTotalAmount: input.SubtotalAmount,
				Eligible:         false,
				IneligibleReason: ErrDiscountNoMatchingItems.Error(),
			}
		}

		if d.Type == TypePercentage {
			discountAmount = (eligibleSubtotal * d.Value) / 100
			if d.MaxDiscountAmount != nil && *d.MaxDiscountAmount > 0 && discountAmount > *d.MaxDiscountAmount {
				discountAmount = *d.MaxDiscountAmount
			}
		} else { // Fixed
			discountAmount = d.Value
			if discountAmount > eligibleSubtotal {
				discountAmount = eligibleSubtotal
			}
		}

	case ScopeOrder:
		fallthrough
	default:
		if d.Type == TypePercentage {
			discountAmount = (input.SubtotalAmount * d.Value) / 100
			if d.MaxDiscountAmount != nil && *d.MaxDiscountAmount > 0 && discountAmount > *d.MaxDiscountAmount {
				discountAmount = *d.MaxDiscountAmount
			}
		} else { // Fixed
			discountAmount = d.Value
		}
	}

	if discountAmount < 0 {
		discountAmount = 0
	}
	if discountAmount > input.SubtotalAmount {
		discountAmount = input.SubtotalAmount
	}

	finalTotal := input.SubtotalAmount - discountAmount
	if finalTotal < 0 {
		finalTotal = 0
	}

	return CalculationResult{
		Discount:         d,
		DiscountAmount:   discountAmount,
		FinalTotalAmount: finalTotal,
		Eligible:         true,
	}
}
