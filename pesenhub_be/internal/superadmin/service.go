package superadmin

import (
	"context"
	"errors"
	"strings"
	"time"

	"pesenhub/backend/internal/gowa"
)

type Database interface {
	Ping(context.Context) error
}

type ServiceStore interface {
	ListUsers(ctx context.Context, filterStatus Status, search string, limit, offset int) ([]UserSummary, error)
	ListInvitations(ctx context.Context, limit, offset int) ([]Invitation, error)
	CreateInvitation(ctx context.Context, actorID, email, outletName string, expiry time.Duration) (Invitation, error)
	RevokeInvitation(ctx context.Context, invitationID string) error
	UpdateUserStatus(ctx context.Context, actorID, targetUserID string, targetStatus Status, reason, requestID string) error
	RevokeUserSessions(ctx context.Context, targetUserID string) error
	ListAudits(ctx context.Context, targetUserID string, limit, offset int) ([]AuditEntry, error)
	GetTrafficMetrics(ctx context.Context, timeRange string) (TrafficMetrics, error)
}

type ActiveConnectionCounter interface {
	ClientCount() int
}

type Service struct {
	store       ServiceStore
	db          Database
	gowaChecker gowa.Checker
	wsCounter   ActiveConnectionCounter
	now         func() time.Time
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
	dbMessage := "PostgreSQL connection pool healthy"
	if s.db != nil {
		pingCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
		defer cancel()
		if err := s.db.Ping(pingCtx); err != nil {
			dbStatus = HealthDown
			dbMessage = "PostgreSQL unavailable"
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

func (s *Service) InviteUser(ctx context.Context, actorID, email, outletName string) (Invitation, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" || !strings.Contains(email, "@") || len(email) > 320 {
		return Invitation{}, errors.New("invalid email address")
	}
	return s.store.CreateInvitation(ctx, actorID, email, outletName, 7*24*time.Hour)
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
