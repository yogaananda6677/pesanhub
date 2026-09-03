package order

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"pesenhub/backend/internal/catalog"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/domain"
)

type Store struct{ db *pgxpool.Pool }

func NewStore(db *pgxpool.Pool) *Store { return &Store{db: db} }

func (s *Store) Transition(ctx context.Context, orderID string, in TransitionInput, key, hash, actorID, roleRequest string) (StatusResult, bool, error) {
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return StatusResult{}, false, err
	}
	defer tx.Rollback(ctx)
	parts := strings.SplitN(roleRequest, "|", 2)
	role, requestID := parts[0], "unknown"
	if len(parts) == 2 && parts[1] != "" {
		requestID = parts[1]
	}
	if role != "STAFF" {
		return StatusResult{}, false, customer.ErrUnauthorized
	}
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
	if !errors.Is(err, pgx.ErrNoRows) {
		return StatusResult{}, false, err
	}
	var current string
	var version int64
	err = tx.QueryRow(ctx, `SELECT status,version FROM orders WHERE id=$1 FOR UPDATE`, orderID).Scan(&current, &version)
	if errors.Is(err, pgx.ErrNoRows) {
		return StatusResult{}, false, ErrNotFound
	}
	if err != nil {
		return StatusResult{}, false, err
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
	metadata, _ := json.Marshal(map[string]any{"from_status": current, "to_status": result.Status, "version": result.Version})
	if _, err = tx.Exec(ctx, `INSERT INTO order_status_history (id,order_id,from_status,to_status,order_version,actor_type,actor_id,reason_code,request_id,idempotency_key,request_hash) VALUES ($1,$2,$3,$4,$5,'STAFF',$6,NULLIF($7,''),$8,$9,$10)`, customer.NewID(), orderID, current, result.Status, result.Version, actorID, in.ReasonCode, requestID, key, hash); err != nil {
		return StatusResult{}, false, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO audit_logs (id,aggregate_type,aggregate_id,action,actor_type,actor_id,request_id,metadata_redacted) VALUES ($1,'ORDER',$2,'ORDER_STATUS_CHANGED','STAFF',$3,$4,$5)`, customer.NewID(), orderID, actorID, requestID, metadata); err != nil {
		return StatusResult{}, false, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO outbox_events (id,aggregate_type,aggregate_id,event_type,payload,deduplication_key) VALUES ($1,'ORDER',$2,'ORDER_STATUS_CHANGED',$3,$4)`, customer.NewID(), orderID, metadata, "order-status:"+orderID+":"+fmt.Sprint(result.Version)); err != nil {
		return StatusResult{}, false, err
	}
	if err = tx.Commit(ctx); err != nil {
		return StatusResult{}, false, err
	}
	return result, true, nil
}

