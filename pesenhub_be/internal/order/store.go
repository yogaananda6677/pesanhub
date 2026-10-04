package order

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"database/sql"
	"github.com/go-sql-driver/mysql"
	dbx "pesenhub/backend/internal/database"
	"time"

	"pesenhub/backend/internal/branch"
	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/discount"
	"pesenhub/backend/internal/domain"
	"pesenhub/backend/internal/httpapi"
)

type OutboxNotifier interface {
	Notify()
}

type Store struct {
	db       *dbx.Pool
	notifier OutboxNotifier
}

func NewStore(db *dbx.Pool) *Store { return &Store{db: db} }

func (s *Store) SetNotifier(n OutboxNotifier) {
	s.notifier = n
}

func (s *Store) notifyOutbox() {
	if s.notifier != nil {
		s.notifier.Notify()
	}
}

func resolveBranchForOrder(ctx context.Context, tx *dbx.Tx, branchID string) (id string, code string, name string, err error) {
	branchID = strings.TrimSpace(branchID)
	var bID, bCode, bName string
	if branchID != "" {
		err = tx.QueryRow(ctx, `SELECT id::text, code, name FROM branches WHERE id = $1::uuid`, branchID).Scan(&bID, &bCode, &bName)
		if err == nil {
			return bID, bCode, bName, nil
		}
	}
	err = tx.QueryRow(ctx, `SELECT id::text, code, name FROM branches WHERE is_default = TRUE LIMIT 1`).Scan(&bID, &bCode, &bName)
	if err == nil {
		return bID, bCode, bName, nil
	}
	return "b0000000-0000-0000-0000-000000000001", "BWX", "Cabang Utama Banyuwangi", nil
}

func (s *Store) Transition(ctx context.Context, orderID string, in TransitionInput, key, hash, actorID, roleRequest string) (StatusResult, bool, error) {
	tx, err := s.db.BeginTx(ctx, dbx.TxOptions{})
	if err != nil {
		return StatusResult{}, false, err
	}
	defer tx.Rollback(ctx)
	parts := strings.SplitN(roleRequest, "|", 2)
	role, requestID := parts[0], "unknown"
	if len(parts) == 2 && parts[1] != "" {
		requestID = parts[1]
	}
	if role != "STAFF" && role != "ADMIN" && role != "CASHIER" {
		return StatusResult{}, false, customer.ErrUnauthorized
	}
	var actualOrderID string
	var current string
	var version int64
	var orderBranchID string
	err = tx.QueryRow(ctx, `SELECT id::text,status,version,branch_id::text FROM orders WHERE id=$1 OR client_order_id=$1 FOR UPDATE`, orderID).Scan(&actualOrderID, &current, &version, &orderBranchID)
	if errors.Is(err, sql.ErrNoRows) {
		return StatusResult{}, false, ErrNotFound
	}
	if err != nil {
		return StatusResult{}, false, err
	}
	orderID = actualOrderID

	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, "ORDER_STATUS:"+orderID+":"+key); err != nil {
		return StatusResult{}, false, err
	}
	var replay StatusResult
	var storedHash, storedActor string
	err = tx.QueryRow(ctx, `SELECT o.id::text,o.status,o.version,h.request_hash,h.actor_id FROM order_status_history h JOIN orders o ON o.id=h.order_id WHERE h.order_id=$1 AND h.idempotency_key=$2`, orderID, key).Scan(&replay.ID, &replay.Status, &replay.Version, &storedHash, &storedActor)
	if err == nil {
		if storedHash != hash || storedActor != actorID {
			return StatusResult{}, false, ErrIdempotencyConflict
		}
		return replay, false, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return StatusResult{}, false, err
	}
	scope := branch.ScopeFromContext(ctx)
	if !scope.All && scope.BranchID != "" && orderBranchID != scope.BranchID {
		return StatusResult{}, false, ErrNotFound
	}
	if version != in.ExpectedVersion {
		return StatusResult{}, false, ErrVersionConflict
	}
	if !ValidTransition(domain.OrderStatus(current), domain.OrderStatus(in.TargetStatus)) {
		return StatusResult{}, false, ErrInvalidTransition
	}
	result := StatusResult{ID: orderID, Status: in.TargetStatus, Version: version + 1}
	if _, err = tx.Exec(ctx, `UPDATE orders SET status=$2,version=$3,updated_at=now() WHERE id=$1`, orderID, result.Status, result.Version); err != nil {
		return StatusResult{}, false, err
	}
	metadata, _ := json.Marshal(map[string]any{"from_status": current, "to_status": result.Status, "version": result.Version, "branch_id": orderBranchID})
	auditMeta := SanitizeAuditMetadata(map[string]any{
		"order_id":    orderID,
		"branch_id":   orderBranchID,
		"from_status": current,
		"to_status":   result.Status,
		"version":     result.Version,
		"reason_code": in.ReasonCode,
	})
	if _, err = tx.Exec(ctx, `INSERT INTO order_status_history (id,order_id,from_status,to_status,order_version,actor_type,actor_id,reason_code,request_id,idempotency_key,request_hash) VALUES ($1,$2,$3,$4,$5,'STAFF',$6,NULLIF($7,''),$8,$9,$10)`, customer.NewID(), orderID, current, result.Status, result.Version, actorID, in.ReasonCode, requestID, key, hash); err != nil {
		return StatusResult{}, false, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO audit_logs (id,aggregate_type,aggregate_id,action,actor_type,actor_id,request_id,metadata_redacted) VALUES ($1,'ORDER',$2,'ORDER_STATUS_CHANGED','STAFF',$3,$4,$5)`, customer.NewID(), orderID, actorID, requestID, auditMeta); err != nil {
		return StatusResult{}, false, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO outbox_events (id,aggregate_type,aggregate_id,event_type,payload,deduplication_key) VALUES ($1,'ORDER',$2,'ORDER_STATUS_CHANGED',$3,$4)`, customer.NewID(), orderID, metadata, "order-status:"+orderID+":"+fmt.Sprint(result.Version)); err != nil {
		return StatusResult{}, false, err
	}
	if err = tx.Commit(ctx); err != nil {
		return StatusResult{}, false, err
	}
	s.notifyOutbox()
	return result, true, nil
}

func nextDailyOrderNumber(ctx context.Context, tx *dbx.Tx, branchID, branchCode string) (string, error) {
	if branchCode == "" {
		branchCode = "ORD"
	}
	if branchID == "" {
		branchID = "b0000000-0000-0000-0000-000000000001"
	}
	loc, err := time.LoadLocation("Asia/Jakarta")
	if err != nil {
		loc = time.FixedZone("WIB", 7*3600)
	}
	now := time.Now().In(loc)
	dateStr := now.Format("2006-01-02")
	dateCompact := now.Format("20060102")

	var seq int
	err = tx.QueryRow(ctx, `SELECT last_sequence FROM daily_order_sequences WHERE branch_id = $1 AND order_date = $2 FOR UPDATE`, branchID, dateStr).Scan(&seq)
	if errors.Is(err, sql.ErrNoRows) {
		seq = 1
		_, err = tx.Exec(ctx, `INSERT INTO daily_order_sequences (branch_id, order_date, last_sequence) VALUES ($1, $2, 1)`, branchID, dateStr)
	} else if err == nil {
		seq++
		_, err = tx.Exec(ctx, `UPDATE daily_order_sequences SET last_sequence = $1, updated_at = now() WHERE branch_id = $2 AND order_date = $3`, seq, branchID, dateStr)
	}
	if err != nil {
		// Fallback to random if sequence table fails
		return fmt.Sprintf("%s-%s-%s", branchCode, dateCompact, strings.ToUpper(strings.ReplaceAll(customer.NewID(), "-", "")[:6])), nil
	}
	return fmt.Sprintf("%s-%s-%04d", branchCode, dateCompact, seq), nil
}

