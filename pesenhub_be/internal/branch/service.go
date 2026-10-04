package branch

import (
	"context"
	"regexp"
	"strings"

	"pesenhub/backend/internal/customer"
	"pesenhub/backend/internal/domain"
)

var validCodePattern = regexp.MustCompile(`^[A-Z0-9_-]{2,16}$`)

type Repository interface {
	List(ctx context.Context, activeOnly bool) ([]Branch, error)
	GetByID(ctx context.Context, id string) (Branch, error)
	GetByCode(ctx context.Context, code string) (Branch, error)
	GetDefault(ctx context.Context) (Branch, error)
	Create(ctx context.Context, b Branch) (Branch, error)
	Update(ctx context.Context, b Branch) (Branch, error)
	AssignUserBranch(ctx context.Context, userID, branchID string) error
}

type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) List(ctx context.Context, activeOnly bool) ([]Branch, error) {
	return s.repo.List(ctx, activeOnly)
}

func (s *Service) GetByID(ctx context.Context, id string) (Branch, error) {
	if !domain.ValidUUID(id) {
		return Branch{}, ErrNotFound
	}
	return s.repo.GetByID(ctx, id)
}

func (s *Service) GetDefault(ctx context.Context) (Branch, error) {
	return s.repo.GetDefault(ctx)
}

func (s *Service) Create(ctx context.Context, in CreateBranchInput) (Branch, error) {
	code := strings.ToUpper(strings.TrimSpace(in.Code))
	name := strings.TrimSpace(in.Name)
	if !validCodePattern.MatchString(code) || name == "" || len(name) > 120 {
		return Branch{}, ErrInvalidInput
	}
	b := Branch{
		ID:        customer.NewID(),
		Code:      code,
		Name:      name,
		Address:   strings.TrimSpace(in.Address),
		Phone:     strings.TrimSpace(in.Phone),
		IsDefault: in.IsDefault,
		IsActive:  true,
	}
	return s.repo.Create(ctx, b)
}

func (s *Service) Update(ctx context.Context, id string, in UpdateBranchInput) (Branch, error) {
	if !domain.ValidUUID(id) {
		return Branch{}, ErrNotFound
	}
	existing, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return Branch{}, err
	}

	if in.Code != "" {
		code := strings.ToUpper(strings.TrimSpace(in.Code))
		if !validCodePattern.MatchString(code) {
			return Branch{}, ErrInvalidInput
		}
		existing.Code = code
	}
	if in.Name != "" {
		name := strings.TrimSpace(in.Name)
		if len(name) > 120 {
			return Branch{}, ErrInvalidInput
		}
		existing.Name = name
	}
	if in.Address != "" {
		existing.Address = strings.TrimSpace(in.Address)
	}
	if in.Phone != "" {
		existing.Phone = strings.TrimSpace(in.Phone)
	}
	if in.IsDefault != nil {
		existing.IsDefault = *in.IsDefault
	}
	if in.IsActive != nil {
		existing.IsActive = *in.IsActive
	}

	return s.repo.Update(ctx, existing)
}

func (s *Service) AssignUserBranch(ctx context.Context, userID, branchID string) error {
	if !domain.ValidUUID(userID) || !domain.ValidUUID(branchID) {
		return ErrInvalidInput
	}
	if _, err := s.repo.GetByID(ctx, branchID); err != nil {
		return err
	}
	return s.repo.AssignUserBranch(ctx, userID, branchID)
}
