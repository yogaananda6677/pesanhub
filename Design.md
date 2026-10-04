# Stitch Design Prompt — PesenHub Martabak & Terang Bulan

Copy the complete prompt below into Google Stitch.

---

## Prompt

Design a polished, high-fidelity, responsive point-of-sale and kitchen management application named **PesenHub** for an Indonesian **martabak telur and terang bulan** outlet. This is a redesign of an existing nasi goreng application. Preserve the operational structure and workflows, but replace every nasi goreng-specific visual, product, category, modifier, note, illustration, and piece of copy with content appropriate for martabak and terang bulan.

Create a cohesive multi-screen product, not a marketing website. The application is used by cashiers and kitchen staff during busy evening service. It must feel fast, warm, appetizing, practical, and easy to scan with greasy or busy hands. All interface copy must be in natural Indonesian. Use Indonesian Rupiah formatting such as `Rp28.000`.

### Product identity

- Platform brand: **PesenHub**.
- Outlet name displayed in the header: **Martabak & Terang Bulan Pusat**.
- Product character: warm night-stall atmosphere, freshly baked batter, melted butter, chocolate, cheese, and savory martabak telur.
- Brand personality: friendly, confident, local, modern, dependable, and not overly luxurious.
- Use a simple brand mark inspired by a folded martabak slice inside a rounded square. Do not use a rice bowl, wok, noodles, fried rice, chef mascot, or generic restaurant logo.
- Do not display any nasi goreng, mie goreng, kwetiau, rice, or fried-rice-related content anywhere.

### Visual direction

Use a warm food-oriented visual system:

- Primary / cocoa brown: `#7A321F`.
- Primary dark / toasted crust: `#4B2118`.
- Primary soft: `#F7E8DF`.
- Secondary / butter gold: `#F2A72B`.
- Secondary soft: `#FFF1D2`.
- Accent / pandan green: `#2F7D4A`.
- Background / warm cream: `#FFF8EE`.
- Surface: `#FFFFFF`.
- Surface secondary: `#FFFCF7`.
- Border: `#E9DDD3`.
- Main text: `#2B1B16`.
- Secondary text: `#75645D`.
- Error / overdue: `#C63D32`.
- Information / in production: `#316FC3`.

Use **Plus Jakarta Sans** or a visually similar rounded humanist sans-serif. Use strong, compact headings and highly legible body text. Prices and order numbers should be bold and easy to scan.

Use clean white cards on a warm cream background, thin borders, subtle shadows, and 12–16 px corner radii. Use warm editorial food photography for menu cards: close-up martabak cut into pieces, visible layers, melted cheese, chocolate sprinkles, peanuts, butter sheen, and savory egg filling. Photography should look realistic and appetizing, not like emoji, clip art, or glossy fast-food advertising. Keep photography consistent in lighting and crop.

Avoid excessive gradients, glassmorphism, neon colors, oversized decorative illustrations, cramped cards, and tiny text. Do not make every element pill-shaped. Reserve pills for statuses, filters, and small tags.

### Accessibility and ergonomics

- Every interactive target must be at least 48 × 48 dp.
- Never communicate status by color alone; always combine color with a clear icon and Indonesian label.
- Maintain strong contrast and support text scaling.
- Keep the primary action visible and easy to reach.
- Use concise Indonesian labels suitable for fast operational scanning.
- Use icons consistently: dashboard, point of sale, receipt, cooking pan, menu book, settings, Wi-Fi/cloud, WhatsApp, globe, and cash register.
- Provide visible focus, pressed, disabled, loading, success, warning, offline, and error states.

### Responsive shell

Create designs for these viewports:

1. Mobile portrait: **390 × 844**.
2. Tablet landscape: **1024 × 768**.
3. Desktop operational view: **1440 × 900**.

Desktop and tablet use a dark cocoa left navigation rail with the folded-martabak brand mark at the top. Navigation items are:

- Beranda
- Kasir
- Antrean
- Dapur
- Menu
- Pengaturan

