# Hermes Structured Order Extraction & Confidence Policy

## 1. Ringkasan Arsitektur

Hermes bertindak sebagai conversational AI agent order extraction di PesenHub. Perannya dibatasi secara ketat pada boundary backend (`internal/hermes`):
- **Tidak Memiliki Akses Database Langsung**: Hermes tidak mengeksekusi query database langsung dan tidak memegang credential integrasi.
- **Bukan Order Final**: Output dari pipeline ekstraksi adalah `DraftCandidate` yang tervalidasi dan audit record `agent_runs`. Order final hanya dibuat setelah konfirmasi eksplisit dari pelanggan pada Issue #41.
- **Zero AI Price/Menu Hallucination**: Model LLM dilarang mengarang harga, SKU, atau ketersediaan menu. Seluruh item yang diekstraksi dicocokkan ke katalog aktif (`internal/catalog`), dan harga unit serta line total dihitung langsung oleh backend dari database katalog.

```
[Inbound WhatsApp Message]
            │
            ▼
   [Prompt Injection Check] ──(Injected)──► [Status: REJECTED_INJECTION]
            │ (Safe)
            ▼
   [Untrusted Boundary Wrap]
  <untrusted_customer_message>
            │
            ▼
       [LLM Client] (Hermes/OpenAI/Mock)
            │
            ▼
   [RawExtractedOrder JSON]
            │
            ▼
   [Catalog Resolver] ──► Cocokkan SKU/Menu & Validasi Modifier Wajib
            │             Hitung Harga Resmi dari Backend
            ▼
   [Confidence Evaluator] ──► Cek Ambang Batas (0.75) & Deteksi Keraguan
            │
            ▼
    [DraftCandidate] + [AgentRun Audit] ──► Disimpan ke PostgreSQL (agent_runs)
```

---

## 2. Invariants & Zero Hallucination Policy

1. **Grounded on Active Catalog**:
   - Jika pelanggan memesan menu yang tidak terdaftar di katalog (`is_available = true`), sistem tidak mengarang SKU atau harga melainkan menandai `is_ambiguous = true` dengan alasan `menu_not_found:<menu_name>`.
   - Jika menu habis (`is_available = false`), sistem menandai `is_ambiguous = true` dengan alasan `menu_unavailable:<menu_name>`.
2. **Kalkulasi Harga backend**:
   - Nilai `UnitPriceAmount`, `ModifiersTotalAmount`, dan `LineTotalAmount` selalu berasal dari data katalog backend.
   - Angka harga yang mungkin disebut pelanggan atau dimunculkan oleh model diabaikan dalam kalkulasi final.
3. **Pilihan Modifier Wajib (Required Modifiers)**:
   - Untuk modifier group dengan `min_select >= 1` (misalnya Level Pedas), jika pelanggan tidak menyebutkan pilihannya, sistem menolak membuat asumsi default.
   - Sistem mencatat flag ambiguitas `missing_required_modifier:<group_name>` dan menandai draft sebagai ambigu agar dapat diklarifikasi ke pelanggan.
4. **Batas Maksimum Modifier (Max Select)**:
   - Jika pelanggan memilih opsi melebihi `max_select`, dicatat `modifier_limit_exceeded:<group_name>`.

---

## 3. Kebijakan Skor Confidence & Ambiguitas

- **Ambang Batas Default**: `DefaultConfidenceThreshold = 0.75`.
- **Perhitungan Skor**:
  - Skor rata-rata item berbobot 60%, skor order level berbobot 40%.
  - Deteksi kata-kata keraguan pelanggan (misal "mungkin", "kayaknya", "atau", "kalau ada", "terserah") memberikan penalti confidence dan memicu flag `uncertainty_detected`.
- **Kondisi Draft Ambigu (`is_ambiguous = true`)**:
  - Skor agregat confidence < 0.75.
  - Terdapat item dengan confidence < 0.75.
  - Terdapat modifier wajib yang belum dipilih.
  - Terdapat menu tidak dikenal atau habis.
  - Pesan tidak mengandung pesanan makanan/minuman valid (`no_valid_items_resolved`).
  - Terdeteksi percobaan prompt injection.

---

## 4. Keamanan & Proteksi Prompt Injection

1. **Untrusted Input Boundary**:
   - Pesan mentah pelanggan dibungkus dalam tag pembatas eksplisit:
     ```
     <untrusted_customer_message>
     {{pesan_pelanggan}}
     </untrusted_customer_message>
     ```
   - Karakter atau tag tiruan di dalam pesan pelanggan dibersihkan terlebih dahulu untuk mencegah manipulasi delimiter.
2. **Deteksi Pola Jailbreak / Injection**:
   - Regex matcher mendeteksi pola umum seperti "ignore previous instructions", "system override", "you are now", "abaikan instruksi sebelumnya", dll.
   - Jika terdeteksi, run langsung ditandai `REJECTED_INJECTION`, LLM tidak dipanggil, dan draft ditandai sebagai ambigu.
3. **Privasi PII**:
   - Nomor telepon pelanggan dimask menggunakan fungsi `MaskPhone` (misal `+62812****7890`) dalam log dan audit yang terekspos.

---

## 5. Audit Trail (`agent_runs` Table)

Setiap pemanggilan ekstraksi dicatat ke tabel PostgreSQL `agent_runs`:

| Kolom | Tipe | Keterangan |
| --- | --- | --- |
| `id` | UUID | Primary key run |
| `inbound_message_id` | UUID | Foreign key ke `waha_inbound_messages.id` (nullable) |
| `session` | TEXT | Identifier sesi WAHA |
| `customer_phone` | TEXT | Nomor WhatsApp pengirim |
| `model` | TEXT | Model yang digunakan (misal `hermes-3-llama-3.1-8b`) |
| `prompt_version` | TEXT | Versi prompt (misal `v1.0.0`) |
| `confidence_score` | NUMERIC(3,2) | Skor confidence final (0.00 – 1.00) |
| `is_ambiguous` | BOOLEAN | Menandakan apakah butuh klarifikasi |
| `ambiguity_reasons` | TEXT[] | Daftar alasan jika ambigu |
| `extracted_draft` | JSONB | Snapshot data draft yang diekstrak |
| `tool_calls` | JSONB | Audit pemanggilan tool internal (LLM, catalog) |
| `duration_ms` | INTEGER | Waktu eksekusi pipeline dalam milidetik |
| `status` | TEXT | `SUCCESS`, `AMBIGUOUS`, `FAILED`, `REJECTED_INJECTION` |
| `error_message` | TEXT | Pesan error bila terjadi kegagalan |
| `correlation_id` | TEXT | Correlation ID penelusuran request |
| `created_at` | TIMESTAMPTZ | Waktu eksekusi |

---

## 6. Testing & CI Decoupling

- Semua unit test di `internal/hermes` menggunakan `MockLLMClient` dan `mockCatalogProvider`.
- Tidak ada dependensi ke external LLM provider, GPU, atau network eksternal di CI.
- Integration test `store_integration_test.go` memverifikasi skema dan query PostgreSQL terhadap instance database test terisolasi.