func loadDiscountForOrder(ctx context.Context, tx *dbx.Tx, discountID string) (*discount.Discount, error) {
	q := `SELECT id, name, code, scope, channel, type, value, max_discount_amount, min_order_amount,
	             branch_id, is_active, start_time, end_time, version, created_at, updated_at
	      FROM discounts
	      WHERE id = $1 FOR SHARE`

	var d discount.Discount
	var code, branchID sql.NullString
	var startTime, endTime sql.NullTime

	err := tx.QueryRow(ctx, q, discountID).Scan(
		&d.ID, &d.Name, &code, &d.Scope, &d.Channel, &d.Type, &d.Value,
		&d.MaxDiscountAmount, &d.MinOrderAmount, &branchID,
		&d.IsActive, &startTime, &endTime, &d.Version, &d.CreatedAt, &d.UpdatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, discount.ErrDiscountNotFound
	}
	if err != nil {
		return nil, err
	}
	if code.Valid {
		d.Code = &code.String
	}
	if branchID.Valid {
		d.BranchID = &branchID.String
	}
	if startTime.Valid {
		d.StartTime = &startTime.Time
	}
	if endTime.Valid {
		d.EndTime = &endTime.Time
	}

	rows, err := tx.Query(ctx, `SELECT menu_id FROM discount_menus WHERE discount_id = $1`, discountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	d.MenuIDs = []string{}
	for rows.Next() {
		var mID string
		if err := rows.Scan(&mID); err != nil {
			return nil, err
		}
		d.MenuIDs = append(d.MenuIDs, mID)
	}
	return &d, rows.Err()
}

func (s *Store) Create(ctx context.Context, in CreateInput, key, hash, actorRequest string) (Order, bool, error) {
	tx, err := s.db.BeginTx(ctx, dbx.TxOptions{})
	if err != nil {
		return Order{}, false, err
	}
	defer tx.Rollback(ctx)

	orderSource := strings.TrimSpace(in.Source)
	if orderSource == "" {
		orderSource = "CASHIER_MANUAL"
	}

	priceChannel := "OFFLINE"
	switch orderSource {
	case "GRABFOOD", "GOFOOD", "SHOPEEFOOD":
		priceChannel = orderSource
	}

	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, orderSource+":"+key); err != nil {
		return Order{}, false, err
	}
	if existing, found, err := loadExisting(ctx, tx, orderSource, key, hash); found || err != nil {
		return existing, false, err
	}

	items := make([]Item, 0, len(in.Items))
	var total int64
	for _, requested := range in.Items {
		menu, err := loadMenuForChannel(ctx, tx, requested.MenuID, priceChannel)
		if err != nil {
			return Order{}, false, err
		}
		unit, err := catalog.Price(menu, requested.Selections)
		if err != nil {
			return Order{}, false, err
		}
		if unit > (1<<63-1)/int64(requested.Quantity) {
			return Order{}, false, ErrInvalidInput
		}
		line := unit * int64(requested.Quantity)
		if total > 1<<63-1-line {
			return Order{}, false, ErrInvalidInput
		}
		total += line
		items = append(items, Item{ID: customer.NewID(), MenuID: menu.ID, Name: menu.Name, SKU: menu.SKU, UnitPriceAmount: unit, Quantity: requested.Quantity, LineTotalAmount: line})
	}

	bID, bCode, bName, _ := resolveBranchForOrder(ctx, tx, in.BranchID)

	subtotal := total
	var discountAmount int64
	var discountIDRef any
	var discountNameRef any
	var discountIDStr, discountNameStr string

	if strings.TrimSpace(in.DiscountID) != "" {
		disc, err := loadDiscountForOrder(ctx, tx, strings.TrimSpace(in.DiscountID))
		if err != nil {
			return Order{}, false, fmt.Errorf("%w: %s", ErrInvalidInput, err.Error())
		}
		calcItems := make([]discount.ItemForDiscount, len(items))
		for i, it := range items {
			calcItems[i] = discount.ItemForDiscount{
				MenuID:    it.MenuID,
				UnitPrice: it.UnitPriceAmount,
				Quantity:  it.Quantity,
				LineTotal: it.LineTotalAmount,
			}
		}
		calcRes := discount.Calculate(disc, discount.CalculationInput{
			Channel:        orderSource,
			BranchID:       bID,
			SubtotalAmount: subtotal,
			Items:          calcItems,
			DiscountID:     disc.ID,
		})
		if !calcRes.Eligible {
			return Order{}, false, fmt.Errorf("%w: %s", ErrInvalidInput, calcRes.IneligibleReason)
		}
		discountAmount = calcRes.DiscountAmount
		discountIDRef = disc.ID
		discountNameRef = disc.Name
		discountIDStr = disc.ID
		discountNameStr = disc.Name
		total = calcRes.FinalTotalAmount
	}

	parts := strings.SplitN(actorRequest, "|", 2)
	actorID, requestID := parts[0], "unknown"
	if len(parts) == 2 && parts[1] != "" {
		requestID = parts[1]
	}
	orderNum, err := nextDailyOrderNumber(ctx, tx, bID, bCode)
	if err != nil {
		return Order{}, false, err
	}
	orderID := customer.NewID()
	if in.ClientOrderID != "" && domain.ValidUUID(in.ClientOrderID) {
		orderID = in.ClientOrderID
	}
	o := Order{
		ID:             orderID,
		OrderNumber:    orderNum,
		ClientOrderID:  in.ClientOrderID,
		BranchID:       bID,
		BranchCode:     bCode,
		BranchName:     bName,
		Source:         orderSource,
		Status:         "PENDING",
		SubtotalAmount: subtotal,
		DiscountAmount: discountAmount,
		DiscountID:     discountIDStr,
		DiscountName:   discountNameStr,
		TotalAmount:    total,
		Version:        1,
		Items:          items,
	}
	var customerRef any
	if in.CustomerID != "" {
		customerRef = in.CustomerID
	}
	err = tx.QueryRow(ctx, `INSERT INTO orders (id,order_number,customer_id,branch_id,source,status,customer_name_snapshot,customer_phone_snapshot,notes,subtotal_amount,discount_amount,discount_id,discount_name_snapshot,total_amount,idempotency_key,client_order_id,request_hash) VALUES ($1,$2,$3,$4::uuid,$5,'PENDING',$6,NULLIF($7,''),NULLIF($8,''),$9,$10,$11,$12,$13,$14,$15,$16) RETURNING created_at`, o.ID, o.OrderNumber, customerRef, bID, orderSource, in.CustomerName, in.CustomerPhone, in.Notes, subtotal, discountAmount, discountIDRef, discountNameRef, total, key, in.ClientOrderID, hash).Scan(&o.CreatedAt)
	if err != nil {
		var dbErr *mysql.MySQLError
		if errors.As(err, &dbErr) && dbErr.Number == 1062 {
			return Order{}, false, ErrIdempotencyConflict
		}
		return Order{}, false, err
	}
	for i, requested := range in.Items {
		item := items[i]
		_, err = tx.Exec(ctx, `INSERT INTO order_items (id,order_id,menu_id,menu_name_snapshot,sku_snapshot,unit_price_amount,quantity,line_total_amount,notes) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,NULLIF($9,''))`, item.ID, o.ID, item.MenuID, item.Name, item.SKU, item.UnitPriceAmount, item.Quantity, item.LineTotalAmount, requested.Notes)
		if err != nil {
			return Order{}, false, err
		}
		menu, _ := loadMenu(ctx, tx, item.MenuID)
		if err = insertOrderItemModifiers(ctx, tx, item.ID, menu, requested.Selections); err != nil {
			return Order{}, false, err
		}
	}
	metadata, _ := json.Marshal(map[string]any{
		"order_id":     o.ID,
		"order_number": o.OrderNumber,
		"branch_id":    bID,
		"source":       orderSource,
		"status":       "PENDING",
		"total_amount": total,
		"version":      1,
	})
	auditMeta := SanitizeAuditMetadata(map[string]any{
		"order_id":       o.ID,
		"order_number":   o.OrderNumber,
		"branch_id":      bID,
		"source":         orderSource,
		"status":         "PENDING",
		"total_amount":   total,
		"customer_name":  in.CustomerName,
		"customer_phone": in.CustomerPhone,
		"version":        1,
	})
	statements := []struct {
		q    string
		args []any
	}{
		{`INSERT INTO order_status_history (id,order_id,to_status,order_version,actor_type,actor_id,request_id) VALUES ($1,$2,'PENDING',1,'STAFF',$3,$4)`, []any{customer.NewID(), o.ID, actorID, requestID}},
		{`INSERT INTO audit_logs (id,aggregate_type,aggregate_id,action,actor_type,actor_id,request_id,metadata_redacted) VALUES ($1,'ORDER',$2,'ORDER_CREATED','STAFF',$3,$4,$5)`, []any{customer.NewID(), o.ID, actorID, requestID, auditMeta}},
		{`INSERT INTO outbox_events (id,aggregate_type,aggregate_id,event_type,payload,deduplication_key) VALUES ($1,'ORDER',$2,'ORDER_CREATED',$3,$4)`, []any{customer.NewID(), o.ID, metadata, "order-created:" + o.ID}},
	}
	for _, st := range statements {
		if _, err = tx.Exec(ctx, st.q, st.args...); err != nil {
			return Order{}, false, err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return Order{}, false, err
	}
	s.notifyOutbox()
	return o, true, nil
}

func loadExisting(ctx context.Context, tx *dbx.Tx, source, key, hash string) (Order, bool, error) {
	var o Order
	var stored string
	err := tx.QueryRow(ctx, `SELECT o.id::text,o.order_number,COALESCE(o.client_order_id::text, ''),o.branch_id::text,COALESCE(b.code, ''),COALESCE(b.name, ''),o.source,o.status,o.subtotal_amount,o.discount_amount,COALESCE(o.discount_id::text, ''),COALESCE(o.discount_name_snapshot, ''),o.total_amount,o.version,o.created_at,o.request_hash FROM orders o LEFT JOIN branches b ON b.id = o.branch_id WHERE o.source=$1 AND o.idempotency_key=$2`, source, key).Scan(&o.ID, &o.OrderNumber, &o.ClientOrderID, &o.BranchID, &o.BranchCode, &o.BranchName, &o.Source, &o.Status, &o.SubtotalAmount, &o.DiscountAmount, &o.DiscountID, &o.DiscountName, &o.TotalAmount, &o.Version, &o.CreatedAt, &stored)
	if errors.Is(err, sql.ErrNoRows) {
		return Order{}, false, nil
	}
	if err != nil {
		return Order{}, false, err
	}
	if stored != hash {
		return Order{}, true, ErrIdempotencyConflict
	}
	rows, err := tx.Query(ctx, `SELECT id::text,menu_id::text,menu_name_snapshot,sku_snapshot,unit_price_amount,quantity,line_total_amount FROM order_items WHERE order_id=$1 ORDER BY created_at,id`, o.ID)
	if err != nil {
		return Order{}, true, err
	}
	defer rows.Close()
	for rows.Next() {
		var item Item
		if err = rows.Scan(&item.ID, &item.MenuID, &item.Name, &item.SKU, &item.UnitPriceAmount, &item.Quantity, &item.LineTotalAmount); err != nil {
			return Order{}, true, err
		}
		o.Items = append(o.Items, item)
	}
	return o, true, rows.Err()
}

func selectedOptionCounts(selections []catalog.Selection) map[string]int {
	counts := make(map[string]int)
	for _, selection := range selections {
		for _, optionID := range selection.OptionIDs {
			counts[optionID]++
		}
	}
	return counts
}

func insertOrderItemModifiers(ctx context.Context, tx *dbx.Tx, itemID string, menu catalog.Menu, selections []catalog.Selection) error {
	options := make(map[string]catalog.Option)
	for _, group := range menu.Groups {
		for _, option := range group.Options {
			options[option.ID] = option
		}
	}
	for optionID, quantity := range selectedOptionCounts(selections) {
		option, ok := options[optionID]
		if !ok {
			return ErrInvalidInput
		}
		_, err := tx.Exec(ctx, `INSERT INTO order_item_modifiers (id,order_item_id,modifier_option_id,name_snapshot,price_delta_amount,quantity) VALUES ($1,$2,$3,$4,$5,$6)`, customer.NewID(), itemID, option.ID, option.Name, option.PriceDeltaAmount, quantity)
		if err != nil {
			return err
		}
	}
	return nil
}

func loadMenu(ctx context.Context, tx *dbx.Tx, id string) (catalog.Menu, error) {
	return loadMenuForChannel(ctx, tx, id, "OFFLINE")
}

func loadMenuForChannel(ctx context.Context, tx *dbx.Tx, id string, channel string) (catalog.Menu, error) {
	var m catalog.Menu
	err := tx.QueryRow(ctx, `SELECT id::text,category_id::text,sku,name,price_amount,is_available,version,sort_order FROM menus WHERE id=$1 FOR SHARE`, id).Scan(&m.ID, &m.CategoryID, &m.SKU, &m.Name, &m.PriceAmount, &m.Available, &m.Version, &m.SortOrder)
	if errors.Is(err, sql.ErrNoRows) {
		return m, &catalog.ValidationError{Field: "menu_id", Err: catalog.ErrUnavailable}
	}
	if err != nil {
		return m, err
	}
	if channel != "" && channel != "OFFLINE" {
		var channelPrice int64
		err := tx.QueryRow(ctx, `SELECT amount FROM menu_channel_prices WHERE menu_id=$1 AND channel=$2`, id, channel).Scan(&channelPrice)
		if err == nil && channelPrice >= 0 {
			m.PriceAmount = channelPrice
		}
	}
	rows, err := tx.Query(ctx, `SELECT g.id::text,g.code,g.name,g.min_select,g.max_select,g.sort_order,g.is_active,o.id::text,o.code,o.name,o.price_delta_amount,o.is_available,o.sort_order FROM modifier_groups g LEFT JOIN modifier_options o ON o.group_id=g.id WHERE g.menu_id=$1 ORDER BY g.sort_order,g.id,o.sort_order,o.id FOR SHARE`, id)
	if err != nil {
		return m, err
	}
	defer rows.Close()
	groups := map[string]int{}
	for rows.Next() {
		var g catalog.Group
		var oid, ocode, oname *string
		var price *int64
		var avail *bool
		var sort *int
		if err = rows.Scan(&g.ID, &g.Code, &g.Name, &g.MinSelect, &g.MaxSelect, &g.SortOrder, &g.Active, &oid, &ocode, &oname, &price, &avail, &sort); err != nil {
			return m, err
		}
		idx, ok := groups[g.ID]
		if !ok {
			idx = len(m.Groups)
			groups[g.ID] = idx
			m.Groups = append(m.Groups, g)
		}
		if oid != nil {
			m.Groups[idx].Options = append(m.Groups[idx].Options, catalog.Option{ID: *oid, Code: *ocode, Name: *oname, PriceDeltaAmount: *price, Available: *avail, SortOrder: *sort})
		}
	}
	if err = rows.Err(); err != nil {
		return m, err
	}
	return m, nil
}

func (s *Store) List(ctx context.Context, filter OrderFilter) ([]OrderDetail, string, error) {
	var where []string
	var args []any

	if len(filter.Sources) > 0 {
		args = append(args, filter.Sources)
		where = append(where, fmt.Sprintf("o.source = ANY($%d)", len(args)))
	}
	if len(filter.Statuses) > 0 {
		args = append(args, filter.Statuses)
		where = append(where, fmt.Sprintf("o.status = ANY($%d)", len(args)))
	}
	if filter.CreatedFrom != nil {
		args = append(args, *filter.CreatedFrom)
		where = append(where, fmt.Sprintf("o.created_at >= $%d", len(args)))
	}
	if filter.CreatedTo != nil {
		args = append(args, *filter.CreatedTo)
		where = append(where, fmt.Sprintf("o.created_at <= $%d", len(args)))
	}
	if filter.BranchID != "" {
		args = append(args, filter.BranchID)
		where = append(where, fmt.Sprintf("o.branch_id = $%d::uuid", len(args)))
	}

	orderDir := "ASC"
	if strings.ToLower(filter.Pagination.Order) == "desc" {
		orderDir = "DESC"
	}

	if filter.Pagination.Cursor != "" {
		curTime, curID, err := DecodeCursor(filter.Pagination.Cursor)
		if err != nil {
			return nil, "", err
		}
		args = append(args, curTime, curID)
		if orderDir == "DESC" {
			where = append(where, fmt.Sprintf("(o.created_at, o.id) < ($%d, $%d)", len(args)-1, len(args)))
		} else {
			where = append(where, fmt.Sprintf("(o.created_at, o.id) > ($%d, $%d)", len(args)-1, len(args)))
		}
	}

	whereClause := ""
	if len(where) > 0 {
		whereClause = "WHERE " + strings.Join(where, " AND ")
	}

	limit := filter.Pagination.Size
	if limit < 1 {
		limit = httpapi.DefaultPageSize
	} else if limit > httpapi.MaxPageSize {
		limit = httpapi.MaxPageSize
	}

	args = append(args, limit+1)
	limitClause := fmt.Sprintf("LIMIT $%d", len(args))
	orderClause := fmt.Sprintf("ORDER BY o.created_at %s, o.id %s", orderDir, orderDir)

	query := fmt.Sprintf(`SELECT o.id::text, o.order_number, COALESCE(o.client_order_id::text, ''), COALESCE(o.customer_id::text, ''),
		o.branch_id::text, COALESCE(b.code, ''), COALESCE(b.name, ''),
		o.source, o.status, o.customer_name_snapshot, o.customer_phone_snapshot,
		COALESCE(o.notes, ''), o.subtotal_amount, o.discount_amount, COALESCE(o.discount_id::text, ''), COALESCE(o.discount_name_snapshot, ''),
		o.total_amount, o.version, o.created_at, o.updated_at
		FROM orders o
		LEFT JOIN branches b ON b.id = o.branch_id
		%s %s %s`, whereClause, orderClause, limitClause)

	rows, err := s.db.Query(ctx, query, args...)
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()

	var orders []OrderDetail
	for rows.Next() {
		var o OrderDetail
		var phone *string
		if err = rows.Scan(&o.ID, &o.OrderNumber, &o.ClientOrderID, &o.CustomerID, &o.BranchID, &o.BranchCode, &o.BranchName, &o.Source, &o.Status, &o.CustomerName, &phone, &o.Notes, &o.SubtotalAmount, &o.DiscountAmount, &o.DiscountID, &o.DiscountName, &o.TotalAmount, &o.Version, &o.CreatedAt, &o.UpdatedAt); err != nil {
			return nil, "", err
		}
		o.CustomerPhone = phone
		orders = append(orders, o)
	}
	if err = rows.Err(); err != nil {
		return nil, "", err
	}

	var nextCursor string
	if len(orders) > limit {
		nextCursor = EncodeCursor(orders[limit-1].CreatedAt, orders[limit-1].ID)
		orders = orders[:limit]
	}

	if err = s.populateItems(ctx, orders); err != nil {
		return nil, "", err
	}

	return orders, nextCursor, nil
}

func (s *Store) GetByID(ctx context.Context, orderID string) (OrderDetail, error) {
	var o OrderDetail
	var phone *string
	err := s.db.QueryRow(ctx, `SELECT o.id::text, o.order_number, COALESCE(o.client_order_id::text, ''), COALESCE(o.customer_id::text, ''),
		o.branch_id::text, COALESCE(b.code, ''), COALESCE(b.name, ''),
		o.source, o.status, o.customer_name_snapshot, o.customer_phone_snapshot,
		COALESCE(o.notes, ''), o.subtotal_amount, o.discount_amount, COALESCE(o.discount_id::text, ''), COALESCE(o.discount_name_snapshot, ''),
		o.total_amount, o.version, o.created_at, o.updated_at,
		COALESCE(o.public_tracking_token, '')
		FROM orders o
		LEFT JOIN branches b ON b.id = o.branch_id
		WHERE o.id = $1 OR o.client_order_id = $1`, orderID).Scan(&o.ID, &o.OrderNumber, &o.ClientOrderID, &o.CustomerID, &o.BranchID, &o.BranchCode, &o.BranchName, &o.Source, &o.Status, &o.CustomerName, &phone, &o.Notes, &o.SubtotalAmount, &o.DiscountAmount, &o.DiscountID, &o.DiscountName, &o.TotalAmount, &o.Version, &o.CreatedAt, &o.UpdatedAt, &o.PublicTrackingToken)
	if errors.Is(err, sql.ErrNoRows) {
		return OrderDetail{}, ErrNotFound
	}
	if err != nil {
		return OrderDetail{}, err
	}
	o.CustomerPhone = phone
	orders := []OrderDetail{o}
	if err = s.populateItems(ctx, orders); err != nil {
		return OrderDetail{}, err
	}
	o = orders[0]

	histRows, err := s.db.Query(ctx, `SELECT COALESCE(from_status, ''), to_status, order_version, actor_type, COALESCE(actor_id, ''), COALESCE(reason_code, ''), created_at
		FROM order_status_history
		WHERE order_id = $1
		ORDER BY order_version ASC`, o.ID)
	if err != nil {
		return OrderDetail{}, err
	}
	defer histRows.Close()

	o.History = []OrderStatusHistoryEntry{}
	for histRows.Next() {
		var h OrderStatusHistoryEntry
		if err = histRows.Scan(&h.FromStatus, &h.ToStatus, &h.Version, &h.ActorType, &h.ActorID, &h.ReasonCode, &h.CreatedAt); err != nil {
			return OrderDetail{}, err
		}
		o.History = append(o.History, h)
	}
	if err = histRows.Err(); err != nil {
		return OrderDetail{}, err
	}
	return o, nil
}

func (s *Store) GetLatestByPhone(ctx context.Context, phone string) (OrderDetail, error) {
	phone = strings.TrimSpace(phone)
	if phone == "" {
		return OrderDetail{}, ErrNotFound
	}

	normPhone, err := NormalizePhone(phone)
	if err != nil {
		normPhone = phone
	}

	var o OrderDetail
	var phoneSnapshot *string
	err = s.db.QueryRow(ctx, `SELECT o.id::text, o.order_number, COALESCE(o.client_order_id::text, ''), COALESCE(o.customer_id::text, ''),
		o.branch_id::text, COALESCE(b.code, ''), COALESCE(b.name, ''),
		o.source, o.status, o.customer_name_snapshot, o.customer_phone_snapshot,
		COALESCE(o.notes, ''), o.subtotal_amount, o.discount_amount, COALESCE(o.discount_id::text, ''), COALESCE(o.discount_name_snapshot, ''),
		o.total_amount, o.version, o.created_at, o.updated_at,
		COALESCE(o.public_tracking_token, '')
		FROM orders o
		LEFT JOIN branches b ON b.id = o.branch_id
		WHERE o.customer_phone_snapshot = $1 OR o.customer_phone_snapshot = $2
		ORDER BY o.created_at DESC LIMIT 1`, normPhone, phone).Scan(&o.ID, &o.OrderNumber, &o.ClientOrderID, &o.CustomerID, &o.BranchID, &o.BranchCode, &o.BranchName, &o.Source, &o.Status, &o.CustomerName, &phoneSnapshot, &o.Notes, &o.SubtotalAmount, &o.DiscountAmount, &o.DiscountID, &o.DiscountName, &o.TotalAmount, &o.Version, &o.CreatedAt, &o.UpdatedAt, &o.PublicTrackingToken)
	if errors.Is(err, sql.ErrNoRows) {
		return OrderDetail{}, ErrNotFound
	}
	if err != nil {
		return OrderDetail{}, err
	}
	o.CustomerPhone = phoneSnapshot
	orders := []OrderDetail{o}
	if err = s.populateItems(ctx, orders); err != nil {
		return OrderDetail{}, err
	}
	return orders[0], nil
}

func (s *Store) populateItems(ctx context.Context, orders []OrderDetail) error {
	if len(orders) == 0 {
		return nil
	}
	orderIDs := make([]string, len(orders))
	orderMap := make(map[string]*OrderDetail, len(orders))
	for i := range orders {
		orderIDs[i] = orders[i].ID
		orderMap[orders[i].ID] = &orders[i]
		orders[i].Items = []OrderItemDetail{}
	}

	rows, err := s.db.Query(ctx, `SELECT oi.id::text, oi.order_id::text, COALESCE(oi.menu_id::text, ''),
		oi.menu_name_snapshot, oi.sku_snapshot, COALESCE(mc.name, ''),
		oi.quantity, oi.unit_price_amount, oi.line_total_amount, COALESCE(oi.notes, '')
		FROM order_items oi
		LEFT JOIN menus m ON m.id = oi.menu_id
		LEFT JOIN menu_categories mc ON mc.id = m.category_id
		WHERE oi.order_id = ANY($1)
		ORDER BY oi.created_at ASC, oi.id ASC`, orderIDs)
	if err != nil {
		return err
	}
	defer rows.Close()

	var itemIDs []string
	itemMap := make(map[string]*OrderItemDetail)

	for rows.Next() {
		var it OrderItemDetail
		var orderID string
		if err = rows.Scan(&it.ID, &orderID, &it.MenuID, &it.Name, &it.SKU, &it.CategoryName, &it.Quantity, &it.UnitPriceAmount, &it.LineTotalAmount, &it.Notes); err != nil {
			return err
		}
		it.Modifiers = []ModifierSnapshot{}
		if ord, ok := orderMap[orderID]; ok {
			ord.Items = append(ord.Items, it)
			itemIDs = append(itemIDs, it.ID)
			itemMap[it.ID] = &ord.Items[len(ord.Items)-1]
		}
	}
	if err = rows.Err(); err != nil {
		return err
	}

	if len(itemIDs) == 0 {
		return nil
	}

	modRows, err := s.db.Query(ctx, `SELECT id::text, order_item_id::text, name_snapshot, price_delta_amount, quantity
		FROM order_item_modifiers
		WHERE order_item_id = ANY($1)
		ORDER BY created_at ASC, id ASC`, itemIDs)
	if err != nil {
		return err
	}
	defer modRows.Close()

	for modRows.Next() {
		var mod ModifierSnapshot
		var itemID string
		if err = modRows.Scan(&mod.ID, &itemID, &mod.Name, &mod.PriceDeltaAmount, &mod.Quantity); err != nil {
			return err
		}
		if it, ok := itemMap[itemID]; ok {
			it.Modifiers = append(it.Modifiers, mod)
		}
	}
	return modRows.Err()
}

func (s *Store) CreateWeb(ctx context.Context, in PublicOrderCreateInput, key, hash, requestID string) (PublicOrderResponse, bool, error) {
	tx, err := s.db.BeginTx(ctx, dbx.TxOptions{})
	if err != nil {
		return PublicOrderResponse{}, false, err
	}
	defer tx.Rollback(ctx)

	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, "CUSTOMER_WEB:"+key); err != nil {
		return PublicOrderResponse{}, false, err
	}

	var existing PublicOrderResponse
	var storedHash string
	var discName sql.NullString
	err = tx.QueryRow(ctx, `SELECT order_number, COALESCE(public_tracking_token, ''), status, subtotal_amount, discount_amount, discount_name_snapshot, total_amount, created_at, request_hash
		FROM orders
		WHERE source = 'CUSTOMER_WEB' AND idempotency_key = $1`, key).Scan(
		&existing.OrderNumber, &existing.PublicTrackingToken, &existing.Status, &existing.SubtotalAmount, &existing.DiscountAmount, &discName, &existing.TotalAmount, &existing.CreatedAt, &storedHash,
	)
	if discName.Valid {
		existing.DiscountName = discName.String
	}
	if err == nil {
		if storedHash != hash {
			return PublicOrderResponse{}, false, ErrIdempotencyConflict
		}
		return existing, false, nil
	} else if !errors.Is(err, sql.ErrNoRows) {
		return PublicOrderResponse{}, false, err
	}

	items := make([]Item, 0, len(in.Items))
	var total int64
	for _, requested := range in.Items {
		menu, err := loadMenu(ctx, tx, requested.MenuID)
		if err != nil {
			return PublicOrderResponse{}, false, err
		}
		unit, err := catalog.Price(menu, requested.Selections)
		if err != nil {
			return PublicOrderResponse{}, false, err
		}
		if unit > (1<<63-1)/int64(requested.Quantity) {
			return PublicOrderResponse{}, false, ErrInvalidInput
		}
		line := unit * int64(requested.Quantity)
		if total > 1<<63-1-line {
			return PublicOrderResponse{}, false, ErrInvalidInput
		}
		total += line
		items = append(items, Item{
			ID:              customer.NewID(),
			MenuID:          menu.ID,
			Name:            menu.Name,
			SKU:             menu.SKU,
			UnitPriceAmount: unit,
			Quantity:        requested.Quantity,
			LineTotalAmount: line,
		})
	}

	var customerID string
	_, err = tx.Exec(ctx, `INSERT INTO customers (id, phone_e164, display_name, create_idempotency_key)
		VALUES ($1, $2, $3, $4)
		ON DUPLICATE KEY UPDATE display_name = VALUES(display_name)`, customer.NewID(), in.CustomerPhone, in.CustomerName, "cust-"+in.CustomerPhone)
	if err == nil {
		err = tx.QueryRow(ctx, `SELECT id FROM customers WHERE phone_e164=$1`, in.CustomerPhone).Scan(&customerID)
	}
	if err != nil {
		return PublicOrderResponse{}, false, err
	}

	bID, bCode, _, _ := resolveBranchForOrder(ctx, tx, in.BranchID)

	subtotal := total
	var discountAmount int64
	var discountIDRef any
	var discountNameRef any
	var discountNameStr string

	if strings.TrimSpace(in.DiscountID) != "" {
		disc, err := loadDiscountForOrder(ctx, tx, strings.TrimSpace(in.DiscountID))
		if err != nil {
			return PublicOrderResponse{}, false, fmt.Errorf("%w: %s", ErrInvalidInput, err.Error())
		}
		calcItems := make([]discount.ItemForDiscount, len(items))
		for i, it := range items {
			calcItems[i] = discount.ItemForDiscount{
				MenuID:    it.MenuID,
				UnitPrice: it.UnitPriceAmount,
				Quantity:  it.Quantity,
				LineTotal: it.LineTotalAmount,
			}
		}
		calcRes := discount.Calculate(disc, discount.CalculationInput{
			Channel:        "CUSTOMER_WEB",
			BranchID:       bID,
			SubtotalAmount: subtotal,
			Items:          calcItems,
			DiscountID:     disc.ID,
		})
		if !calcRes.Eligible {
			return PublicOrderResponse{}, false, fmt.Errorf("%w: %s", ErrInvalidInput, calcRes.IneligibleReason)
		}
		discountAmount = calcRes.DiscountAmount
		discountIDRef = disc.ID
		discountNameRef = disc.Name
		discountNameStr = disc.Name
		total = calcRes.FinalTotalAmount
	}

	orderID := customer.NewID()
	orderNumber, err := nextDailyOrderNumber(ctx, tx, bID, bCode)
	if err != nil {
		return PublicOrderResponse{}, false, err
	}
	trackingToken := "trk_" + strings.ToLower(strings.ReplaceAll(customer.NewID(), "-", "")+strings.ReplaceAll(customer.NewID(), "-", "")[:8])

	res := PublicOrderResponse{
		OrderNumber:         orderNumber,
		PublicTrackingToken: trackingToken,
		Status:              "PENDING",
		SubtotalAmount:      subtotal,
		DiscountAmount:      discountAmount,
		DiscountName:        discountNameStr,
		TotalAmount:         total,
	}

	err = tx.QueryRow(ctx, `INSERT INTO orders (id, order_number, customer_id, branch_id, source, fulfillment, status, customer_name_snapshot, customer_phone_snapshot, notes, subtotal_amount, discount_amount, discount_id, discount_name_snapshot, total_amount, idempotency_key, version, request_hash, public_tracking_token)
		VALUES ($1, $2, $3, $4::uuid, 'CUSTOMER_WEB', 'PICKUP', 'PENDING', $5, $6, NULLIF($7, ''), $8, $9, $10, $11, $12, $13, 1, $14, $15)
		RETURNING created_at`, orderID, orderNumber, customerID, bID, in.CustomerName, in.CustomerPhone, in.Notes, subtotal, discountAmount, discountIDRef, discountNameRef, total, key, hash, trackingToken).Scan(&res.CreatedAt)
	if err != nil {
		var dbErr *mysql.MySQLError
		if errors.As(err, &dbErr) && dbErr.Number == 1062 {
			return PublicOrderResponse{}, false, ErrIdempotencyConflict
		}
		return PublicOrderResponse{}, false, err
	}

	for i, requested := range in.Items {
		item := items[i]
		_, err = tx.Exec(ctx, `INSERT INTO order_items (id, order_id, menu_id, menu_name_snapshot, sku_snapshot, unit_price_amount, quantity, line_total_amount, notes)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULLIF($9, ''))`,
			item.ID, orderID, item.MenuID, item.Name, item.SKU, item.UnitPriceAmount, item.Quantity, item.LineTotalAmount, requested.Notes)
		if err != nil {
			return PublicOrderResponse{}, false, err
		}

		menu, _ := loadMenu(ctx, tx, item.MenuID)
		if err = insertOrderItemModifiers(ctx, tx, item.ID, menu, requested.Selections); err != nil {
			return PublicOrderResponse{}, false, err
		}
	}

	metadata, _ := json.Marshal(map[string]any{
		"order_id":       orderID,
		"order_number":   orderNumber,
		"branch_id":      bID,
		"source":         "CUSTOMER_WEB",
		"status":         "PENDING",
		"customer_name":  in.CustomerName,
		"customer_phone": in.CustomerPhone,
		"total_amount":   total,
		"version":        1,
	})
	auditMeta := SanitizeAuditMetadata(map[string]any{
		"order_id":       orderID,
		"order_number":   orderNumber,
		"branch_id":      bID,
		"source":         "CUSTOMER_WEB",
		"status":         "PENDING",
		"customer_name":  in.CustomerName,
		"customer_phone": in.CustomerPhone,
		"total_amount":   total,
		"version":        1,
	})

	statements := []struct {
		q    string
		args []any
	}{
		{`INSERT INTO order_status_history (id, order_id, to_status, order_version, actor_type, actor_id, request_id) VALUES ($1, $2, 'PENDING', 1, 'CUSTOMER', $3, $4)`, []any{customer.NewID(), orderID, customerID, requestID}},
		{`INSERT INTO audit_logs (id, aggregate_type, aggregate_id, action, actor_type, actor_id, request_id, metadata_redacted) VALUES ($1, 'ORDER', $2, 'ORDER_CREATED', 'CUSTOMER', $3, $4, $5)`, []any{customer.NewID(), orderID, customerID, requestID, auditMeta}},
		{`INSERT INTO outbox_events (id, aggregate_type, aggregate_id, event_type, payload, deduplication_key) VALUES ($1, 'ORDER', $2, 'ORDER_CREATED', $3, $4)`, []any{customer.NewID(), orderID, metadata, "order-created:" + orderID}},
	}
	for _, st := range statements {
		if _, err = tx.Exec(ctx, st.q, st.args...); err != nil {
			return PublicOrderResponse{}, false, err
		}
	}

	if err = tx.Commit(ctx); err != nil {
		return PublicOrderResponse{}, false, err
	}
	s.notifyOutbox()
	return res, true, nil
}

