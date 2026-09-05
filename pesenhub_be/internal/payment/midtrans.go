package payment

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type MidtransGateway interface {
	CreateQRIS(context.Context, string, int64) (QRISCharge, error)
}

type MidtransStatusGateway interface {
	GetStatus(context.Context, string) (MidtransNotification, error)
}

type MidtransClient struct {
	baseURL, serverKey string
	httpClient         *http.Client
}

func NewMidtransClient(baseURL, serverKey string, timeout time.Duration) *MidtransClient {
	return &MidtransClient{baseURL: strings.TrimRight(baseURL, "/"), serverKey: serverKey, httpClient: &http.Client{Timeout: timeout}}
}

func (c *MidtransClient) CreateQRIS(ctx context.Context, orderID string, amount int64) (QRISCharge, error) {
	body, err := json.Marshal(map[string]any{
		"payment_type":        "qris",
		"transaction_details": map[string]any{"order_id": orderID, "gross_amount": amount},
	})
	if err != nil {
		return QRISCharge{}, &ProviderError{Kind: "encoding"}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/v2/charge", bytes.NewReader(body))
	if err != nil {
		return QRISCharge{}, &ProviderError{Kind: "configuration"}
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Content-Type", "application/json")
	req.SetBasicAuth(c.serverKey, "")
	res, err := c.httpClient.Do(req)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) || isTimeout(err) {
			return QRISCharge{}, &ProviderError{Kind: "timeout"}
		}
		return QRISCharge{}, &ProviderError{Kind: "network"}
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		_, _ = io.Copy(io.Discard, io.LimitReader(res.Body, 1<<20))
		kind := "server"
		switch res.StatusCode {
		case http.StatusRequestTimeout:
			kind = "timeout"
		case http.StatusNotAcceptable:
			kind = "duplicate"
		case http.StatusTooManyRequests:
			kind = "rate_limited"
		default:
			if res.StatusCode >= 400 && res.StatusCode < 500 {
				kind = "rejected"
			}
		}
		return QRISCharge{}, &ProviderError{Kind: kind}
	}
	var out struct {
		TransactionID     string `json:"transaction_id"`
		OrderID           string `json:"order_id"`
		TransactionStatus string `json:"transaction_status"`
		PaymentType       string `json:"payment_type"`
		GrossAmount       string `json:"gross_amount"`
		ExpiryTime        string `json:"expiry_time"`
		Actions           []struct {
			Name string `json:"name"`
			URL  string `json:"url"`
		} `json:"actions"`
	}
	decoder := json.NewDecoder(io.LimitReader(res.Body, (1<<20)+1))
	if err := decoder.Decode(&out); err != nil {
		return QRISCharge{}, &ProviderError{Kind: "invalid_response"}
	}
	grossAmount, amountErr := parseIDRAmount(out.GrossAmount)
	if out.TransactionID == "" || out.OrderID != orderID || out.TransactionStatus == "" || out.PaymentType != "qris" || amountErr != nil || grossAmount != amount {
		return QRISCharge{}, &ProviderError{Kind: "invalid_response"}
	}
	charge := QRISCharge{ProviderOrderID: out.OrderID, ProviderReference: out.TransactionID, Status: out.TransactionStatus}
	for _, action := range out.Actions {
		if action.Name == "generate-qr-code" {
			if parsed, parseErr := url.Parse(action.URL); parseErr == nil && parsed.Scheme == "https" && parsed.Host != "" {
				charge.QRCodeURL = action.URL
			}
			break
		}
	}
	if charge.QRCodeURL == "" {
		return QRISCharge{}, &ProviderError{Kind: "invalid_response"}
	}
	if out.ExpiryTime != "" {
		for _, layout := range []string{"2006-01-02 15:04:05", time.RFC3339} {
			parsed, parseErr := time.ParseInLocation(layout, out.ExpiryTime, time.FixedZone("WIB", 7*60*60))
			if parseErr == nil {
				parsed = parsed.UTC()
				charge.ExpiresAt = &parsed
				break
			}
		}
	}
	return charge, nil
}

func (c *MidtransClient) GetStatus(ctx context.Context, identifier string) (MidtransNotification, error) {
	if strings.TrimSpace(identifier) == "" {
		return MidtransNotification{}, &ProviderError{Kind: "configuration"}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/v2/"+url.PathEscape(identifier)+"/status", nil)
	if err != nil {
		return MidtransNotification{}, &ProviderError{Kind: "configuration"}
	}
	req.Header.Set("Accept", "application/json")
	req.SetBasicAuth(c.serverKey, "")
	res, err := c.httpClient.Do(req)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) || isTimeout(err) {
			return MidtransNotification{}, &ProviderError{Kind: "timeout"}
		}
		return MidtransNotification{}, &ProviderError{Kind: "network"}
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		_, _ = io.Copy(io.Discard, io.LimitReader(res.Body, 1<<20))
		kind := "server"
		switch res.StatusCode {
		case http.StatusNotFound:
			kind = "not_found"
		case http.StatusUnauthorized, http.StatusForbidden:
			kind = "authentication"
		case http.StatusRequestTimeout, http.StatusGatewayTimeout:
			kind = "timeout"
		case http.StatusTooManyRequests:
			kind = "rate_limited"
		default:
			if res.StatusCode >= 400 && res.StatusCode < 500 {
				kind = "rejected"
			}
		}
		return MidtransNotification{}, &ProviderError{Kind: kind}
	}
	var out MidtransNotification
	body, err := io.ReadAll(io.LimitReader(res.Body, (1<<20)+1))
	if err != nil || len(body) > 1<<20 || json.Unmarshal(body, &out) != nil || out.OrderID == "" || out.TransactionID == "" || out.TransactionStatus == "" || out.StatusCode == "" || out.GrossAmount == "" || out.PaymentType == "" || out.Currency == "" {
		return MidtransNotification{}, &ProviderError{Kind: "invalid_response"}
	}
	if out.PaymentType != "qris" || out.Currency != "IDR" {
		return MidtransNotification{}, &ProviderError{Kind: "invalid_response"}
	}
	if _, err := mapMidtransStatus(out); err != nil {
		return MidtransNotification{}, &ProviderError{Kind: "invalid_response"}
	}
	return out, nil
}

func parseIDRAmount(value string) (int64, error) {
	whole, fraction, found := strings.Cut(value, ".")
	if found && strings.Trim(fraction, "0") != "" {
		return 0, errors.New("fractional IDR amount")
	}
	return strconv.ParseInt(whole, 10, 64)
}

func isTimeout(err error) bool {
	type timeout interface{ Timeout() bool }
	var target timeout
	return errors.As(err, &target) && target.Timeout()
}

func (c *MidtransClient) String() string { return fmt.Sprintf("MidtransClient(%s)", c.baseURL) }
