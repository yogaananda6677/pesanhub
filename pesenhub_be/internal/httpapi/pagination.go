package httpapi

import (
	"encoding/base64"
	"errors"
	"net/url"
	"strconv"
	"strings"
)

const (
	DefaultPageSize = 20
	MaxPageSize     = 100
)

var ErrInvalidPagination = errors.New("invalid pagination")

type Pagination struct {
	Size   int
	Cursor string
	Sort   string
	Order  string
}

type PageMeta struct {
	Size       int     `json:"size"`
	NextCursor *string `json:"next_cursor"`
}

// ParsePagination validates the shared collection query. allowedSort contains
// public field names; handlers must translate them to fixed SQL expressions.
func ParsePagination(query url.Values, allowedSort map[string]struct{}, defaultSort string) (Pagination, error) {
	p := Pagination{Size: DefaultPageSize, Cursor: query.Get("page[cursor]"), Sort: defaultSort, Order: "asc"}
	if raw := query.Get("page[size]"); raw != "" {
		size, err := strconv.Atoi(raw)
		if err != nil || size < 1 || size > MaxPageSize {
			return Pagination{}, ErrInvalidPagination
		}
		p.Size = size
	}
	if p.Cursor != "" {
		if _, err := base64.RawURLEncoding.DecodeString(p.Cursor); err != nil {
			return Pagination{}, ErrInvalidPagination
		}
	}
	if raw := query.Get("sort"); raw != "" {
		p.Order = "asc"
		if strings.HasPrefix(raw, "-") {
			p.Order, raw = "desc", strings.TrimPrefix(raw, "-")
		}
		if _, ok := allowedSort[raw]; !ok {
			return Pagination{}, ErrInvalidPagination
		}
		p.Sort = raw
	}
	return p, nil
}