func (s *Store) CreateWhatsApp(ctx context.Context, in WhatsAppOrderCreateInput, key, hash, requestID string) (WhatsAppOrderResponse, bool, error) {
	tx, err := s.db.BeginTx(ctx, dbx.TxOptions{})
	if err != nil {
		return WhatsAppOrderResponse{}, false, err
	}
	defer tx.Rollback(ctx)

	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, "WHATSAPP:"+key); err != nil {
		return WhatsAppOrderResponse{}, false, err
	}

	var existing WhatsAppOrderResponse
	var storedHash string
	var discName sql.NullString
	err = tx.QueryRow(ctx, `SELECT id::text, order_number, COALESCE(public_tracking_token, ''), status, subtotal_amount, discount_amount, discount_name_snapshot, total_amount, created_at, request_hash
		FROM orders
		WHERE source = 'WHATSAPP' AND idempotency_key = $1`, key).Scan(
		&existing.ID, &existing.OrderNumber, &existing.PublicTrackingToken, &existing.Status, &existing.SubtotalAmount, &existing.DiscountAmount, &discName, &existing.TotalAmount, &existing.CreatedAt, &storedHash,
	)
	if discName.Valid {
		existing.DiscountName = discName.String
	}
	if err == nil {
		if storedHash != hash {
			return WhatsAppOrderResponse{}, false, ErrIdempotencyConflict
		}
		return existing, false, nil
	} else if !errors.Is(err, sql.ErrNoRows) {
		return WhatsAppOrderResponse{}, false, err
	}

	items := make([]Item, 0, len(in.Items))
	var total int64
	for _, requested := range in.Items {
		menu, err := loadMenu(ctx, tx, requested.MenuID)
		if err != nil {
			return WhatsAppOrderResponse{}, false, err
		}
		unit, err := catalog.Price(menu, requested.Selections)
		if err != nil {
			return WhatsAppOrderResponse{}, false, err
		}
		if unit > (1<<63-1)/int64(requested.Quantity) {
			return WhatsAppOrderResponse{}, false, ErrInvalidInput
		}
		line := unit * int64(requested.Quantity)
		if total > 1<<63-1-line {
			return WhatsAppOrderResponse{}, false, ErrInvalidInput
		}
		total += line
		items = append(items, Item{
			ID:              customer.NewID(),
			MenuID:          menu.ID,
			Name:            menu.Name,
			SKU:             menu.SKU,
			UnitPriceAmount: unit,
			Quantity:        requested.Quantity,
			LineTotalAmount: line,
		})
	}

	custName := strings.TrimSpace(in.CustomerName)
	if custName == "" {
		custName = "Pelanggan WhatsApp"
	}

	var customerID string
	_, err = tx.Exec(ctx, `INSERT INTO customers (id, phone_e164, display_name, create_idempotency_key)
		VALUES ($1, $2, $3, $4)
		ON DUPLICATE KEY UPDATE display_name = VALUES(display_name)`, customer.NewID(), in.CustomerPhone, custName, "cust-"+in.CustomerPhone)
	if err == nil {
		err = tx.QueryRow(ctx, `SELECT id FROM customers WHERE phone_e164=$1`, in.CustomerPhone).Scan(&customerID)
	}
	if err != nil {
		return WhatsAppOrderResponse{}, false, err
	}

	bID, bCode, _, _ := resolveBranchForOrder(ctx, tx, in.BranchID)

	subtotal := total
	var discountAmount int64
	var discountIDRef any
	var discountNameRef any
	var discountNameStr string

	if strings.TrimSpace(in.DiscountID) != "" {
		disc, err := loadDiscountForOrder(ctx, tx, strings.TrimSpace(in.DiscountID))
		if err != nil {
			return WhatsAppOrderResponse{}, false, fmt.Errorf("%w: %s", ErrInvalidInput, err.Error())
		}
		calcItems := make([]discount.ItemForDiscount, len(items))
		for i, it := range items {
			calcItems[i] = discount.ItemForDiscount{
				MenuID:    it.MenuID,
				UnitPrice: it.UnitPriceAmount,
				Quantity:  it.Quantity,
				LineTotal: it.LineTotalAmount,
			}
		}
		calcRes := discount.Calculate(disc, discount.CalculationInput{
			Channel:        "WHATSAPP",
			BranchID:       bID,
			SubtotalAmount: subtotal,
			Items:          calcItems,
			DiscountID:     disc.ID,
		})
		if !calcRes.Eligible {
			return WhatsAppOrderResponse{}, false, fmt.Errorf("%w: %s", ErrInvalidInput, calcRes.IneligibleReason)
		}
		discountAmount = calcRes.DiscountAmount
		discountIDRef = disc.ID
		discountNameRef = disc.Name
		discountNameStr = disc.Name
		total = calcRes.FinalTotalAmount
	}

	orderID := customer.NewID()
	orderNumber, err := nextDailyOrderNumber(ctx, tx, bID, bCode)
	if err != nil {
		return WhatsAppOrderResponse{}, false, err
	}
	trackingToken := "trk_" + strings.ToLower(strings.ReplaceAll(customer.NewID(), "-", "")+strings.ReplaceAll(customer.NewID(), "-", "")[:8])

	res := WhatsAppOrderResponse{
		ID:                  orderID,
		OrderNumber:         orderNumber,
		PublicTrackingToken: trackingToken,
		Status:              "PENDING",
		SubtotalAmount:      subtotal,
		DiscountAmount:      discountAmount,
		DiscountName:        discountNameStr,
		TotalAmount:         total,
	}

	err = tx.QueryRow(ctx, `INSERT INTO orders (id, order_number, customer_id, branch_id, source, fulfillment, status, customer_name_snapshot, customer_phone_snapshot, notes, subtotal_amount, discount_amount, discount_id, discount_name_snapshot, total_amount, idempotency_key, version, request_hash, public_tracking_token)
		VALUES ($1, $2, $3, $4::uuid, 'WHATSAPP', 'PICKUP', 'PENDING', $5, $6, NULLIF($7, ''), $8, $9, $10, $11, $12, $13, 1, $14, $15)
		RETURNING created_at`, orderID, orderNumber, customerID, bID, custName, in.CustomerPhone, in.Notes, subtotal, discountAmount, discountIDRef, discountNameRef, total, key, hash, trackingToken).Scan(&res.CreatedAt)
	if err != nil {
		var dbErr *mysql.MySQLError
		if errors.As(err, &dbErr) && dbErr.Number == 1062 {
			return WhatsAppOrderResponse{}, false, ErrIdempotencyConflict
		}
		return WhatsAppOrderResponse{}, false, err
	}

	for i, requested := range in.Items {
		item := items[i]
		_, err = tx.Exec(ctx, `INSERT INTO order_items (id, order_id, menu_id, menu_name_snapshot, sku_snapshot, unit_price_amount, quantity, line_total_amount, notes)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULLIF($9, ''))`,
			item.ID, orderID, item.MenuID, item.Name, item.SKU, item.UnitPriceAmount, item.Quantity, item.LineTotalAmount, requested.Notes)
		if err != nil {
			return WhatsAppOrderResponse{}, false, err
		}

		menu, _ := loadMenu(ctx, tx, item.MenuID)
		if err = insertOrderItemModifiers(ctx, tx, item.ID, menu, requested.Selections); err != nil {
			return WhatsAppOrderResponse{}, false, err
		}
	}

	metadata, _ := json.Marshal(map[string]any{
		"order_id":       orderID,
		"order_number":   orderNumber,
		"branch_id":      bID,
		"source":         "WHATSAPP",
		"status":         "PENDING",
		"customer_name":  custName,
		"customer_phone": in.CustomerPhone,
		"total_amount":   total,
		"version":        1,
	})
	auditMeta := SanitizeAuditMetadata(map[string]any{
		"order_id":       orderID,
		"order_number":   orderNumber,
		"branch_id":      bID,
		"source":         "WHATSAPP",
		"status":         "PENDING",
		"customer_name":  custName,
		"customer_phone": in.CustomerPhone,
		"total_amount":   total,
		"version":        1,
	})

	statements := []struct {
		q    string
		args []any
	}{
		{`INSERT INTO order_status_history (id, order_id, to_status, order_version, actor_type, actor_id, request_id) VALUES ($1, $2, 'PENDING', 1, 'AGENT', $3, $4)`, []any{customer.NewID(), orderID, "AGENT", requestID}},
		{`INSERT INTO audit_logs (id, aggregate_type, aggregate_id, action, actor_type, actor_id, request_id, metadata_redacted) VALUES ($1, 'ORDER', $2, 'ORDER_CREATED', 'AGENT', $3, $4, $5)`, []any{customer.NewID(), orderID, "AGENT", requestID, auditMeta}},
		{`INSERT INTO outbox_events (id, aggregate_type, aggregate_id, event_type, payload, deduplication_key) VALUES ($1, 'ORDER', $2, 'ORDER_CREATED', $3, $4)`, []any{customer.NewID(), orderID, metadata, "order-created:" + orderID}},
	}
	for _, st := range statements {
		if _, err = tx.Exec(ctx, st.q, st.args...); err != nil {
			return WhatsAppOrderResponse{}, false, err
		}
	}

	if err = tx.Commit(ctx); err != nil {
		return WhatsAppOrderResponse{}, false, err
	}
	s.notifyOutbox()
	return res, true, nil
}

