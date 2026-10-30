package shift

import (
	"context"
	"errors"
	"strings"

	"pesenhub/backend/internal/branch"
	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/domain"
)

var (
	ErrUnauthorized  = errors.New("unauthorized")
	ErrInvalidAmount = errors.New("invalid amount: cash value cannot be negative")
	ErrInvalidBranch = errors.New("invalid or missing branch_id")
	ErrNoActiveShift = errors.New("no active shift currently open")
)

type BranchFinder interface {
	GetByID(ctx context.Context, id string) (branch.Branch, error)
}

type Service struct {
	store        *Store
	branchFinder BranchFinder
}

func NewService(store *Store, branchFinder BranchFinder) *Service {
	return &Service{
		store:        store,
		branchFinder: branchFinder,
	}
}

func (s *Service) resolveBranchID(p customer.Principal, requestedBranch string) (string, error) {
	if p.Role == "CASHIER" {
		if p.BranchID == "" {
			return "", ErrInvalidBranch
		}
		if requestedBranch != "" && requestedBranch != p.BranchID {
			return "", errors.New("cross branch access forbidden for cashier")
		}
		return p.BranchID, nil
	}

	bID := strings.TrimSpace(requestedBranch)
	if bID == "" {
		bID = p.BranchID
	}
	if bID == "" {
		return "", ErrInvalidBranch
	}
	if !domain.ValidUUID(bID) {
		return "", ErrInvalidBranch
	}
	return bID, nil
}

func (s *Service) OpenShift(ctx context.Context, p customer.Principal, req OpenShiftRequest) (CashShift, error) {
	if !customer.CanOperateOutlet(p) {
		return CashShift{}, ErrUnauthorized
	}

	branchID, err := s.resolveBranchID(p, req.BranchID)
	if err != nil {
		return CashShift{}, err
	}

	if req.StartingCash < 0 {
		return CashShift{}, ErrInvalidAmount
	}

	cashierName := strings.TrimSpace(p.Subject)
	if cashierName == "" {
		cashierName = "Kasir Utama"
	}

	var notesPtr *string
	trimmedNotes := strings.TrimSpace(req.Notes)
	if trimmedNotes != "" {
		notesPtr = &trimmedNotes
	}

	cs := CashShift{
		BranchID:     branchID,
		CashierID:    p.Subject,
		CashierName:  cashierName,
		StartingCash: req.StartingCash,
		Notes:        notesPtr,
	}

	return s.store.OpenShift(ctx, cs)
}

func (s *Service) GetCurrentShift(ctx context.Context, p customer.Principal, requestedBranch string) (*CashShift, error) {
	if !customer.CanOperateOutlet(p) {
		return nil, ErrUnauthorized
	}

	branchID, err := s.resolveBranchID(p, requestedBranch)
	if err != nil {
		return nil, err
	}

	return s.store.GetCurrentShift(ctx, branchID)
}

func (s *Service) CloseShift(ctx context.Context, p customer.Principal, req CloseShiftRequest) (CashShift, error) {
	if !customer.CanOperateOutlet(p) {
		return CashShift{}, ErrUnauthorized
	}

	if req.ActualCash < 0 {
		return CashShift{}, ErrInvalidAmount
	}

	shiftID := strings.TrimSpace(req.ShiftID)
	branchID, _ := s.resolveBranchID(p, "")

	if shiftID == "" {
		active, err := s.store.GetCurrentShift(ctx, branchID)
		if err != nil {
			return CashShift{}, err
		}
		if active == nil {
			return CashShift{}, ErrNoActiveShift
		}
		shiftID = active.ID
	}

	return s.store.CloseShift(ctx, shiftID, branchID, req.ActualCash, strings.TrimSpace(req.Notes))
}

func (s *Service) ListShifts(ctx context.Context, p customer.Principal, requestedBranch string, limit int) ([]CashShift, error) {
	if !customer.CanOperateOutlet(p) {
		return nil, ErrUnauthorized
	}

	branchID, err := s.resolveBranchID(p, requestedBranch)
	if err != nil {
		return nil, err
	}

	return s.store.ListShifts(ctx, branchID, limit)
}