The active navigation item has a cream or white surface and cocoa text. Show a small red number badge on Antrean when new orders exist.

Mobile uses a sticky bottom navigation with five items:

- Beranda
- Kasir
- Antrean
- Dapur
- Lainnya

Place Menu and Pengaturan inside the Lainnya bottom sheet on mobile. Keep a sticky top bar showing the active page title, outlet name, online/offline status, notification button, and user avatar. Use a single-column layout on mobile, split layouts on tablet, and wider grids on desktop.

### Core application states

Use these order statuses throughout the product:

- **Menunggu** — amber clock icon.
- **Diterima** — blue check-circle icon.
- **Sedang Dibuat** — blue cooking icon.
- **Siap Diambil** — green package-check icon.
- **Selesai** — neutral check icon.
- **Ditolak** — red cancel icon.

Use these order sources:

- **Kasir** — point-of-sale icon.
- **Web** — globe icon.
- **WhatsApp** — WhatsApp/chat icon.

Use payment states **Belum Dibayar**, **Sudah Dibayar**, **Gagal**, and **Kedaluwarsa** with both text and icon.

### Realistic menu catalog

Use the following categories and example products across all screens:

#### Martabak Telur

- Martabak Telur Ayam — `Rp32.000`.
- Martabak Telur Bebek — `Rp38.000`.
- Martabak Telur Spesial Daging — `Rp48.000`.
- Martabak Telur Jumbo — `Rp62.000`.

#### Terang Bulan

- Cokelat Kacang Susu — `Rp28.000`.
- Keju Susu — `Rp32.000`.
- Cokelat Keju — `Rp36.000`.
- Pandan Keju — `Rp38.000`.
- Red Velvet Oreo — `Rp42.000`.
- Premium Toblerone Keju — `Rp58.000`.

#### Paket Hemat

- Paket Berdua: Martabak Telur Ayam + Cokelat Kacang — `Rp55.000`.
- Paket Keluarga: Martabak Telur Spesial + Cokelat Keju — `Rp78.000`.

#### Minuman

- Es Teh Manis — `Rp6.000`.
- Teh Hangat — `Rp5.000`.
- Es Jeruk — `Rp9.000`.

Show **Favorit** or **Terlaris** tags on a few products. Show at least one product as **Habis**, dim its image, disable its add action, and keep the “Habis” label clearly visible.

### Product modifier behavior

When a product is selected, open a bottom sheet on mobile and a centered dialog or side panel on tablet/desktop.

For martabak telur, provide:

- Pilihan ukuran: Regular, Spesial, Jumbo.
- Pilihan telur: Ayam or Bebek.
- Jumlah telur: 2, 3, or 4.
- Isian: Daging sapi, ayam, atau campur.
- Tingkat pedas: Tidak Pedas, Sedang, Pedas.
- Extras: Tambah daging `+Rp10.000`, tambah telur `+Rp6.000`, acar ekstra `+Rp3.000`.
- Optional note, for example “acar dipisah, saus pedas banyak”.

For terang bulan, provide:

- Adonan: Original, Pandan `+Rp3.000`, Red Velvet `+Rp5.000`, Black Forest `+Rp5.000`.
- Ukuran: Regular or Jumbo.
- Topping utama with visual selection cards: Cokelat, Kacang, Keju, Oreo, Wijen.
- Premium topping: Toblerone, Nutella, Lotus Biscoff.
- Combination option: Satu rasa or Dua rasa / setengah-setengah.
- Butter option: Normal or Extra butter `+Rp3.000`.
- Optional note, for example “potong 10, susu sedikit, topping dipisah”.

Always show selection requirements, additional prices, quantity control, a live-updating total, and a large **Tambah ke Keranjang** button.

## Required screens

### 1. Beranda / operational dashboard

Create a welcoming but compact operational dashboard.