func (s *Store) PreviewWeb(ctx context.Context, items []ItemInput) (PreviewResponse, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return PreviewResponse{}, err
	}
	defer tx.Rollback(ctx)

	var total int64
	previewItems := make([]PreviewItem, 0, len(items))

	for _, requested := range items {
		menu, err := loadMenu(ctx, tx, requested.MenuID)
		if err != nil {
			return PreviewResponse{}, err
		}
		unit, err := catalog.Price(menu, requested.Selections)
		if err != nil {
			return PreviewResponse{}, err
		}
		if unit > (1<<63-1)/int64(requested.Quantity) {
			return PreviewResponse{}, ErrInvalidInput
		}
		line := unit * int64(requested.Quantity)
		if total > 1<<63-1-line {
			return PreviewResponse{}, ErrInvalidInput
		}
		total += line

		options := map[string]catalog.Option{}
		for _, g := range menu.Groups {
			for _, op := range g.Options {
				options[op.ID] = op
			}
		}
		var mods []ModifierSnapshot
		for optionID, quantity := range selectedOptionCounts(requested.Selections) {
			if op, ok := options[optionID]; ok {
				mods = append(mods, ModifierSnapshot{
					ID:               op.ID,
					Name:             op.Name,
					PriceDeltaAmount: op.PriceDeltaAmount,
					Quantity:         quantity,
				})
			}
		}

		previewItems = append(previewItems, PreviewItem{
			MenuID:          menu.ID,
			Name:            menu.Name,
			Quantity:        requested.Quantity,
			UnitPriceAmount: unit,
			LineTotalAmount: line,
			Modifiers:       mods,
		})
	}

	return PreviewResponse{
		SubtotalAmount: total,
		TotalAmount:    total,
		Items:          previewItems,
	}, nil
}

