package order

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWebStaticAssetsAccessibilityAndResponsive(t *testing.T) {
	// Locate web directory relative to package
	webDir := filepath.Join("..", "..", "web")
	if _, err := os.Stat(webDir); err != nil {
		t.Skip("web directory not found relative to test")
	}

	handler := http.FileServer(http.Dir(webDir))

	// 1. Check index.html
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 for index.html, got %d", w.Code)
	}
	body := w.Body.String()

	// Acceptance criteria: Viewport ponsel tanpa horizontal scroll
	if !strings.Contains(body, `<meta name="viewport" content="width=device-width`) {
		t.Fatal("index.html missing mobile responsive viewport meta tag")
	}

	// Accessibility checks
	if !strings.Contains(body, `role="banner"`) || !strings.Contains(body, `role="main"`) {
		t.Fatal("index.html missing semantic landmark roles")
	}
	if !strings.Contains(body, `aria-live=`) {
		t.Fatal("index.html missing aria-live regions for dynamic validation and status announcements")
	}

	// Web order removal verification: index.html must not contain href="/order/"
	if strings.Contains(body, `href="/order/"`) {
		t.Fatal("index.html should not contain direct links to web order (/order/)")
	}
	// WhatsApp order channel verification
	if !strings.Contains(body, `https://wa.me/6282243509775`) {
		t.Fatal("index.html must provide WhatsApp ordering link")
	}

	// 2. Check style.css
	req = httptest.NewRequest(http.MethodGet, "/style.css", nil)
	w = httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 for style.css, got %d", w.Code)
	}
	css := w.Body.String()
	if !strings.Contains(css, "overflow-x: hidden") {
		t.Fatal("style.css should prevent horizontal scroll")
	}

	// 3. Check app.js
	req = httptest.NewRequest(http.MethodGet, "/app.js", nil)
	w = httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 for app.js, got %d", w.Code)
	}
	js := w.Body.String()
	if !strings.Contains(js, "Idempotency-Key") {
		t.Fatal("app.js must attach Idempotency-Key header for double submit protection")
	}
	if !strings.Contains(js, "loadTracking") {
		t.Fatal("app.js must support tracking view via token")
	}

	// 4. Check landing.js (Interactive category tabs and mobile nav)
	req = httptest.NewRequest(http.MethodGet, "/landing.js", nil)
	w = httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 for landing.js, got %d", w.Code)
	}
	landingJS := w.Body.String()
	if !strings.Contains(landingJS, "menu-category-section") {
		t.Fatal("landing.js must query menu-category-section for menu tab filtering")
	}

	// 5. Check landing.css
	req = httptest.NewRequest(http.MethodGet, "/landing.css", nil)
	w = httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 for landing.css, got %d", w.Code)
	}
	landingCSS := w.Body.String()
	if !strings.Contains(landingCSS, ".btn-whatsapp-subtle") {
		t.Fatal("landing.css must include .btn-whatsapp-subtle styling")
	}
}