- Eyebrow: `RINGKASAN OPERASIONAL`.
- Heading: `Selamat malam, Yoga!`.
- Supporting text: `Pantau pesanan martabak dan terang bulan malam ini.`
- Primary button: `Buat pesanan`.
- Three prominent metric cards: `Perlu tindakan`, `Sedang dibuat`, and `Siap diambil`.
- A large **Pesanan aktif** panel sorted by urgency. Each row shows order time, elapsed minutes, customer, source badge, short item summary, and status.
- A **Butuh perhatian** panel for overdue orders. Use an example such as `PH-1261 · Dimas`, `1× Terang Bulan Cokelat Keju`, `18 mnt`.
- Add a subtle operational reminder: `Pastikan acar, saus, dan topping tambahan ikut dikemas.`
- Include online state and an offline banner variation saying queued updates will synchronize automatically.

### 2. Kasir / create order

Design this as the primary POS workflow.

- Heading: `Buat pesanan`.
- Supporting text: `Pilih menu, atur topping, lalu proses pembayaran.`
- Search input: `Cari martabak atau topping...`.
- Horizontally scrollable category filters: Semua, Martabak Telur, Terang Bulan, Paket Hemat, Minuman.
- Product grid with consistent food photos, name, category, price, Favorit/Terlaris tag, availability, and a clear add button.
- Tablet/desktop: use a catalog on the left and a sticky order cart on the right.
- Mobile: use a single catalog column or two-card grid and a sticky bottom cart summary showing number of items and total.
- Cart fields: customer name, takeaway/pickup option, order notes, item modifiers, quantity controls, delete action, subtotal, other fees, and grand total.
- Example cart:
  - `1× Martabak Telur Bebek` with `Spesial · Pedas · Acar dipisah`.
  - `1× Terang Bulan Cokelat Keju` with `Pandan · Dua rasa · Potong 10`.
- Primary action: `Lanjut pembayaran` with the current total.

### 3. Payment and order confirmation

Create a clean modal or bottom sheet opened from the cart.

- Heading: `Pembayaran`.
- Show order summary and total prominently.
- Payment choices: **Tunai** and **QRIS** with large selection cards.
- For cash, provide nominal shortcuts: Uang Pas, Rp50.000, Rp100.000, plus manual input.
- Show `Kembalian` calculation clearly.
- For QRIS, show a realistic QR placeholder, expiration timer, and `Menunggu pembayaran` state.
- Main button: `Bayar & Buat Pesanan`.
- Success state: large check icon, `Pesanan berhasil dibuat`, order number, estimated preparation time, and actions `Lihat antrean` and `Pesanan baru`.

### 4. Antrean pesanan

- Eyebrow: `ANTREAN TERPADU`.
- Heading: `Antrean pesanan`.
- Supporting text: `Kasir, Web, dan WhatsApp dalam satu tempat.`
- Status filters: Aktif, Menunggu, Diterima, Sedang Dibuat, Siap Diambil, Selesai, Semua.
- Search input: `Cari nama atau nomor order`.
- Desktop: three-column responsive order card grid.
- Mobile: single-column cards.
- Each card shows order number, source badge, elapsed time, customer, payment state, status, item list, modifiers, note, total, `Lihat detail`, and the next status action.
- Example orders must only use martabak and terang bulan products.
- Flag overdue orders with a red left border plus the explicit label `Terlambat`, not color alone.

### 5. Detail order

Create a side drawer on desktop and full-height bottom sheet or page on mobile.

- Show order number, customer, source, payment state, and order timeline.
- Item lines must expose production-critical modifiers in bold: dough flavor, egg type/count, size, topping combination, cut count, spice level, sauce, and packaging notes.
- Show timestamps for Dipesan, Diterima, Sedang Dibuat, Siap Diambil, and Selesai.
- Include a clear next-step action such as `Mulai buat`, `Tandai siap`, or `Selesaikan pesanan`.
- Destructive action `Tolak pesanan` must be secondary, red, and require confirmation.

### 6. Dapur / kitchen display system

Design a tablet-first production board readable from a distance.

