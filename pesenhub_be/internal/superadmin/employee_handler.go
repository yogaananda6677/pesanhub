package superadmin

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"

	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/httpapi"
	"pesenhub/backend/internal/httpserver"
)

type EmployeeSummary struct {
	ID          string    `json:"id"`
	Email       string    `json:"email"`
	DisplayName string    `json:"display_name"`
	Role        string    `json:"role"`
	Status      string    `json:"status"`
	BranchID    *string   `json:"branch_id,omitempty"`
	BranchName  string    `json:"branch_name,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
}

type CreateEmployeeRequest struct {
	Email       string `json:"email"`
	DisplayName string `json:"display_name,omitempty"`
	Role        string `json:"role,omitempty"`
	BranchID    string `json:"branch_id,omitempty"`
}

type UpdateEmployeeRequest struct {
	DisplayName *string `json:"display_name,omitempty"`
	Role        *string `json:"role,omitempty"`
	Status      *string `json:"status,omitempty"`
	BranchID    *string `json:"branch_id,omitempty"`
}

// GET /api/v1/admin/employees
func (h *Handler) ListEmployees(w http.ResponseWriter, r *http.Request) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" || (p.Role != "ADMIN" && p.Role != "SUPERADMIN" && p.Role != "OWNER") {
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Admin authorization required.", httpserver.RequestID(r.Context()), nil)
		return
	}

	search := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("q")))
	employees, err := h.service.ListEmployees(r.Context(), search)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	if employees == nil {
		employees = []EmployeeSummary{}
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"data": employees,
	})
}

// POST /api/v1/admin/employees
func (h *Handler) CreateEmployee(w http.ResponseWriter, r *http.Request) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" || (p.Role != "ADMIN" && p.Role != "SUPERADMIN" && p.Role != "OWNER") {
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Admin authorization required.", httpserver.RequestID(r.Context()), nil)
		return
	}

	var req CreateEmployeeRequest
	d := json.NewDecoder(io.LimitReader(r.Body, (1<<20)+1))
	if err := d.Decode(&req); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_REQUEST", "Format JSON tidak valid.", httpserver.RequestID(r.Context()), nil)
		return
	}

	email := strings.ToLower(strings.TrimSpace(req.Email))
	if !strings.Contains(email, "@") || len(email) < 5 {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_EMAIL", "Alamat email tidak valid.", httpserver.RequestID(r.Context()), nil)
		return
	}

	role := strings.ToUpper(strings.TrimSpace(req.Role))
	if role == "" {
		role = "CASHIER"
	}
	if role != "CASHIER" && role != "ADMIN" && role != "MANAGER" {
		role = "CASHIER"
	}

	branchID := strings.TrimSpace(req.BranchID)
	if branchID == "" && p.BranchID != "" {
		branchID = p.BranchID
	}

	emp, err := h.service.CreateEmployee(r.Context(), p.Subject, email, req.DisplayName, role, branchID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusCreated, emp)
}

// PATCH /api/v1/admin/employees/{id}
func (h *Handler) UpdateEmployee(w http.ResponseWriter, r *http.Request) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" || (p.Role != "ADMIN" && p.Role != "SUPERADMIN" && p.Role != "OWNER") {
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Admin authorization required.", httpserver.RequestID(r.Context()), nil)
		return
	}

	targetID := r.PathValue("id")
	if targetID == "" {
		httpapi.WriteError(w, http.StatusBadRequest, "ID_REQUIRED", "ID karyawan wajib disertakan.", httpserver.RequestID(r.Context()), nil)
		return
	}

	var req UpdateEmployeeRequest
	d := json.NewDecoder(io.LimitReader(r.Body, (1<<20)+1))
	if err := d.Decode(&req); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_REQUEST", "Format JSON tidak valid.", httpserver.RequestID(r.Context()), nil)
		return
	}

	emp, err := h.service.UpdateEmployee(r.Context(), targetID, req.DisplayName, req.Role, req.Status, req.BranchID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, emp)
}

// DELETE /api/v1/admin/employees/{id}
func (h *Handler) DeleteEmployee(w http.ResponseWriter, r *http.Request) {
	p := customer.PrincipalFromRequest(r)
	if p.Subject == "" || (p.Role != "ADMIN" && p.Role != "SUPERADMIN" && p.Role != "OWNER") {
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "Admin authorization required.", httpserver.RequestID(r.Context()), nil)
		return
	}

	targetID := r.PathValue("id")
	if targetID == "" {
		httpapi.WriteError(w, http.StatusBadRequest, "ID_REQUIRED", "ID karyawan wajib disertakan.", httpserver.RequestID(r.Context()), nil)
		return
	}

	if err := h.service.DeleteEmployee(r.Context(), targetID); err != nil {
		h.writeError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
