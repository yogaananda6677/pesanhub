package appauth

import (
	"context"
	"errors"
	"strings"

	"github.com/coreos/go-oidc/v3/oidc"
)

type GoogleVerifier interface {
	Verify(context.Context, string, string) (GoogleIdentity, error)
}

type OIDCGoogleVerifier struct{ verifier *oidc.IDTokenVerifier }

func NewOIDCGoogleVerifier(ctx context.Context, clientID string) (*OIDCGoogleVerifier, error) {
	if strings.TrimSpace(clientID) == "" {
		return nil, errors.New("google client ID is required")
	}
	keys := oidc.NewRemoteKeySet(ctx, "https://www.googleapis.com/oauth2/v3/certs")
	return &OIDCGoogleVerifier{verifier: oidc.NewVerifier("https://accounts.google.com", keys, &oidc.Config{ClientID: clientID})}, nil
}

func (v *OIDCGoogleVerifier) Verify(ctx context.Context, rawToken, expectedNonce string) (GoogleIdentity, error) {
	if strings.TrimSpace(rawToken) == "" || strings.TrimSpace(expectedNonce) == "" {
		return GoogleIdentity{}, errors.New("ID token and nonce are required")
	}
	token, err := v.verifier.Verify(ctx, rawToken)
	if err != nil {
		return GoogleIdentity{}, errors.New("invalid Google identity token")
	}
	var claims struct {
		Subject       string `json:"sub"`
		Email         string `json:"email"`
		EmailVerified bool   `json:"email_verified"`
		Name          string `json:"name"`
		Nonce         string `json:"nonce"`
	}
	if err := token.Claims(&claims); err != nil || claims.Subject == "" || claims.Email == "" || !claims.EmailVerified || claims.Nonce != expectedNonce {
		return GoogleIdentity{}, errors.New("invalid Google identity claims")
	}
	return GoogleIdentity{Subject: claims.Subject, Email: claims.Email, DisplayName: claims.Name, EmailVerified: true}, nil
}