func (s *Store) Create(ctx context.Context, in CreateInput, key, hash, actorRequest string) (Order, bool, error) {
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Order{}, false, err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, "CASHIER_MANUAL:"+key); err != nil {
		return Order{}, false, err
	}
	if existing, found, err := loadExisting(ctx, tx, key, hash); found || err != nil {
		return existing, false, err
	}

	items := make([]Item, 0, len(in.Items))
	var total int64
	for _, requested := range in.Items {
		menu, err := loadMenu(ctx, tx, requested.MenuID)
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
	parts := strings.SplitN(actorRequest, "|", 2)
	actorID, requestID := parts[0], "unknown"
	if len(parts) == 2 && parts[1] != "" {
		requestID = parts[1]
	}
	o := Order{ID: customer.NewID(), OrderNumber: "ORD-" + strings.ToUpper(strings.ReplaceAll(customer.NewID(), "-", "")[:16]), ClientOrderID: in.ClientOrderID, Source: "CASHIER_MANUAL", Status: "PENDING", TotalAmount: total, Version: 1, Items: items}
	var customerRef any
	if in.CustomerID != "" {
		customerRef = in.CustomerID
	}
	err = tx.QueryRow(ctx, `INSERT INTO orders (id,order_number,customer_id,source,status,customer_name_snapshot,customer_phone_snapshot,notes,subtotal_amount,total_amount,idempotency_key,client_order_id,request_hash) VALUES ($1,$2,$3,'CASHIER_MANUAL','PENDING',$4,NULLIF($5,''),NULLIF($6,''),$7,$7,$8,$9,$10) RETURNING created_at`, o.ID, o.OrderNumber, customerRef, in.CustomerName, in.CustomerPhone, in.Notes, total, key, in.ClientOrderID, hash).Scan(&o.CreatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
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
		options := map[string]catalog.Option{}
		for _, g := range menu.Groups {
			for _, op := range g.Options {
				options[op.ID] = op
			}
		}
		for _, sel := range requested.Selections {
			for _, optionID := range sel.OptionIDs {
				op := options[optionID]
				_, err = tx.Exec(ctx, `INSERT INTO order_item_modifiers (id,order_item_id,modifier_option_id,name_snapshot,price_delta_amount) VALUES ($1,$2,$3,$4,$5)`, customer.NewID(), item.ID, op.ID, op.Name, op.PriceDeltaAmount)
				if err != nil {
					return Order{}, false, err
				}
			}
		}
	}
	metadata, _ := json.Marshal(map[string]any{"source": "CASHIER_MANUAL", "total_amount": total})
	statements := []struct {
		q    string
		args []any
	}{
		{`INSERT INTO order_status_history (id,order_id,to_status,order_version,actor_type,actor_id,request_id) VALUES ($1,$2,'PENDING',1,'STAFF',$3,$4)`, []any{customer.NewID(), o.ID, actorID, requestID}},
		{`INSERT INTO audit_logs (id,aggregate_type,aggregate_id,action,actor_type,actor_id,request_id,metadata_redacted) VALUES ($1,'ORDER',$2,'ORDER_CREATED','STAFF',$3,$4,$5)`, []any{customer.NewID(), o.ID, actorID, requestID, metadata}},
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
	return o, true, nil
}

func loadExisting(ctx context.Context, tx pgx.Tx, key, hash string) (Order, bool, error) {
	var o Order
	var stored string
	err := tx.QueryRow(ctx, `SELECT id::text,order_number,client_order_id::text,source,status,total_amount,version,created_at,request_hash FROM orders WHERE source='CASHIER_MANUAL' AND idempotency_key=$1`, key).Scan(&o.ID, &o.OrderNumber, &o.ClientOrderID, &o.Source, &o.Status, &o.TotalAmount, &o.Version, &o.CreatedAt, &stored)
	if errors.Is(err, pgx.ErrNoRows) {
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

func loadMenu(ctx context.Context, tx pgx.Tx, id string) (catalog.Menu, error) {
	var m catalog.Menu
	err := tx.QueryRow(ctx, `SELECT id::text,category_id::text,sku,name,price_amount,is_available,version,sort_order FROM menus WHERE id=$1 FOR SHARE`, id).Scan(&m.ID, &m.CategoryID, &m.SKU, &m.Name, &m.PriceAmount, &m.Available, &m.Version, &m.SortOrder)
	if errors.Is(err, pgx.ErrNoRows) {
		return m, &catalog.ValidationError{Field: "menu_id", Err: catalog.ErrUnavailable}
	}
	if err != nil {
		return m, err
	}
	rows, err := tx.Query(ctx, `SELECT g.id::text,g.code,g.name,g.min_select,g.max_select,g.sort_order,g.is_active,o.id::text,o.code,o.name,o.price_delta_amount,o.is_available,o.sort_order FROM modifier_groups g LEFT JOIN modifier_options o ON o.group_id=g.id WHERE g.menu_id=$1 ORDER BY g.sort_order,g.id,o.sort_order,o.id FOR SHARE OF g`, id)
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
