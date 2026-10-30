package report

import (
	"context"
	"errors"

	"pesenhub/backend/internal/branch"
	"pesenhub/backend/internal/customer"
)

var (
	ErrCrossBranchForbidden = errors.New("cross branch access forbidden")
	ErrBranchNotFound       = errors.New("branch not found")
	ErrUnauthorized         = errors.New("unauthorized")
	ErrInvalidDateRange     = errors.New("invalid date range")
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

func (s *Service) validateFilter(ctx context.Context, p customer.Principal, filter *Filter) error {
	if !customer.CanOperateOutlet(p) {
		return ErrUnauthorized
	}

	if filter.From != nil && filter.To != nil && filter.From.After(*filter.To) {
		return ErrInvalidDateRange
	}

	switch p.Role {
	case "CASHIER":
		if p.BranchID == "" {
			return ErrUnauthorized
		}
		// Cashier cannot query another branch
		if filter.BranchID != "" && filter.BranchID != p.BranchID {
			return ErrCrossBranchForbidden
		}
		// Strictly enforce cashier's assigned branch
		filter.BranchID = p.BranchID
		filter.IncludeBranches = false

	case "ADMIN", "SUPERADMIN", "STAFF":
		if filter.BranchID != "" {
			if s.branchFinder != nil {
				b, err := s.branchFinder.GetByID(ctx, filter.BranchID)
				if err != nil || !b.IsActive {
					return ErrBranchNotFound
				}
			}
		} else {
			// Admin in All Branches mode gets branch breakdown by default
			filter.IncludeBranches = true
		}
	}
	return nil
}

func (s *Service) GetSummary(ctx context.Context, p customer.Principal, filter Filter) (Summary, error) {
	if err := s.validateFilter(ctx, p, &filter); err != nil {
		return Summary{}, err
	}
	return s.store.GetSummary(ctx, filter)
}

func (s *Service) GetTopProducts(ctx context.Context, p customer.Principal, filter Filter, limit int) (TopProductsResponse, error) {
	if err := s.validateFilter(ctx, p, &filter); err != nil {
		return TopProductsResponse{}, err
	}
	return s.store.GetTopProducts(ctx, filter, limit)
}
