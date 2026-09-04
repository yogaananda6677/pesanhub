# Hermes Guided Clarification Engine & Conversation Policy

## 1. Ringkasan Fitur

Ketika pelanggan mengirimkan pesanan yang memiliki ketidakjelasan (*ambiguous*) atau informasi yang belum lengkap, Hermes tidak langsung membuat order, tidak menebak preferensi wajib, dan tidak mengajukan banyak pertanyaan sekaligus yang membingungkan pelanggan. 

Melalui **Guided Clarification Engine** (Issue #39):
1. **Satu Pertanyaan Per Turn**: Memilih satu ambiguitas paling memblokir (*highest priority blocking ambiguity*).
2. **Opsi Terstruktur dari Katalog**: Menyertakan pilihan opsi riil yang tersedia di katalog (misal varian level pedas aktif).
3. **Penggabungan Parsial Non-Destruktif**: Jawaban pelanggan hanya memperbarui field terkait tanpa mereset atau menghapus menu/porsi lain yang sudah benar.
4. **Revalidasi Real-Time Katalog Backend**: Setiap turn memverifikasi ulang apakah item dan modifier di draft masih tersedia (`is_available = true`). Jika ada menu yang mendadak habis, sistem langsung mendeteksi dan meminta klarifikasi penggantian menu.
5. **Bounded Retry & Human Handoff**: Percobaan klarifikasi dibatasi maksimal 3 kali (`MaxClarificationAttempts = 3`). Jika gagal mencapai kesepahaman, percakapan otomatis dialihkan ke staf kasir manusia (`HANDOFF`).
6. **State Persistence**: State percakapan dicatat secara persisten ke tabel PostgreSQL `agent_conversations`.

```
[Inbound WhatsApp Message]
            │
            ▼
   [Prompt Injection Check] ──(Injected)──► [Handoff ke Staf Manusia]
            │ (Safe)
            ▼
    [Conversation State]
            ├── Status: COLLECTING
            │      └── Jalankan ExtractOrder
            │             ├── Ambigu ──► [PlanClarification] ──► Kirim 1 Pertanyaan Prioritas
            │             └── Lengkap ──► Siap Konfirmasi
            │
            └── Status: AWAITING_CLARIFICATION
                   └── [DraftMerger]
                          ├── Merge Jawaban Pelanggan ke Draft
                          ├── Revalidasi Katalog Backend
                          │      └── Menu Habis? ──► Tanyakan Penggantian Menu
                          ├── Masih Ambigu?
                          │      ├── Attempts < 3 ──► Kirim Pertanyaan Klarifikasi Berikutnya
                          │      └── Attempts >= 3 ──► [Trigger Human Handoff]
                          └── Selesai & Lengkap ──► [READY_FOR_CONFIRMATION] Ringkasan Order
```

---

## 2. Hierarki Prioritas Pertanyaan Klarifikasi

Ketika terdapat beberapa data yang belum lengkap atau ambigu, sistem memprioritaskan pertanyaan berdasarkan urutan dampak:

| Peringkat | Jenis Ambiguitas | Contoh Skenario | Template Pertanyaan |
| --- | --- | --- | --- |
| 1 | `menu_unavailable` | Menu habis / out of stock | *"Mohon maaf kak, menu [Nama Menu] saat ini sedang habis. Apakah mau diganti dengan menu lain atau dibatalkan kak?"* |
| 2 | `menu_not_found` | Menu tidak ada di katalog | *"Mohon maaf kak, menu [Nama Menu] belum ada di daftar menu kami. Bisa tolong sebutkan pilihan menu lainnya kak?"* |
| 3 | `missing_required_modifier` | Level pedas / varian wajib (`min_select >= 1`) belum dipilih | *"Untuk [Nama Menu], mau pilih varian [Grup Modifier] apa kak? ([Opsi 1] / [Opsi 2] / [Opsi 3])"* |
| 4 | `invalid_quantity` | Jumlah porsi 0 atau tidak valid | *"Mau pesan [Nama Menu] berapa porsi kak?"* |
| 5 | `unrecognized_modifier` | Topping / permintaan di luar grup | *"Untuk pilihan [Nama Modifier], saat ini tidak tersedia di menu kami. Apakah mau tetap pesan tanpa [Nama Modifier] kak?"* |
| 6 | `empty_order_items` | Pesan salam atau bukan order | *"Halo kak! Ada yang bisa kami bantu? Mau pesan makanan atau minuman apa hari ini?"* |
| 7 | `missing_fulfillment_type` | Tipe pengambilan belum dipilih | *"Pesanannya mau diambil sendiri (Takeaway/Pickup) atau makan di tempat (Dine In) kak?"* |
| 8 | `missing_payment_method` | Metode pembayaran belum dipilih | *"Untuk pembayarannya mau pakai Tunai (Cash) di kasir atau QRIS kak?"* |

---

## 3. Kebijakan Update Non-Destruktif (`DraftMerger`)

- Ketika pelanggan menjawab, misalnya `"pedas ya"`:
  - `DraftMerger` mencocokkan teks jawaban ke opsi grup modifier terkait.
  - Menghitung ulang harga baris menggunakan data katalog backend resmi:
    `LineTotalAmount = (UnitPriceAmount + ModifiersTotalAmount) * Quantity`
  - Memperbarui subtotal: `SubtotalAmount = sum(LineTotalAmount)`.
  - Menghapus flag `missing_required_modifier` dari daftar ambiguitas.
  - Catatan khusus (*notes*), item menu lain, dan jumlah porsi yang sudah benar **tetap dipertahankan**.

---

## 4. Bounded Retry & Human Handoff

- Ambang batas percobaan klarifikasi:
  ```go
  const MaxClarificationAttempts = 3
  ```
- Jika pelanggan menjawab dengan teks yang tidak dapat dikenali berulang kali (`attempts >= 3`):
  - Sistem menghentikan loop klarifikasi otonom.
  - Status percakapan berubah menjadi `HANDOFF`.
  - Pesan balasan:
    *"Mohon maaf kak, agar pesanannya tidak salah paham, percakapan ini kami teruskan ke staf kami ya. Mohon ditunggu sebentar."*
  - Kasir / staf outlet dapat mengambil alih percakapan (Issue #40).

---

## 5. Persistence State Percakapan (`agent_conversations`)

State percakapan disimpan pada tabel PostgreSQL `agent_conversations`:

| Kolom | Tipe | Deskripsi |
| --- | --- | --- |
| `id` | UUID | Primary key percakapan |
| `session` | TEXT | Nama sesi GOWA (default: `default`) |
| `customer_phone` | TEXT | Nomor telepon pengirim (E.164) |
| `status` | TEXT | `COLLECTING`, `AWAITING_CLARIFICATION`, `READY_FOR_CONFIRMATION`, `HANDOFF` |
| `current_draft` | JSONB | Data `DraftCandidate` yang sedang diisi |
| `pending_ambiguity` | TEXT | Ambiguitas yang sedang ditanyakan saat ini |
| `clarification_attempts` | INTEGER | Jumlah percobaan klarifikasi berturut-turut |
| `last_question` | TEXT | Teks pertanyaan terakhir yang dikirim ke pelanggan |
| `last_inbound_message_id` | UUID | Relasi ke pesan GOWA terakhir |
| `correlation_id` | TEXT | ID penelusuran request |
| `created_at` / `updated_at` | TIMESTAMPTZ | Waktu pembuatan & pembaruan |

Constraint: `UNIQUE (session, customer_phone)` memastikan satu nomor pelanggan memiliki satu sesi aktif yang konsisten.

---

## 6. Testing & CI Decoupling

- Seluruh alur klarifikasi dan merging diuji dengan mock provider katalog dan in-memory conversation store (`service_clarification_test.go`, `merger_test.go`, `clarification_test.go`).
- Tidak membutuhkan koneksi model LLM eksternal atau GPU.
- Integration test PostgreSQL memverifikasi skema database tabel `agent_conversations` dan query upsert/reset.
