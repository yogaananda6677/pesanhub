package hermes

import (
	"fmt"
	"math"
	"strings"
)

// DefaultConfidenceThreshold is the minimum overall confidence required before treating a draft as unambiguous.
const DefaultConfidenceThreshold = 0.75

// Uncertainty keywords in Indonesian and English that reduce confidence if present in customer notes/text.
var uncertaintyKeywords = []string{
	"mungkin",
	"kayaknya",
	"atau",
	"kalo ada",
	"kalau ada",
	"terserah",
	"kira kira",
	"kira-kira",
	"maybe",
	"if available",
	"or whatever",
}

// ConfidenceEvaluator evaluates confidence scores and determines whether a draft is ambiguous.
type ConfidenceEvaluator struct {
	threshold float64
}

// NewConfidenceEvaluator creates a new ConfidenceEvaluator with the given threshold.
// If threshold <= 0, DefaultConfidenceThreshold is used.
func NewConfidenceEvaluator(threshold float64) *ConfidenceEvaluator {
	if threshold <= 0 {
		threshold = DefaultConfidenceThreshold
	}
	return &ConfidenceEvaluator{threshold: threshold}
}

// Evaluate analyzes the raw LLM output, resolution results, and notes to compute final confidence and ambiguity.
func (e *ConfidenceEvaluator) Evaluate(raw *RawExtractedOrder, resolveResult *ResolveResult) (float64, bool, []string) {
	reasons := make([]string, 0)
	isAmbiguous := false

	// Incorporate existing ambiguities from resolver
	if resolveResult != nil && resolveResult.IsAmbiguous {
		isAmbiguous = true
		reasons = append(reasons, resolveResult.AmbiguityReasons...)
	}

	if resolveResult == nil || len(resolveResult.Items) == 0 {
		reasons = append(reasons, "no_valid_items_resolved")
		return 0.0, true, dedupeStrings(reasons)
	}

	// Calculate base confidence from items and raw order
	var totalItemConf float64
	for _, it := range resolveResult.Items {
		conf := it.Confidence
		if conf <= 0 {
			conf = 0.5
		}
		if conf > 1.0 {
			conf = 1.0
		}
		if conf < e.threshold {
			isAmbiguous = true
			reasons = append(reasons, fmt.Sprintf("low_item_confidence:%s:%.2f", it.Name, conf))
		}
		totalItemConf += conf
	}

	avgItemConf := totalItemConf / float64(len(resolveResult.Items))

	orderConf := raw.Confidence
	if orderConf <= 0 {
		orderConf = avgItemConf
	}
	if orderConf > 1.0 {
		orderConf = 1.0
	}

	// Weighted combined confidence: 60% item average, 40% order level
	overallScore := (0.6 * avgItemConf) + (0.4 * orderConf)

	// Check notes for uncertainty
	combinedNotes := strings.ToLower(raw.Notes)
	for _, it := range raw.Items {
		combinedNotes += " " + strings.ToLower(it.Notes)
	}

	for _, kw := range uncertaintyKeywords {
		if strings.Contains(combinedNotes, kw) {
			overallScore -= 0.15
			isAmbiguous = true
			reasons = append(reasons, fmt.Sprintf("uncertainty_detected:%s", kw))
			break
		}
	}

	// Round to 2 decimal places
	overallScore = math.Round(math.Max(0.0, math.Min(1.0, overallScore))*100) / 100

	if overallScore < e.threshold {
		isAmbiguous = true
		reasons = append(reasons, fmt.Sprintf("confidence_below_threshold:%.2f<%.2f", overallScore, e.threshold))
	}

	return overallScore, isAmbiguous, dedupeStrings(reasons)
}

func dedupeStrings(input []string) []string {
	seen := make(map[string]struct{}, len(input))
	result := make([]string, 0, len(input))
	for _, s := range input {
		if _, ok := seen[s]; !ok {
			seen[s] = struct{}{}
			result = append(result, s)
		}
	}
	return result
}
