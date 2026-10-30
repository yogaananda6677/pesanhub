package report

import (
	"context"
	"fmt"
	"strings"

	dbx "pesenhub/backend/internal/database"
)

type Store struct {
	db *dbx.Pool
}

func NewStore(db *dbx.Pool) *Store {
	return &Store{db: db}
}

func (s *Store) GetSummary(ctx context.Context, filter Filter) (Summary, error) {
	summary := Summary{
		OrdersByStatus: map[string]int64{
			"PENDING":          0,
			"ACCEPTED":         0,
			"PREPARING":        0,
			"READY_FOR_PICKUP": 0,
			"COMPLETED":        0,
			"CANCELLED":        0,
			"REJECTED":         0,
		},
		RevenueByPaymentMethod: map[string]int64{
			"CASH": 0,
			"QRIS": 0,
		},
		OrdersByPaymentStatus: map[string]int64{
			"UNPAID":  0,
			"PENDING": 0,
			"PAID":    0,
			"FAILED":  0,
		},
		RevenueByChannel: map[string]int64{
			"CASHIER_MANUAL": 0,
			"WHATSAPP":       0,
			"CUSTOMER_WEB":   0,
		},
		OrdersByChannel: map[string]int64{
			"CASHIER_MANUAL": 0,
			"WHATSAPP":       0,
			"CUSTOMER_WEB":   0,
		},
		From:            filter.From,
		To:              filter.To,
		BranchID:        filter.BranchID,
		BranchBreakdown: []BranchSummary{},
	}

	var conds []string
	var args []any
	argIdx := 1

	if filter.BranchID != "" {
		conds = append(conds, fmt.Sprintf("o.branch_id = $%d::uuid", argIdx))
		args = append(args, filter.BranchID)
		argIdx++
	}
	if filter.From != nil {
		conds = append(conds, fmt.Sprintf("o.created_at >= $%d", argIdx))
		args = append(args, *filter.From)
		argIdx++
	}
	if filter.To != nil {
		conds = append(conds, fmt.Sprintf("o.created_at <= $%d", argIdx))
		args = append(args, *filter.To)
		argIdx++
	}

	whereClause := ""
	if len(conds) > 0 {
		whereClause = "WHERE " + strings.Join(conds, " AND ")
	}

	// 1. Total revenue, gross revenue, discount, total orders, paid or completed count for AOV
	totalQuery := fmt.Sprintf(`
		SELECT 
			COALESCE(SUM(CASE WHEN (o.status = 'COMPLETED' OR p.status = 'PAID') AND o.status NOT IN ('CANCELLED', 'REJECTED') THEN o.total_amount ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN (o.status = 'COMPLETED' OR p.status = 'PAID') AND o.status NOT IN ('CANCELLED', 'REJECTED') THEN o.subtotal_amount ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN (o.status = 'COMPLETED' OR p.status = 'PAID') AND o.status NOT IN ('CANCELLED', 'REJECTED') THEN o.discount_amount ELSE 0 END), 0),
			COUNT(DISTINCT o.id),
			COUNT(DISTINCT CASE WHEN (o.status = 'COMPLETED' OR p.status = 'PAID') AND o.status NOT IN ('CANCELLED', 'REJECTED') THEN o.id END)
		FROM orders o
		LEFT JOIN payments p ON p.order_id = o.id
		%s`, whereClause)

	var paidOrCompleted int64
	err := s.db.QueryRow(ctx, totalQuery, args...).Scan(
		&summary.TotalRevenue,
		&summary.GrossRevenue,
		&summary.TotalDiscount,
		&summary.TotalOrders,
		&paidOrCompleted,
	)
	if err != nil {
		return summary, err
	}
	summary.NetRevenue = summary.TotalRevenue
	if summary.GrossRevenue == 0 && summary.TotalRevenue > 0 {
		summary.GrossRevenue = summary.TotalRevenue + summary.TotalDiscount
	}

	if paidOrCompleted > 0 {
		summary.AverageOrderValue = summary.TotalRevenue / paidOrCompleted
	}

	// 2. Orders by status
	statusQuery := fmt.Sprintf(`SELECT o.status, COUNT(*) FROM orders o %s GROUP BY o.status`, whereClause)
	statusRows, err := s.db.Query(ctx, statusQuery, args...)
	if err != nil {
		return summary, err
	}
	defer statusRows.Close()
	for statusRows.Next() {
		var st string
		var count int64
		if err := statusRows.Scan(&st, &count); err == nil {
			summary.OrdersByStatus[st] = count
		}
	}

	// 3. Orders by payment status
	paymentStatusQuery := fmt.Sprintf(`
		SELECT COALESCE(p.status, 'UNPAID'), COUNT(DISTINCT o.id)
		FROM orders o
		LEFT JOIN payments p ON p.order_id = o.id
		%s
		GROUP BY COALESCE(p.status, 'UNPAID')`, whereClause)
	paymentStatusRows, err := s.db.Query(ctx, paymentStatusQuery, args...)
	if err != nil {
		return summary, err
	}
	defer paymentStatusRows.Close()
	for paymentStatusRows.Next() {
		var ps string
		var count int64
		if err := paymentStatusRows.Scan(&ps, &count); err == nil {
			summary.OrdersByPaymentStatus[ps] = count
		}
	}

	// 4. Revenue by payment method
	revConds := []string{"(o.status = 'COMPLETED' OR p.status = 'PAID')", "o.status NOT IN ('CANCELLED', 'REJECTED')"}
	revConds = append(revConds, conds...)
	revWhere := "WHERE " + strings.Join(revConds, " AND ")
	revMethodQuery := fmt.Sprintf(`
		SELECT COALESCE(p.method, 'UNSPECIFIED'), COALESCE(SUM(o.total_amount), 0)
		FROM orders o
		JOIN payments p ON p.order_id = o.id
		%s
		GROUP BY COALESCE(p.method, 'UNSPECIFIED')`, revWhere)
	revMethodRows, err := s.db.Query(ctx, revMethodQuery, args...)
	if err != nil {
		return summary, err
	}
	defer revMethodRows.Close()
	for revMethodRows.Next() {
		var pm string
		var rev int64
		if err := revMethodRows.Scan(&pm, &rev); err == nil {
			if pm == "MIDTRANS_QRIS" {
				pm = "QRIS"
			}
			summary.RevenueByPaymentMethod[pm] = rev
			if pm == "CASH" {
				summary.CashRevenue += rev
			} else if pm == "QRIS" {
				summary.DigitalRevenue += rev
			}
		}
	}

	// 5. Channel breakdown (Revenue and Orders by channel source)
	channelQuery := fmt.Sprintf(`
		SELECT o.source,
			COUNT(DISTINCT o.id),
			COALESCE(SUM(CASE WHEN (o.status = 'COMPLETED' OR p.status = 'PAID') AND o.status NOT IN ('CANCELLED', 'REJECTED') THEN o.total_amount ELSE 0 END), 0)
		FROM orders o
		LEFT JOIN payments p ON p.order_id = o.id
		%s
		GROUP BY o.source`, whereClause)
	channelRows, err := s.db.Query(ctx, channelQuery, args...)
	if err == nil {
		defer channelRows.Close()
		for channelRows.Next() {
			var ch string
			var count int64
			var rev int64
			if err := channelRows.Scan(&ch, &count, &rev); err == nil {
				summary.RevenueByChannel[ch] = rev
				summary.OrdersByChannel[ch] = count
			}
		}
	}

	// 6. Branch breakdown if all branches mode or explicitly requested
	if filter.IncludeBranches || filter.BranchID == "" {
		var joinConds []string
		var joinArgs []any
		joinIdx := 1
		if filter.From != nil {
			joinConds = append(joinConds, fmt.Sprintf("o.created_at >= $%d", joinIdx))
			joinArgs = append(joinArgs, *filter.From)
			joinIdx++
		}
		if filter.To != nil {
			joinConds = append(joinConds, fmt.Sprintf("o.created_at <= $%d", joinIdx))
			joinArgs = append(joinArgs, *filter.To)
			joinIdx++
		}

		branchWhere := "WHERE b.is_active = true"
		if filter.BranchID != "" {
			branchWhere += fmt.Sprintf(" AND b.id = $%d::uuid", joinIdx)
			joinArgs = append(joinArgs, filter.BranchID)
			joinIdx++
		}

		joinExtra := ""
		if len(joinConds) > 0 {
			joinExtra = " AND " + strings.Join(joinConds, " AND ")
		}

		breakdownQuery := fmt.Sprintf(`
			SELECT b.id::text, b.code, b.name,
				COALESCE(SUM(CASE WHEN (o.status = 'COMPLETED' OR p.status = 'PAID') AND o.status NOT IN ('CANCELLED', 'REJECTED') THEN o.total_amount ELSE 0 END), 0),
				COUNT(DISTINCT o.id),
				COUNT(DISTINCT CASE WHEN o.status = 'COMPLETED' THEN o.id END)
			FROM branches b
			LEFT JOIN orders o ON o.branch_id = b.id%s
			LEFT JOIN payments p ON p.order_id = o.id
			%s
			GROUP BY b.id, b.code, b.name
			ORDER BY b.is_default DESC, b.name ASC`, joinExtra, branchWhere)

		bRows, err := s.db.Query(ctx, breakdownQuery, joinArgs...)
		if err != nil {
			return summary, err
		}
		defer bRows.Close()

		for bRows.Next() {
			var bs BranchSummary
			if err := bRows.Scan(&bs.BranchID, &bs.BranchCode, &bs.BranchName, &bs.TotalRevenue, &bs.TotalOrders, &bs.CompletedOrders); err == nil {
				summary.BranchBreakdown = append(summary.BranchBreakdown, bs)
			}
		}
	}

	return summary, nil
}

