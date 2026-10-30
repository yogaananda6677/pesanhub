package report

import "time"

type Filter struct {
	BranchID        string
	IncludeBranches bool
	From            *time.Time
	To              *time.Time
}

type BranchSummary struct {
	BranchID        string `json:"branch_id"`
	BranchCode      string `json:"branch_code"`
	BranchName      string `json:"branch_name"`
	TotalRevenue    int64  `json:"total_revenue"`
	TotalOrders     int64  `json:"total_orders"`
	CompletedOrders int64  `json:"completed_orders"`
}

type Summary struct {
	TotalRevenue           int64            `json:"total_revenue"`
	GrossRevenue           int64            `json:"gross_revenue"`
	TotalDiscount          int64            `json:"total_discount"`
	NetRevenue             int64            `json:"net_revenue"`
	CashRevenue            int64            `json:"cash_revenue"`
	DigitalRevenue         int64            `json:"digital_revenue"`
	TotalOrders            int64            `json:"total_orders"`
	AverageOrderValue      int64            `json:"average_order_value"`
	OrdersByStatus         map[string]int64 `json:"orders_by_status"`
	RevenueByPaymentMethod map[string]int64 `json:"revenue_by_payment_method"`
	OrdersByPaymentStatus  map[string]int64 `json:"orders_by_payment_status"`
	RevenueByChannel       map[string]int64 `json:"revenue_by_channel"`
	OrdersByChannel        map[string]int64 `json:"orders_by_channel"`
	From                   *time.Time       `json:"from,omitempty"`
	To                     *time.Time       `json:"to,omitempty"`
	BranchID               string           `json:"branch_id,omitempty"`
	BranchBreakdown        []BranchSummary  `json:"branch_breakdown,omitempty"`
}

type SummaryResponse struct {
	Summary Summary `json:"summary"`
}

type TopProduct struct {
	Name         string `json:"name"`
	Quantity     int64  `json:"quantity"`
	TotalRevenue int64  `json:"total_revenue"`
}

type TopProductsResponse struct {
	TopProducts []TopProduct `json:"top_products"`
	TopToppings []TopProduct `json:"top_toppings"`
}
