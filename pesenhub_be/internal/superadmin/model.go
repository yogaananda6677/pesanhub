package superadmin

import "time"

type Role string
type Status string

const (
	RoleOwner      Role = "OWNER"
	RoleSuperadmin Role = "SUPERADMIN"

	StatusPending   Status = "PENDING_APPROVAL"
	StatusApproved  Status = "APPROVED"
	StatusRejected  Status = "REJECTED"
	StatusSuspended Status = "SUSPENDED"
	StatusInvited   Status = "INVITED"

	HealthHealthy  = "healthy"
	HealthDegraded = "degraded"
	HealthDown     = "down"
)

type UserSummary struct {
	ID                 string     `json:"id"`
	EmailMasked        string     `json:"email"`
	DisplayName        string     `json:"display_name"`
	Role               Role       `json:"role"`
	Status             Status     `json:"status"`
	StatusReason       string     `json:"status_reason,omitempty"`
	ApprovedAt         *time.Time `json:"approved_at,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
	ActiveSessionCount int        `json:"active_session_count"`
}

type Invitation struct {
	ID          string    `json:"id"`
	EmailMasked string    `json:"email"`
	OutletName  string    `json:"outlet_name"`
	Status      string    `json:"status"`
	InvitedBy   string    `json:"invited_by"`
	CreatedAt   time.Time `json:"created_at"`
	ExpiresAt   time.Time `json:"expires_at"`
}

type InviteRequest struct {
	Email      string `json:"email"`
	OutletName string `json:"outlet_name,omitempty"`
}

type StatusChangeRequest struct {
	Reason string `json:"reason,omitempty"`
}

type AuditEntry struct {
	ID                    string    `json:"id"`
	UserID                string    `json:"user_id"`
	TargetUserMaskedEmail string    `json:"target_email"`
	ActorUserID           *string   `json:"actor_user_id,omitempty"`
	ActorMaskedEmail      string    `json:"actor_email,omitempty"`
	FromStatus            *string   `json:"from_status,omitempty"`
	ToStatus              string    `json:"to_status"`
	ReasonRedacted        *string   `json:"reason,omitempty"`
	RequestID             string    `json:"request_id"`
	CreatedAt             time.Time `json:"created_at"`
}

type ComponentHealth struct {
	Component string         `json:"component"`
	Status    string         `json:"status"`
	Freshness time.Time      `json:"freshness"`
	Message   string         `json:"message"`
	Details   map[string]any `json:"details,omitempty"`
}

type SystemHealthSnapshot struct {
	OverallStatus string            `json:"overall_status"`
	Timestamp     time.Time         `json:"timestamp"`
	Components    []ComponentHealth `json:"components"`
}

type TrafficSample struct {
	BucketTime        time.Time `json:"bucket_time"`
	TotalRequests     int       `json:"total_requests"`
	SuccessRequests   int       `json:"success_requests"`
	ClientErrors      int       `json:"client_errors"`
	ServerErrors      int       `json:"server_errors"`
	LatencyP50Ms      int       `json:"latency_p50_ms"`
	LatencyP95Ms      int       `json:"latency_p95_ms"`
	WAInboundCount    int       `json:"wa_inbound_count"`
	WAOutboundCount   int       `json:"wa_outbound_count"`
	SyncSuccessCount  int       `json:"sync_success_count"`
	SyncFailureCount  int       `json:"sync_failure_count"`
	SyncConflictCount int       `json:"sync_conflict_count"`
}

type TrafficMetrics struct {
	TimeRange         string          `json:"range"`
	TotalRequests     int64           `json:"total_requests"`
	SuccessRequests   int64           `json:"success_requests"`
	ClientErrors      int64           `json:"client_errors"`
	ServerErrors      int64           `json:"server_errors"`
	RequestRatePerMin float64         `json:"request_rate_per_min"`
	SuccessRate       float64         `json:"success_rate"`
	LatencyP50Ms      int             `json:"latency_p50_ms"`
	LatencyP95Ms      int             `json:"latency_p95_ms"`
	WAInboundCount    int64           `json:"wa_inbound_count"`
	WAOutboundCount   int64           `json:"wa_outbound_count"`
	QueuePending      int64           `json:"queue_pending"`
	QueuePreparing    int64           `json:"queue_preparing"`
	QueueReady        int64           `json:"queue_ready"`
	SyncSuccessCount  int64           `json:"sync_success_count"`
	SyncFailureCount  int64           `json:"sync_failure_count"`
	SyncConflictCount int64           `json:"sync_conflict_count"`
	LastSyncAt        *time.Time      `json:"last_sync_at,omitempty"`
	Series            []TrafficSample `json:"series"`
}
