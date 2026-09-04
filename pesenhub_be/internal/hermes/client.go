package hermes

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

var (
	ErrLLMInvalidResponse = errors.New("invalid or unparseable response from LLM")
	ErrLLMUnavailable     = errors.New("LLM service unavailable")
)

// LLMClient defines the interface to interact with an LLM backend for order extraction.
type LLMClient interface {
	ExtractOrder(ctx context.Context, systemPrompt, userPrompt string) (*RawExtractedOrder, error)
}

// MockLLMClient provides a deterministic mock implementation of LLMClient for testing.
type MockLLMClient struct {
	Response         *RawExtractedOrder
	RawJSON          string
	Err              error
	CallCount        int
	LastSystemPrompt string
	LastUserPrompt   string
}

func (m *MockLLMClient) ExtractOrder(ctx context.Context, systemPrompt, userPrompt string) (*RawExtractedOrder, error) {
	m.CallCount++
	m.LastSystemPrompt = systemPrompt
	m.LastUserPrompt = userPrompt

	if m.Err != nil {
		return nil, m.Err
	}
	if m.RawJSON != "" {
		cleaned := CleanJSONOutput(m.RawJSON)
		var order RawExtractedOrder
		if err := json.Unmarshal([]byte(cleaned), &order); err != nil {
			return nil, fmt.Errorf("%w: %v", ErrLLMInvalidResponse, err)
		}
		return &order, nil
	}
	if m.Response != nil {
		return m.Response, nil
	}

	return &RawExtractedOrder{
		Items:      []RawExtractedItem{},
		Confidence: 0.0,
	}, nil
}

// CleanJSONOutput removes markdown codeblock delimiters if present.
func CleanJSONOutput(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if strings.HasPrefix(trimmed, "```json") {
		trimmed = strings.TrimPrefix(trimmed, "```json")
		trimmed = strings.TrimSuffix(trimmed, "```")
	} else if strings.HasPrefix(trimmed, "```") {
		trimmed = strings.TrimPrefix(trimmed, "```")
		trimmed = strings.TrimSuffix(trimmed, "```")
	}
	return strings.TrimSpace(trimmed)
}

// HTTPLLMClient is an OpenAI/Ollama compatible chat completion client.
type HTTPLLMClient struct {
	baseURL    string
	apiKey     string
	model      string
	httpClient *http.Client
}

// NewHTTPLLMClient creates a new HTTPLLMClient.
func NewHTTPLLMClient(baseURL, apiKey, model string, timeout time.Duration) *HTTPLLMClient {
	if timeout <= 0 {
		timeout = 15 * time.Second
	}
	if model == "" {
		model = DefaultModelName
	}
	return &HTTPLLMClient{
		baseURL: strings.TrimRight(baseURL, "/"),
		apiKey:  apiKey,
		model:   model,
		httpClient: &http.Client{
			Timeout: timeout,
		},
	}
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type chatCompletionRequest struct {
	Model       string        `json:"model"`
	Messages    []chatMessage `json:"messages"`
	Temperature float64       `json:"temperature"`
}

type chatCompletionChoice struct {
	Message chatMessage `json:"message"`
}

type chatCompletionResponse struct {
	Choices []chatCompletionChoice `json:"choices"`
	Error   *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

// ExtractOrder calls the chat completion endpoint and decodes the JSON order.
func (c *HTTPLLMClient) ExtractOrder(ctx context.Context, systemPrompt, userPrompt string) (*RawExtractedOrder, error) {
	reqBody := chatCompletionRequest{
		Model: c.model,
		Messages: []chatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature: 0.1,
	}

	payloadBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal LLM request: %w", err)
	}

	endpoint := fmt.Sprintf("%s/v1/chat/completions", c.baseURL)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payloadBytes))
	if err != nil {
		return nil, fmt.Errorf("failed to create LLM HTTP request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if c.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.apiKey)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrLLMUnavailable, err)
	}
	defer resp.Body.Close()

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read LLM response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%w: status %d body %s", ErrLLMUnavailable, resp.StatusCode, string(bodyBytes))
	}

	var completionResp chatCompletionResponse
	if err := json.Unmarshal(bodyBytes, &completionResp); err != nil {
		return nil, fmt.Errorf("%w: response format error: %v", ErrLLMInvalidResponse, err)
	}

	if completionResp.Error != nil {
		return nil, fmt.Errorf("%w: provider error: %s", ErrLLMUnavailable, completionResp.Error.Message)
	}

	if len(completionResp.Choices) == 0 {
		return nil, fmt.Errorf("%w: no choices returned", ErrLLMInvalidResponse)
	}

	rawContent := completionResp.Choices[0].Message.Content
	cleanedJSON := CleanJSONOutput(rawContent)

	var extracted RawExtractedOrder
	if err := json.Unmarshal([]byte(cleanedJSON), &extracted); err != nil {
		return nil, fmt.Errorf("%w: failed to unmarshal order JSON: %v, raw: %s", ErrLLMInvalidResponse, err, rawContent)
	}

	return &extracted, nil
}