- Eyebrow: `MODE DAPUR`.
- Heading: `Produksi martabak`.
- Supporting text: `Tiket besar untuk produksi martabak telur dan terang bulan.`
- Three horizontal Kanban columns: **Baru**, **Sedang Dibuat**, and **Siap Diambil**.
- Each column shows its count and uses a distinct icon and semantic color.
- Kitchen ticket hierarchy: elapsed time and order number first; then product name and quantity; then modifiers and special notes.
- Add a product-type badge: `MARTABAK TELUR`, `TERANG BULAN`, or `MINUMAN`.
- Highlight critical notes such as `TELUR BEBEK`, `PEDAS`, `DUA RASA`, `POTONG 10`, `ACAR DIPISAH`, or `TANPA SUSU` using high-contrast text labels.
- Example ticket: `2× Martabak Telur Bebek`, `Jumbo · 4 telur · Pedas`, note `Acar dan saus dipisah`.
- Example ticket: `1× Terang Bulan Pandan Keju`, `Dua rasa: Keju / Cokelat Kacang`, note `Potong 10 · Extra butter`.
- Use full-width action buttons on each ticket: `Mulai buat`, `Tandai siap`, or `Serahkan pesanan`.
- On mobile, keep columns horizontally scrollable with snap behavior rather than squeezing ticket content.

### 7. Menu and availability management

- Eyebrow: `KETERSEDIAAN HARI INI`.
- Heading: `Menu outlet`.
- Supporting text: `Matikan menu atau topping yang habis agar tidak dapat dipesan.`
- Show count summary such as `11 dari 13 tersedia`.
- Search and category filters.
- Each menu row/card shows thumbnail, product name, SKU, category, price, availability switch, explicit Tersedia/Habis label, and Edit action.
- Add a secondary section named **Stok topping penting** with availability rows for Keju, Cokelat, Kacang, Oreo, Telur Bebek, Daging Sapi, Nutella, and Lotus Biscoff.
- Changing availability triggers a success toast such as `Pandan Keju sekarang ditandai Habis.`

### 8. Pengaturan outlet

- Outlet profile: name, address, telephone, receipt footer, and operating hours.
- WhatsApp order connection card with Connected/Disconnected status and pairing action.
- Printer and kitchen display device cards.
- Network and synchronization status.
- Account section with staff identity and sign-out action.
- Keep this screen visually quieter than operational screens.

## Components and interaction details

- Buttons: primary cocoa, secondary outlined, tertiary text, and destructive red.
- Cards: clear grouping, thin warm border, subtle shadow, and minimal decoration.
- Status badges: icon + text, semantic background, compact but readable.
- Toasts: success, information, warning, and error variants.
- Empty state example: `Belum ada pesanan — Pesanan baru akan muncul di sini.`
- Loading state: skeleton cards that match the final layout.
- Error state: actionable explanation and `Coba lagi` button.
- Confirmation dialogs for rejecting an order, clearing the cart, signing out, and disabling a menu item.
- Use realistic content throughout instead of lorem ipsum.

## Final output requirements

Produce a unified design system and high-fidelity screens for all required flows. Show at least one mobile frame and one tablet/desktop frame for the most important screens: Beranda, Kasir, Antrean, and Dapur. Include the product modifier sheet, payment modal, order detail, offline state, empty state, and sold-out menu state.

The result must look like a real production POS/KDS product for a busy Indonesian martabak outlet. It must not look like a food-delivery customer app, restaurant landing page, analytics-only dashboard, or generic admin template. Prioritize speed, legibility, order accuracy, and clear cooking instructions.

---

## Quick review checklist

- No nasi goreng, rice, noodles, wok, or old menu references remain.
- Martabak telur and terang bulan have different, realistic modifier flows.
- Food images are consistent and specific to the products.
- Mobile, tablet, and desktop layouts preserve the same information hierarchy.
- Order, payment, source, connectivity, and availability states use icon plus text.
- Kitchen tickets emphasize size, egg count/type, dough, toppings, cut count, sauce, and packaging notes.
- Primary actions are reachable and touch targets are at least 48 × 48 dp.
- All UI copy is in Indonesian and all money uses Indonesian Rupiah formatting.
