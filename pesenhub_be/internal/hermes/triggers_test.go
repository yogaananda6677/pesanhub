package hermes

import "testing"

func TestDetectComplaint(t *testing.T) {
	tests := []struct {
		name         string
		input        string
		wantDetected bool
		wantReason   string
		wantPriority string
	}{
		{
			name:         "complaint about wrong order",
			input:        "Woy salah pesanan ini, saya pesan pedas dikasih manis!",
			wantDetected: true,
			wantReason:   "customer_complaint",
			wantPriority: HandoffPriorityUrgent,
		},
		{
			name:         "disappointment sentiment",
			input:        "Kecewa banget pelayanan buruk dan lama banget",
			wantDetected: true,
			wantReason:   "customer_complaint",
			wantPriority: HandoffPriorityUrgent,
		},
		{
			name:         "request human staff",
			input:        "Saya mau bicara sama manusia dong, jangan bot",
			wantDetected: true,
			wantReason:   "customer_requested_human",
			wantPriority: HandoffPriorityHigh,
		},
		{
			name:         "request admin",
			input:        "Bisa panggil admin gak?",
			wantDetected: true,
			wantReason:   "customer_requested_human",
			wantPriority: HandoffPriorityHigh,
		},
		{
			name:         "normal food order",
			input:        "Pesan Nasi Goreng Spesial 1 pedas ya kak",
			wantDetected: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			detected, reason, priority := DetectComplaint(tc.input)
			if detected != tc.wantDetected {
				t.Fatalf("expected detected=%v, got %v", tc.wantDetected, detected)
			}
			if tc.wantDetected {
				if reason != tc.wantReason {
					t.Errorf("expected reason=%q, got %q", tc.wantReason, reason)
				}
				if priority != tc.wantPriority {
					t.Errorf("expected priority=%q, got %q", tc.wantPriority, priority)
				}
			}
		})
	}
}

func TestDetectOutOfScope(t *testing.T) {
	tests := []struct {
		name         string
		input        string
		wantDetected bool
		wantReason   string
		wantPriority string
	}{
		{
			name:         "loan request",
			input:        "Halo kak, apa bisa pinjam uang atau ada info pinjol cepat cair?",
			wantDetected: true,
			wantReason:   "out_of_scope_inquiry",
			wantPriority: HandoffPriorityLow,
		},
		{
			name:         "job vacancy inquiry",
			input:        "Permisi, apakah outlet ini sedang buka lowongan kerja?",
			wantDetected: true,
			wantReason:   "out_of_scope_inquiry",
			wantPriority: HandoffPriorityLow,
		},
		{
			name:         "motorcycle mechanic inquiry",
			input:        "Bisa sekalian servis motor atau ganti oli gak kak?",
			wantDetected: true,
			wantReason:   "out_of_scope_inquiry",
			wantPriority: HandoffPriorityLow,
		},
		{
			name:         "normal menu inquiry",
			input:        "Ada menu mie goreng apa aja ya kak?",
			wantDetected: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			detected, reason, priority := DetectOutOfScope(tc.input)
			if detected != tc.wantDetected {
				t.Fatalf("expected detected=%v, got %v", tc.wantDetected, detected)
			}
			if tc.wantDetected {
				if reason != tc.wantReason {
					t.Errorf("expected reason=%q, got %q", tc.wantReason, reason)
				}
				if priority != tc.wantPriority {
					t.Errorf("expected priority=%q, got %q", tc.wantPriority, priority)
				}
			}
		})
	}
}
