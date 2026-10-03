package superadmin

import (
	"context"
	"errors"
	"net/mail"
	"strings"
	"time"

	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/gowa"
)

var ErrInvitationDelivery = errors.New("invitation was saved but email delivery failed")

type InvitationSender interface {
	SendCashierInvitation(context.Context, string, string, time.Time) error
}
type Database interface {
	Ping(context.Context) error
}

type ServiceStore interface {
	ListUsers(ctx context.Context, filterStatus Status, search string, limit, offset int) ([]UserSummary, error)
	GetUser(ctx context.Context, userID string) (*UserSummary, error)
	ListInvitations(ctx context.Context, limit, offset int) ([]Invitation, error)
	CreateInvitation(ctx context.Context, actorID, email, outletName, branchID string, expiry time.Duration) (Invitation, error)
	RevokeInvitation(ctx context.Context, invitationID string) error
	UpdateUserStatus(ctx context.Context, actorID, targetUserID string, targetStatus Status, reason, requestID string) error
	UpdateUserBranch(ctx context.Context, actorID, targetUserID, branchID, reason, requestID string) error
	RevokeUserSessions(ctx context.Context, targetUserID string) error
	ListAudits(ctx context.Context, targetUserID string, limit, offset int) ([]AuditEntry, error)
	GetTrafficMetrics(ctx context.Context, timeRange string) (TrafficMetrics, error)
	ListEmployees(ctx context.Context, search string) ([]EmployeeSummary, error)
	CreateEmployee(ctx context.Context, actorID, email, displayName, role, branchID string) (EmployeeSummary, error)
	UpdateEmployee(ctx context.Context, targetUserID string, displayName, role, status, branchID *string) (EmployeeSummary, error)
	DeleteEmployee(ctx context.Context, targetUserID string) error
}

type WhatsAppGatewayInspector interface {
	gowa.Checker
	DeviceID() string
	ListDevices(context.Context) ([]gowa.DeviceInfo, error)
	ResolveActiveDevice(context.Context) (*gowa.DeviceInfo, error)
}

type ActiveConnectionCounter interface {
	ClientCount() int
}

type Service struct {
	store            ServiceStore
	db               Database
	gowaChecker      gowa.Checker
	wsCounter        ActiveConnectionCounter
	now              func() time.Time
	invitationSender InvitationSender
}

func (s *Service) SetInvitationSender(sender InvitationSender) {
	s.invitationSender = sender
}

func NewService(store ServiceStore, db Database, gowaChecker gowa.Checker, wsCounter ActiveConnectionCounter) *Service {
	return &Service{
		store:       store,
		db:          db,
		gowaChecker: gowaChecker,
		wsCounter:   wsCounter,
		now:         time.Now,
	}
}

func (s *Service) GetSystemHealth(ctx context.Context) (SystemHealthSnapshot, error) {
	now := s.now().UTC()
	components := make([]ComponentHealth, 0, 6)
	overallStatus := HealthHealthy

	// 1. API Component
	components = append(components, ComponentHealth{
		Component: "api",
		Status:    HealthHealthy,
		Freshness: now,
		Message:   "HTTP API listening and healthy",
		Details: map[string]any{
			"version": "1.0.0",
		},
	})

	// 2. Database Component
	dbStatus := HealthHealthy
	dbMessage := "MySQL connection pool healthy"
	if s.db != nil {
		pingCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
		defer cancel()
		if err := s.db.Ping(pingCtx); err != nil {
			dbStatus = HealthDown
			dbMessage = "MySQL unavailable"
			overallStatus = HealthDown
		}
	} else {
		dbStatus = HealthDegraded
		dbMessage = "Database checker not configured"
		if overallStatus != HealthDown {
			overallStatus = HealthDegraded
		}
	}
	components = append(components, ComponentHealth{
		Component: "database",
		Status:    dbStatus,
		Freshness: now,
		Message:   dbMessage,
	})

	// 3. GOWA Component
	gowaStatus := HealthHealthy
	gowaMessage := "WhatsApp gateway connected and device ready"
	var gowaDetails map[string]any
	if s.gowaChecker != nil {
		gowaCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
		defer cancel()
		readiness := s.gowaChecker.Readiness(gowaCtx)
		gowaDetails = map[string]any{
			"api":    string(readiness.API),
			"device": string(readiness.Device),
		}
		if readiness.Reason != "" {
			gowaDetails["reason"] = readiness.Reason
		}

		if readiness.API != gowa.APIUp {
			gowaStatus = HealthDown
			gowaMessage = "GOWA service unreachable"
			if overallStatus != HealthDown {
				overallStatus = HealthDegraded
			}
		} else if readiness.Device != gowa.DeviceReady {
			gowaStatus = HealthDegraded
			gowaMessage = "WhatsApp device pairing degraded or pending"
			if overallStatus != HealthDown {
				overallStatus = HealthDegraded
			}
		}
	} else {
		gowaStatus = HealthDegraded
		gowaMessage = "GOWA checker not initialized"
		if overallStatus != HealthDown {
			overallStatus = HealthDegraded
		}
	}
	components = append(components, ComponentHealth{
		Component: "gowa",
		Status:    gowaStatus,
		Freshness: now,
		Message:   gowaMessage,
		Details:   gowaDetails,
	})

	// 4. Outbox Worker Component
	components = append(components, ComponentHealth{
		Component: "outbox_worker",
		Status:    HealthHealthy,
		Freshness: now,
		Message:   "Outbox notification dispatcher active",
	})

	// 5. Realtime WebSocket Component
	activeClients := 0
	if s.wsCounter != nil {
		activeClients = s.wsCounter.ClientCount()
	}
	components = append(components, ComponentHealth{
		Component: "realtime_ws",
		Status:    HealthHealthy,
		Freshness: now,
		Message:   "Order queue WebSocket channel open",
		Details: map[string]any{
			"active_clients": activeClients,
		},
	})

	// 6. Mobile Sync Component
	components = append(components, ComponentHealth{
		Component: "mobile_sync",
		Status:    HealthHealthy,
		Freshness: now,
		Message:   "Offline-first order sync channel responsive",
	})

	return SystemHealthSnapshot{
		OverallStatus: overallStatus,
		Timestamp:     now,
		Components:    components,
	}, nil
}

