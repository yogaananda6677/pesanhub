package database

import (
	"context"
	"database/sql"
	"fmt"
	"reflect"
	"regexp"
	"strconv"
	"strings"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

type Pool struct{ db *sql.DB }
type Tx struct{ tx *sql.Tx }
type TxOptions struct{}
type Row interface{ Scan(...any) error }
type Rows = sql.Rows
type Result struct{ sql.Result }

func (r Result) RowsAffected() int64 { n, _ := r.Result.RowsAffected(); return n }

var placeholder = regexp.MustCompile(`\$([0-9]+)`)
var anyPlaceholder = regexp.MustCompile(`=\s*ANY\s*\((\$[0-9]+)(?:::[^)]+)?\)`)
var cast = regexp.MustCompile(`::(?:text|uuid|jsonb|timestamptz|double precision)`)
var conflictNothing = regexp.MustCompile(`(?i)ON\s+CONFLICT(?:\s*\([^)]*\))?\s+DO\s+NOTHING`)
var returningClause = regexp.MustCompile(`(?is)\s+RETURNING\s+(.+?)\s*$`)
var mutationTable = regexp.MustCompile(`(?is)^\s*(?:INSERT\s+INTO|UPDATE)\s+([a-zA-Z0-9_]+)`)

type errorRow struct{ err error }

func (r errorRow) Scan(...any) error { return r.err }

func query(q string, args []any) (string, []any) {
	q = anyPlaceholder.ReplaceAllString(q, "IN ($1)")
	q = cast.ReplaceAllString(q, "")
	q = conflictNothing.ReplaceAllString(q, "ON DUPLICATE KEY UPDATE id=id")
	bound := make([]any, 0, len(args))
	q = placeholder.ReplaceAllStringFunc(q, func(token string) string {
		n, err := strconv.Atoi(token[1:])
		if err != nil || n < 1 || n > len(args) {
			return token
		}
		arg := args[n-1]
		v := reflect.ValueOf(arg)
		if v.IsValid() && (v.Kind() == reflect.Slice || v.Kind() == reflect.Array) && v.Type().Elem().Kind() != reflect.Uint8 {
			if v.Len() == 0 {
				return "NULL"
			}
			marks := make([]string, v.Len())
			for i := range marks {
				marks[i] = "?"
				bound = append(bound, v.Index(i).Interface())
			}
			return strings.Join(marks, ",")
		}
		bound = append(bound, arg)
		return "?"
	})
	return q, bound
}

func returningRow(ctx context.Context, exec func(context.Context, string, ...any) (sql.Result, error), row func(context.Context, string, ...any) *sql.Row, q string, args []any) Row {
	match := returningClause.FindStringSubmatch(q)
	table := mutationTable.FindStringSubmatch(q)
	if len(match) != 2 || len(table) != 2 || len(args) == 0 {
		q, args = query(q, args)
		return row(ctx, q, args...)
	}
	q = returningClause.ReplaceAllString(q, "")
	q, bound := query(q, args)
	result, err := exec(ctx, q, bound...)
	if err != nil {
		return errorRow{err}
	}
	affected, err := result.RowsAffected()
	if err != nil || affected == 0 {
		if err == nil {
			err = sql.ErrNoRows
		}
		return errorRow{err}
	}
	columns := cast.ReplaceAllString(strings.ReplaceAll(match[1], "p.", ""), "")
	return row(ctx, "SELECT "+columns+" FROM "+table[1]+" WHERE id = ?", args[0])
}

func Open(ctx context.Context, dsn string) (*Pool, error) {
	db, err := sql.Open("mysql", strings.TrimPrefix(dsn, "mysql://"))
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(1)
	db.SetConnMaxLifetime(time.Hour)
	check, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := db.PingContext(check); err != nil {
		_ = db.Close()
		return nil, err
	}
	return &Pool{db: db}, nil
}

func (p *Pool) Close()                         { _ = p.db.Close() }
func (p *Pool) Ping(ctx context.Context) error { return p.db.PingContext(ctx) }
func (p *Pool) Exec(ctx context.Context, q string, args ...any) (Result, error) {
	q, args = query(q, args)
	r, err := p.db.ExecContext(ctx, q, args...)
	return Result{r}, err
}
func (p *Pool) Query(ctx context.Context, q string, args ...any) (*Rows, error) {
	q, args = query(q, args)
	return p.db.QueryContext(ctx, q, args...)
}
func (p *Pool) QueryRow(ctx context.Context, q string, args ...any) Row {
	return returningRow(ctx, p.db.ExecContext, p.db.QueryRowContext, q, args)
}
func (p *Pool) Begin(ctx context.Context) (*Tx, error) { return p.BeginTx(ctx, TxOptions{}) }
func (p *Pool) BeginTx(ctx context.Context, _ TxOptions) (*Tx, error) {
	tx, err := p.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	return &Tx{tx: tx}, nil
}
func (t *Tx) Exec(ctx context.Context, q string, args ...any) (Result, error) {
	if strings.Contains(q, "pg_advisory_xact_lock") {
		if len(args) != 1 {
			return Result{}, fmt.Errorf("advisory lock expects one key")
		}
		key := fmt.Sprint(args[0])
		if _, err := t.tx.ExecContext(ctx, "INSERT INTO advisory_locks(lock_key) VALUES (?) ON DUPLICATE KEY UPDATE lock_key=VALUES(lock_key)", key); err != nil {
			return Result{}, err
		}
		r, err := t.tx.ExecContext(ctx, "SELECT lock_key FROM advisory_locks WHERE lock_key=? FOR UPDATE", key)
		return Result{r}, err
	}
	q, args = query(q, args)
	r, err := t.tx.ExecContext(ctx, q, args...)
	return Result{r}, err
}
func (t *Tx) Query(ctx context.Context, q string, args ...any) (*Rows, error) {
	q, args = query(q, args)
	return t.tx.QueryContext(ctx, q, args...)
}
func (t *Tx) QueryRow(ctx context.Context, q string, args ...any) Row {
	return returningRow(ctx, t.tx.ExecContext, t.tx.QueryRowContext, q, args)
}
func (t *Tx) Commit(context.Context) error   { return t.tx.Commit() }
func (t *Tx) Rollback(context.Context) error { return t.tx.Rollback() }
