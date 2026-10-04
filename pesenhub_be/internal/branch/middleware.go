package branch

import (
	"net/http"
	"strings"

	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

type BranchValidator interface {
	GetByID(r http.Request, id string) (Branch, error)
}

func Middleware(service *Service) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			principal := customer.PrincipalFromRequest(r)
			rawHeader := strings.TrimSpace(r.Header.Get("X-Branch-ID"))
			requestID := httpserver.RequestID(r.Context())

			scope := Scope{}

			if principal.Subject != "" {
				switch principal.Role {
				case "CASHIER":
					if principal.BranchID == "" {
						httpapi.WriteError(w, http.StatusForbidden, "NO_BRANCH_ASSIGNED", "Akun kasir belum ditugaskan ke cabang mana pun.", requestID, nil)
						return
					}
					if service != nil {
						b, err := service.GetByID(r.Context(), principal.BranchID)
						if err == nil && !b.IsActive {
							httpapi.WriteError(w, http.StatusForbidden, "BRANCH_INACTIVE", "Cabang kasir sedang tidak aktif.", requestID, nil)
							return
						}
					}
					// If cashier explicitly provided X-Branch-ID and it doesn't match their assigned branch:
					if rawHeader != "" && rawHeader != principal.BranchID {
						httpapi.WriteError(w, http.StatusForbidden, "CROSS_BRANCH_FORBIDDEN", "Kasir tidak memiliki akses ke cabang lain.", requestID, nil)
						return
					}
					scope = Scope{BranchID: principal.BranchID, All: false}

				case "ADMIN", "SUPERADMIN", "STAFF":
					if rawHeader != "" {
						b, err := service.GetByID(r.Context(), rawHeader)
						if err != nil || !b.IsActive {
							httpapi.WriteError(w, http.StatusBadRequest, "INVALID_BRANCH", "Cabang yang dipilih tidak valid atau tidak aktif.", requestID, nil)
							return
						}
						scope = Scope{BranchID: b.ID, All: false}
					} else {
						// Admin without X-Branch-ID is in "All Branches" mode
						scope = Scope{BranchID: "", All: true}
					}

				default:
					if rawHeader != "" {
						b, err := service.GetByID(r.Context(), rawHeader)
						if err == nil && b.IsActive {
							scope = Scope{BranchID: b.ID, All: false}
						}
					}
				}
			} else {
				// Public / Unauthenticated
				if rawHeader != "" {
					b, err := service.GetByID(r.Context(), rawHeader)
					if err == nil && b.IsActive {
						scope = Scope{BranchID: b.ID, All: false}
					}
				}
			}

			r = r.WithContext(WithScope(r.Context(), scope))
			next.ServeHTTP(w, r)
		})
	}
}