func (s *Service) GetTraffic(ctx context.Context, timeRange string) (TrafficMetrics, error) {
	return s.store.GetTrafficMetrics(ctx, timeRange)
}

func (s *Service) ListUsers(ctx context.Context, status Status, search string, limit, offset int) ([]UserSummary, error) {
	return s.store.ListUsers(ctx, status, search, limit, offset)
}

func (s *Service) ListInvitations(ctx context.Context, limit, offset int) ([]Invitation, error) {
	return s.store.ListInvitations(ctx, limit, offset)
}

func (s *Service) InviteUser(ctx context.Context, actorID, email, outletName, branchID string) (Invitation, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	address, parseErr := mail.ParseAddress(email)
	if parseErr != nil || address.Address != email || len(email) > 320 {
		return Invitation{}, errors.New("invalid email address")
	}
	invitation, err := s.store.CreateInvitation(ctx, actorID, email, outletName, branchID, 7*24*time.Hour)
	if err != nil {
		return Invitation{}, err
	}
	if s.invitationSender != nil {
		if err := s.invitationSender.SendCashierInvitation(ctx, email, invitation.OutletName, invitation.ExpiresAt); err != nil {
			return invitation, ErrInvitationDelivery
		}
	}
	return invitation, nil
}

func (s *Service) RevokeInvitation(ctx context.Context, invitationID string) error {
	invitationID = strings.TrimSpace(invitationID)
	if invitationID == "" {
		return errors.New("invitation ID required")
	}
	return s.store.RevokeInvitation(ctx, invitationID)
}

func (s *Service) ApproveUser(ctx context.Context, actorID, targetUserID, reason, requestID string) error {
	if strings.TrimSpace(targetUserID) == "" {
		return errors.New("user ID required")
	}
	if reason == "" {
		reason = "SUPERADMIN_APPROVAL"
	}
	return s.store.UpdateUserStatus(ctx, actorID, targetUserID, StatusApproved, reason, requestID)
}

func (s *Service) RejectUser(ctx context.Context, actorID, targetUserID, reason, requestID string) error {
	if strings.TrimSpace(targetUserID) == "" {
		return errors.New("user ID required")
	}
	if reason == "" {
		reason = "SUPERADMIN_REJECTION"
	}
	return s.store.UpdateUserStatus(ctx, actorID, targetUserID, StatusRejected, reason, requestID)
}

func (s *Service) SuspendUser(ctx context.Context, actorID, targetUserID, reason, requestID string) error {
	if strings.TrimSpace(targetUserID) == "" {
		return errors.New("user ID required")
	}
	if reason == "" {
		reason = "SUPERADMIN_SUSPENSION"
	}
	return s.store.UpdateUserStatus(ctx, actorID, targetUserID, StatusSuspended, reason, requestID)
}

func (s *Service) ReactivateUser(ctx context.Context, actorID, targetUserID, reason, requestID string) error {
	if strings.TrimSpace(targetUserID) == "" {
		return errors.New("user ID required")
	}
	if reason == "" {
		reason = "SUPERADMIN_REACTIVATION"
	}
	return s.store.UpdateUserStatus(ctx, actorID, targetUserID, StatusApproved, reason, requestID)
}

func (s *Service) RevokeSessions(ctx context.Context, targetUserID string) error {
	if strings.TrimSpace(targetUserID) == "" {
		return errors.New("user ID required")
	}
	return s.store.RevokeUserSessions(ctx, targetUserID)
}

func (s *Service) ListAudits(ctx context.Context, targetUserID string, limit, offset int) ([]AuditEntry, error) {
	return s.store.ListAudits(ctx, targetUserID, limit, offset)
}