func (s *Store) GetByPublicToken(ctx context.Context, token string) (PublicTrackingDetail, error) {
	token = strings.TrimSpace(token)
	if token == "" {
		return PublicTrackingDetail{}, ErrNotFound
	}

	var o OrderDetail
	var discName sql.NullString
	err := s.db.QueryRow(ctx, `SELECT id::text, order_number, source, status, customer_name_snapshot, subtotal_amount, discount_amount, discount_name_snapshot, total_amount, version, created_at, updated_at
		FROM orders
		WHERE public_tracking_token = $1`, token).Scan(
		&o.ID, &o.OrderNumber, &o.Source, &o.Status, &o.CustomerName, &o.SubtotalAmount, &o.DiscountAmount, &discName, &o.TotalAmount, &o.Version, &o.CreatedAt, &o.UpdatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return PublicTrackingDetail{}, ErrNotFound
	}
	if err != nil {
		return PublicTrackingDetail{}, err
	}
	if discName.Valid {
		o.DiscountName = discName.String
	}

	orders := []OrderDetail{o}
	if err = s.populateItems(ctx, orders); err != nil {
		return PublicTrackingDetail{}, err
	}
	o = orders[0]

	return PublicTrackingDetail{
		OrderNumber:    o.OrderNumber,
		Status:         o.Status,
		CustomerName:   o.CustomerName,
		SubtotalAmount: o.SubtotalAmount,
		DiscountAmount: o.DiscountAmount,
		DiscountName:   o.DiscountName,
		TotalAmount:    o.TotalAmount,
		CreatedAt:      o.CreatedAt,
		UpdatedAt:      o.UpdatedAt,
		Items:          o.Items,
	}, nil
}

