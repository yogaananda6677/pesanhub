package phonename

import (
	"context"
	"testing"
)

func TestSetPhoneNameInputValidation(t *testing.T) {
	store := NewStore(nil)
	ctx := context.Background()

	_, err := store.Set(ctx, SetPhoneNameInput{Phone: "", CustomerName: ""})
	if err == nil {
		t.Errorf("expected error for empty phone and customer_name, got nil")
	}

	_, err = store.Set(ctx, SetPhoneNameInput{Phone: "08123456789", CustomerName: ""})
	if err == nil {
		t.Errorf("expected error for empty customer_name, got nil")
	}

	name, err := store.Get(ctx, "")
	if err != nil || name != "" {
		t.Errorf("expected empty name for empty phone, got name=%q, err=%v", name, err)
	}
}