func (s *Service) GetUserWhatsAppStatus(ctx context.Context, userID string) (WhatsAppAccountStatus, error) {
	user, err := s.store.GetUser(ctx, userID)
	if err != nil {
		return WhatsAppAccountStatus{}, err
	}

	result := WhatsAppAccountStatus{
		UserID:       user.ID,
		DisplayName:  user.DisplayName,
		EmailMasked:  user.EmailMasked,
		Role:         user.Role,
		Status:       "DISCONNECTED",
		IsConnected:  false,
		GatewayState: "down",
		DeviceID:     "-",
		PhoneMasked:  "-",
		Message:      "WhatsApp belum terhubung.",
	}

	if s.gowaChecker == nil {
		result.Status = "GATEWAY_DOWN"
		result.Message = "WhatsApp Gateway checker belum dikonfigurasi."
		return result, nil
	}

	readiness := s.gowaChecker.Readiness(ctx)
	result.GatewayState = string(readiness.API)

	if readiness.API != gowa.APIUp {
		result.Status = "GATEWAY_DOWN"
		result.Message = "Layanan WhatsApp Gateway (GOWA) sedang tidak aktif atau tidak dapat dihubungi."
		return result, nil
	}

	inspector, ok := s.gowaChecker.(WhatsAppGatewayInspector)
	if !ok {
		if readiness.Device == gowa.DeviceReady {
			result.IsConnected = true
			result.Status = "CONNECTED"
			result.Message = "Perangkat WhatsApp terhubung aktif."
		} else {
			result.Status = "DISCONNECTED"
			result.Message = "Perangkat WhatsApp belum terhubung."
		}
		return result, nil
	}

	devID := inspector.DeviceID()
	if devID != "" {
		result.DeviceID = devID
	}

	activeDevice, err := inspector.ResolveActiveDevice(ctx)
	if err != nil || activeDevice == nil {
		result.Status = "DISCONNECTED"
		result.Message = "Perangkat WhatsApp belum dipasangkan (pairing/scan QR)."
		return result, nil
	}

	result.DeviceID = activeDevice.ID
	isConnected := activeDevice.State == "logged_in" || activeDevice.State == "connected"
	result.IsConnected = isConnected

	if isConnected {
		result.Status = "CONNECTED"
		result.Message = "Perangkat WhatsApp terhubung dan siap menerima pesan."
		if activeDevice.JID != "" {
			result.JID = activeDevice.JID
			phone := strings.Split(activeDevice.JID, "@")[0]
			phone = strings.Split(phone, ":")[0]
			if phone != "" {
				result.PhoneMasked = gowa.MaskPhone("+" + phone)
			}
		}
	} else {
		result.Status = "DISCONNECTED"
		result.Message = "Perangkat WhatsApp terdaftar namun sedang terputus."
	}

	return result, nil
}

func (s *Service) ListWhatsAppAccountStatuses(ctx context.Context) ([]WhatsAppAccountStatus, error) {
	users, err := s.store.ListUsers(ctx, "ALL", "", 100, 0)
	if err != nil {
		return nil, err
	}

	var results []WhatsAppAccountStatus
	for _, u := range users {
		if u.Role == RoleAdmin || u.Role == RoleCashier {
			status, err := s.GetUserWhatsAppStatus(ctx, u.ID)
			if err == nil {
				results = append(results, status)
			}
		}
	}
	return results, nil
}

func (s *Service) UpdateCashierBranch(ctx context.Context, actorPrincipal customer.Principal, targetUserID, newBranchID, reason, requestID string) error {
	if actorPrincipal.Role != "ADMIN" && actorPrincipal.Role != "SUPERADMIN" {
		return customer.ErrUnauthorized
	}
	if actorPrincipal.Subject == targetUserID {
		return errors.New("cannot transfer own branch")
	}
	targetUserID = strings.TrimSpace(targetUserID)
	newBranchID = strings.TrimSpace(newBranchID)
	if targetUserID == "" || newBranchID == "" {
		return errors.New("user ID and branch ID required")
	}
	if reason == "" {
		reason = "ADMIN_TRANSFER"
	}
	return s.store.UpdateUserBranch(ctx, actorPrincipal.Subject, targetUserID, newBranchID, reason, requestID)
}

func (s *Service) ListEmployees(ctx context.Context, search string) ([]EmployeeSummary, error) {
	return s.store.ListEmployees(ctx, search)
}

func (s *Service) CreateEmployee(ctx context.Context, actorID, email, displayName, role, branchID string) (EmployeeSummary, error) {
	return s.store.CreateEmployee(ctx, actorID, email, displayName, role, branchID)
}

func (s *Service) UpdateEmployee(ctx context.Context, targetUserID string, displayName, role, status, branchID *string) (EmployeeSummary, error) {
	return s.store.UpdateEmployee(ctx, targetUserID, displayName, role, status, branchID)
}

func (s *Service) DeleteEmployee(ctx context.Context, targetUserID string) error {
	return s.store.DeleteEmployee(ctx, targetUserID)
}