func (s *Store) GetAuditLogs(ctx context.Context, orderID, actorID, requestID string) ([]AuditLogEntry, error) {
	orderID = strings.TrimSpace(orderID)
	if orderID == "" {
		return nil, ErrNotFound
	}

	var actualID string
	err := s.db.QueryRow(ctx, `SELECT id::text FROM orders WHERE id = $1 OR client_order_id = $1`, orderID).Scan(&actualID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	orderID = actualID

	// Self-audited: record that audit logs were accessed
	_, _ = s.db.Exec(ctx, `INSERT INTO audit_logs (id, aggregate_type, aggregate_id, action, actor_type, actor_id, request_id, metadata_redacted)
		VALUES ($1, 'ORDER', $2, 'AUDIT_LOGS_ACCESSED', 'STAFF', $3, $4, '{}'::jsonb)`,
		customer.NewID(), orderID, actorID, requestID)

	rows, err := s.db.Query(ctx, `SELECT id::text, aggregate_type, aggregate_id::text, action, actor_type, COALESCE(actor_id, ''), request_id, metadata_redacted, created_at
		FROM audit_logs
		WHERE aggregate_type = 'ORDER' AND aggregate_id = $1
		ORDER BY created_at ASC, id ASC`, orderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var entries []AuditLogEntry
	for rows.Next() {
		var e AuditLogEntry
		if err = rows.Scan(&e.ID, &e.AggregateType, &e.AggregateID, &e.Action, &e.ActorType, &e.ActorID, &e.RequestID, &e.Metadata, &e.CreatedAt); err != nil {
			return nil, err
		}
		entries = append(entries, e)
	}
	if err = rows.Err(); err != nil {
		return nil, err
	}
	if entries == nil {
		entries = []AuditLogEntry{}
	}
	return entries, nil
}
