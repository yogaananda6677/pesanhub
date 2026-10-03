package branch

import (
	"context"
	"testing"
)

func TestService_BranchOperations(t *testing.T) {
	svc := setupTestService()
	ctx := context.Background()

	t.Run("List branches", func(t *testing.T) {
		all, err := svc.List(ctx, false)
		if err != nil {
			t.Fatalf("unexpected err: %v", err)
		}
		if len(all) != 3 {
			t.Fatalf("expected 3 branches, got %d", len(all))
		}

		active, err := svc.List(ctx, true)
		if err != nil {
			t.Fatalf("unexpected err: %v", err)
		}
		if len(active) != 2 {
			t.Fatalf("expected 2 active branches, got %d", len(active))
		}
	})

	t.Run("GetByID invalid UUID returns ErrNotFound", func(t *testing.T) {
		_, err := svc.GetByID(ctx, "invalid-uuid")
		if err != ErrNotFound {
			t.Fatalf("expected ErrNotFound, got %v", err)
		}
	})

	t.Run("Create branch validates code and name", func(t *testing.T) {
		// Invalid short code
		_, err := svc.Create(ctx, CreateBranchInput{Code: "A", Name: "Outlet"})
		if err != ErrInvalidInput {
			t.Fatalf("expected ErrInvalidInput, got %v", err)
		}

		// Empty name
		_, err = svc.Create(ctx, CreateBranchInput{Code: "SBY", Name: ""})
		if err != ErrInvalidInput {
			t.Fatalf("expected ErrInvalidInput, got %v", err)
		}

		// Valid
		b, err := svc.Create(ctx, CreateBranchInput{Code: "sby", Name: "Cabang Surabaya"})
		if err != nil {
			t.Fatalf("unexpected err: %v", err)
		}
		if b.Code != "SBY" || b.Name != "Cabang Surabaya" || !b.IsActive {
			t.Fatalf("unexpected created branch: %#v", b)
		}
	})

	t.Run("Update branch", func(t *testing.T) {
		b, err := svc.Update(ctx, "b0000000-0000-0000-0000-000000000001", UpdateBranchInput{
			Name: "Cabang Utama Banyuwangi Baru",
		})
		if err != nil {
			t.Fatalf("unexpected err: %v", err)
		}
		if b.Name != "Cabang Utama Banyuwangi Baru" {
			t.Fatalf("expected updated name, got %s", b.Name)
		}
	})

	t.Run("Assign user to branch validates UUID", func(t *testing.T) {
		err := svc.AssignUserBranch(ctx, "invalid-user-id", "b0000000-0000-0000-0000-000000000001")
		if err != ErrInvalidInput {
			t.Fatalf("expected ErrInvalidInput, got %v", err)
		}

		err = svc.AssignUserBranch(ctx, "a1000000-0000-4000-8000-000000000001", "b0000000-0000-0000-0000-999999999999")
		if err != ErrNotFound {
			t.Fatalf("expected ErrNotFound for non existent branch, got %v", err)
		}
	})
}
