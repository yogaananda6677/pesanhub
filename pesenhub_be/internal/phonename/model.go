package phonename

import "time"

type PhoneName struct {
	PhoneE164    string    `json:"phone_e164"`
	CustomerName string    `json:"customer_name"`
	Notes        string    `json:"notes,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type SetPhoneNameInput struct {
	Phone        string `json:"phone"`
	CustomerName string `json:"customer_name"`
	Notes        string `json:"notes,omitempty"`
}
