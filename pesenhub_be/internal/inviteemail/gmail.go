package inviteemail

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/mail"
	"net/smtp"
	"strings"
	"time"
)

const (
	gmailHost = "smtp.gmail.com"
	gmailAddr = "smtp.gmail.com:587"
)

type GmailSender struct {
	username, password, fromName, loginURL string
	timeout                                time.Duration
}

func NewGmailSender(username, password, fromName, loginURL string) (*GmailSender, error) {
	username = strings.TrimSpace(username)
	password = strings.ReplaceAll(strings.TrimSpace(password), " ", "")
	fromName = strings.TrimSpace(fromName)
	loginURL = strings.TrimSpace(loginURL)
	if _, err := mail.ParseAddress(username); err != nil || password == "" || loginURL == "" || strings.ContainsAny(fromName+loginURL, "\r\n") {
		return nil, errors.New("invalid Gmail invitation configuration")
	}
	if fromName == "" {
		fromName = "PesenHub"
	}
	return &GmailSender{username: username, password: password, fromName: fromName, loginURL: loginURL, timeout: 10 * time.Second}, nil
}

func (s *GmailSender) SendCashierInvitation(ctx context.Context, recipient, outletName string, expiresAt time.Time) error {
	address, err := mail.ParseAddress(strings.TrimSpace(recipient))
	if err != nil || address.Address != strings.TrimSpace(recipient) {
		return errors.New("invalid invitation recipient")
	}
	outletName = strings.TrimSpace(outletName)
	if outletName == "" {
		outletName = "PesenHub Outlet #01"
	}
	if strings.ContainsAny(outletName, "\r\n") {
		return errors.New("invalid outlet name")
	}

	dialer := net.Dialer{Timeout: s.timeout}
	conn, err := dialer.DialContext(ctx, "tcp", gmailAddr)
	if err != nil {
		return fmt.Errorf("connect Gmail SMTP: %w", err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(s.timeout))
	client, err := smtp.NewClient(conn, gmailHost)
	if err != nil {
		return fmt.Errorf("start Gmail SMTP: %w", err)
	}
	defer client.Close()
	if err = client.StartTLS(&tls.Config{ServerName: gmailHost, MinVersion: tls.VersionTLS12}); err != nil {
		return fmt.Errorf("secure Gmail SMTP: %w", err)
	}
	if err = client.Auth(smtp.PlainAuth("", s.username, s.password, gmailHost)); err != nil {
		return fmt.Errorf("authenticate Gmail SMTP: %w", err)
	}
	if err = client.Mail(s.username); err != nil {
		return fmt.Errorf("set invitation sender: %w", err)
	}
	if err = client.Rcpt(address.Address); err != nil {
		return fmt.Errorf("set invitation recipient: %w", err)
	}
	w, err := client.Data()
	if err != nil {
		return fmt.Errorf("open invitation message: %w", err)
	}
	message := fmt.Sprintf("From: %s <%s>\r\nTo: %s\r\nSubject: Undangan Kasir PesenHub\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nAnda diundang sebagai Kasir untuk %s.\r\n\r\nBuka %s lalu masuk dengan akun Google %s. Backend akan mengaktifkan role CASHIER setelah email Google terverifikasi cocok dengan undangan.\r\n\r\nUndangan berlaku sampai %s.\r\n", s.fromName, s.username, address.Address, outletName, s.loginURL, address.Address, expiresAt.In(time.FixedZone("WIB", 7*60*60)).Format("02 Jan 2006 15:04 WIB"))
	if _, err = w.Write([]byte(message)); err != nil {
		_ = w.Close()
		return fmt.Errorf("write invitation message: %w", err)
	}
	if err = w.Close(); err != nil {
		return fmt.Errorf("send invitation message: %w", err)
	}
	if err = client.Quit(); err != nil {
		return fmt.Errorf("finish Gmail SMTP: %w", err)
	}
	return nil
}
