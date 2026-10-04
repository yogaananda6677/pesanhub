package evaluation

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestEvaluationRatings(t *testing.T) {
	ratings := []string{RatingUnrated, RatingGood, RatingBad, RatingNeedsCorrection}
	if len(ratings) != 4 {
		t.Errorf("expected 4 ratings, got %d", len(ratings))
	}
}

func TestEvaluationHandler_Unauthorized(t *testing.T) {
	h := NewHandler(nil)
	req := httptest.NewRequest("GET", "/api/v1/agent/evaluations", nil)
	rec := httptest.NewRecorder()

	h.List(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Errorf("expected 403 Forbidden without staff header, got %d", rec.Code)
	}
}

func TestEvaluationHandler_DecodeSubmitReview(t *testing.T) {
	body := bytes.NewBufferString(`{"rating":"GOOD","feedback_category":"CORRECT","correction_notes":"Mantap"}`)
	req := httptest.NewRequest("POST", "/api/v1/agent/evaluations/123/review", body)

	var in SubmitReviewInput
	err := decodeJSON(req, &in)
	if err != nil {
		t.Fatalf("unexpected error decoding JSON: %v", err)
	}

	if in.Rating != "GOOD" || in.FeedbackCategory != "CORRECT" || in.CorrectionNotes != "Mantap" {
		t.Errorf("unexpected decoded values: %+v", in)
	}
}
