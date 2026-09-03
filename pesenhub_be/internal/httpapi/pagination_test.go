package httpapi

import (
	"encoding/base64"
	"errors"
	"net/url"
	"testing"
)

func TestParsePaginationDefaults(t *testing.T) {
	p, err := ParsePagination(url.Values{}, map[string]struct{}{"created_at": {}}, "created_at")
	if err != nil || p.Size != 20 || p.Sort != "created_at" || p.Order != "asc" {
		t.Fatalf("pagination = %#v, err = %v", p, err)
	}
}

func TestParsePaginationValid(t *testing.T) {
	cursor := base64.RawURLEncoding.EncodeToString([]byte("opaque:test"))
	p, err := ParsePagination(url.Values{"page[size]": {"100"}, "page[cursor]": {cursor}, "sort": {"-created_at"}}, map[string]struct{}{"created_at": {}}, "created_at")
	if err != nil || p.Size != 100 || p.Cursor != cursor || p.Sort != "created_at" || p.Order != "desc" {
		t.Fatalf("pagination = %#v, err = %v", p, err)
	}
}

func TestParsePaginationRejectsInvalidInput(t *testing.T) {
	tests := []url.Values{{"page[size]": {"0"}}, {"page[size]": {"101"}}, {"page[size]": {"many"}}, {"page[cursor]": {"not+base64"}}, {"sort": {"private_column"}}}
	for _, query := range tests {
		if _, err := ParsePagination(query, map[string]struct{}{"created_at": {}}, "created_at"); !errors.Is(err, ErrInvalidPagination) {
			t.Fatalf("query %v: err = %v", query, err)
		}
	}
}