func (s *Store) GetTopProducts(ctx context.Context, filter Filter, limit int) (TopProductsResponse, error) {
	if limit <= 0 {
		limit = 5
	}
	resp := TopProductsResponse{
		TopProducts: []TopProduct{},
		TopToppings: []TopProduct{},
	}

	var conds []string
	var args []any
	argIdx := 1

	conds = append(conds, "(o.status = 'COMPLETED' OR p.status = 'PAID')", "o.status NOT IN ('CANCELLED', 'REJECTED')")

	if filter.BranchID != "" {
		conds = append(conds, fmt.Sprintf("o.branch_id = $%d::uuid", argIdx))
		args = append(args, filter.BranchID)
		argIdx++
	}
	if filter.From != nil {
		conds = append(conds, fmt.Sprintf("o.created_at >= $%d", argIdx))
		args = append(args, *filter.From)
		argIdx++
	}
	if filter.To != nil {
		conds = append(conds, fmt.Sprintf("o.created_at <= $%d", argIdx))
		args = append(args, *filter.To)
		argIdx++
	}

	whereClause := "WHERE " + strings.Join(conds, " AND ")

	// 1. Top menu items
	topItemQuery := fmt.Sprintf(`
		SELECT COALESCE(oi.menu_name_snapshot, 'Item'), 
		       COALESCE(SUM(oi.quantity), 0), 
		       COALESCE(SUM(oi.line_total_amount), 0)
		FROM order_items oi
		JOIN orders o ON o.id = oi.order_id
		LEFT JOIN payments p ON p.order_id = o.id
		%s
		GROUP BY oi.menu_name_snapshot
		ORDER BY SUM(oi.quantity) DESC, SUM(oi.line_total_amount) DESC
		LIMIT $%d`, whereClause, argIdx)

	itemArgs := append(args, limit)
	itemRows, err := s.db.Query(ctx, topItemQuery, itemArgs...)
	if err == nil {
		defer itemRows.Close()
		for itemRows.Next() {
			var tp TopProduct
			if err := itemRows.Scan(&tp.Name, &tp.Quantity, &tp.TotalRevenue); err == nil {
				resp.TopProducts = append(resp.TopProducts, tp)
			}
		}
	}

	// 2. Top toppings / modifiers
	topModifierQuery := fmt.Sprintf(`
		SELECT COALESCE(oim.name_snapshot, 'Topping'),
		       COALESCE(SUM(oim.quantity), 0),
		       COALESCE(SUM(oim.price_delta_amount * oim.quantity), 0)
		FROM order_item_modifiers oim
		JOIN order_items oi ON oi.id = oim.order_item_id
		JOIN orders o ON o.id = oi.order_id
		LEFT JOIN payments p ON p.order_id = o.id
		%s
		GROUP BY oim.name_snapshot
		ORDER BY SUM(oim.quantity) DESC, SUM(oim.price_delta_amount * oim.quantity) DESC
		LIMIT $%d`, whereClause, argIdx)

	modRows, err := s.db.Query(ctx, topModifierQuery, itemArgs...)
	if err == nil {
		defer modRows.Close()
		for modRows.Next() {
			var tp TopProduct
			if err := modRows.Scan(&tp.Name, &tp.Quantity, &tp.TotalRevenue); err == nil {
				resp.TopToppings = append(resp.TopToppings, tp)
			}
		}
	}

	return resp, nil
}
