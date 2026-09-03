# PesenHub Menu Search, Category Filter, and Modifiers

Dokumen ini mendokumentasikan spesifikasi implementasi pencarian menu dengan debounce, filter kategori, penanda ketersediaan item (*availability state*), konfigurasi modifier (*level kepedasan*, *topping*, *varian manis*) sesuai batasan backend, kalkulasi harga dinamis, dan layout responsif pada aplikasi kasir PesenHub ([Issue #27](https://github.com/yogaananda6677/pesanhub/issues/27)).

---

## 1. Latar Belakang & Kebutuhan Desain

Kasir outlet nasi goreng merangkap berbagai tugas fisik (memasak, meracik minuman, membungkus pesanan).
Katalog pemesanan POS/KDS membutuhkan:
1. **Pencarian Cepat Tanpa Lag**: Kasir dapat mengetik nama menu atau SKU (misal *"Gila"*, *"Seafood"*, *"ESTEH"*) dan hasil terfilter seketika dengan debounce 250ms tanpa menurunkan performa UI.
2. **Filter Kategori Terarah**: Tab filter kategori (*Semua*, *Makanan*, *Minuman*, *Tambahan*) dengan counter jumlah item untuk pemindaian instan.
3. **Pencegahan Penjualan Item Habis**: Item dengan status `is_available == false` diberi badge *"Habis"*, visual sedikit redup, dan tombol tambah dinonaktifkan sehingga tidak bisa dimasukkan ke pesanan.
4. **Validasi Modifier & Level Pedas (Backend Constraints)**:
   - Sesuai kontrak backend `pesenhub_be/internal/catalog`:
     - `min_select == 1 && max_select == 1` (*Required Single-Select*): Contohnya level kepedasan (Level 0–5) atau pilihan manis (Normal, Less Sugar, Tanpa Gula). Wajib dipilih salah satu sebelum item dapat dimasukkan ke pesanan.
     - `min_select == 0 && max_select == 3` (*Optional Multi-Select*): Contohnya topping tambahan (Telur Ceplok, Sosis, Bakso, dll). Sistem membatasi kasir agar tidak memilih melebihi batas maksimal.
     - Opsi modifier yang tidak tersedia (`is_available == false`, misal: *Teri Medan*) otomatis dinonaktifkan dengan tanda *(Habis)*.
5. **Kalkulasi Harga Dinamis**:
   - `totalPrice = (basePrice + sum(selectedModifiers.priceDelta)) * quantity`.
   - Tombol stepper kuantitas (- / +) dengan batas minimal 1.
6. **Konsistensi State & Responsif**:
   - Pilihan kategori, query pencarian, dan dialog modifier tetap konsisten saat orientasi layar berganti antara portrait dan landscape.
   - Grid adaptif: 2 kolom pada ponsel (< 600dp) dan 3 kolom pada tablet (>= 600dp), bebas dari *RenderFlex overflow*.

---

## 2. Struktur Data & Model

| Model | File | Keterangan |
|---|---|---|
| `MenuCategory` | `lib/menu/models/menu_category.dart` | Kategori menu (`id`, `name`, `sortOrder`, `isActive`). |
| `MenuOption` | `lib/menu/models/menu_option.dart` | Opsi modifier (`id`, `code`, `name`, `priceDeltaAmount`, `isAvailable`). |
| `MenuModifierGroup` | `lib/menu/models/menu_modifier_group.dart` | Grup modifier (`id`, `code`, `name`, `minSelect`, `maxSelect`, `options`). |
| `MenuItem` | `lib/menu/models/menu_item.dart` | Item menu (`id`, `categoryId`, `sku`, `name`, `priceAmount`, `isAvailable`, `modifierGroups`, `isDrink`). |
| `MenuState` | `lib/menu/models/menu_state.dart` | Presentation states: `loading`, `success`, `empty`, `error`. |

---

## 3. Controller & Logika State

### 3.1 `MenuController` (`lib/menu/controllers/menu_controller.dart`)
- **Debounce Search**: Menggunakan `Timer` 250ms pada `onSearchChanged(query)`.
- **Category Filter**: `selectCategory(categoryId)` memfilter daftar berdasarkan ID kategori.
- **Getter `filteredMenus`**: Mengembalikan item yang sesuai dengan kategori aktif dan kata kunci pencarian, diurutkan berdasarkan `sortOrder`.

### 3.2 `ModifierSelectionState` (`lib/menu/controllers/modifier_selection_state.dart`)
- **Validasi Constraint**:
  - `isGroupValid(group)` memeriksa `count >= group.minSelect && count <= group.maxSelect`.
  - `validationErrors` menyajikan pesan kesalahan visual jika required modifier belum dipilih atau batas maksimum terlampaui.
  - `isValid` memastikan seluruh grup modifier aktif memenuhi syarat.
- **Harga Dinamis**:
  - `unitPrice` mengakumulasikan harga dasar menu ditambah seluruh selisih harga opsi modifier terpilih (`priceDeltaAmount`).
  - `totalPrice = unitPrice * quantity`.

---

## 4. Komponen UI

1. **`MenuItemCard` (`lib/menu/widgets/menu_item_card.dart`)**:
   - Menampilkan nama item, ikon minuman (jika `isDrink`), deskripsi, harga dasar, badge "Habis", dan tombol aksi "+ Tambah" atau "+ Kustom".
   - Tata letak harga dan tombol disusun vertikal (*stacked*) agar tahan terhadap *RenderFlex overflow* pada kolom mobile sempit.
2. **`MenuCategoryFilter` (`lib/menu/widgets/menu_category_filter.dart`)**:
   - Bar chip filter kategori horizontal yang menampilkan badge counter item per kategori secara dinamis.
3. **`ModifierConfigDialog` (`lib/menu/widgets/modifier_config_dialog.dart`)**:
   - Modal adaptif: `showModalBottomSheet` pada ponsel dan `showDialog` terpusat pada tablet.
   - Pilihan radio/chips untuk level pedas, checkbox/chips untuk topping tambahan, stepper kuantitas, catatan khusus pesanan, dan tombol "Tambah ke Pesanan" yang dinonaktifkan jika pilihan wajib belum lengkap.
4. **`MenuCatalogView` (`lib/menu/menu_catalog_view.dart`)**:
   - Tampilan katalog terpadu dengan kolom pencarian, filter kategori, grid item, dan penanganan state *Loading*, *Empty*, serta *Error*.

---

## 5. Verifikasi & Pengujian

Telah teruji melalui `test/menu_catalog_test.dart` (7 test cases):
- **Criteria #1**: Pencarian dengan debounce dan filter kategori menyaring item secara akurat.
- **Criteria #2**: Item yang tidak tersedia (*unavailable*) menampilkan badge "Habis" dan tidak dapat ditambahkan.
- **Criteria #3**: Validasi required modifier (level pedas wajib dipilih) dan batas topping berjalan dengan benar; kalkulasi harga dinamis akurat.
- **Criteria #4**: Status pencarian dan filter kategori tetap terjaga saat rotasi viewport.
- **Criteria #5**: Seluruh presentation states (loading, empty, error) serta responsivitas mobile dan tablet terverifikasi tanpa layout overflow.
