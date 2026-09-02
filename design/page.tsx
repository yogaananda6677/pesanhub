"use client";

import {
  Bell, BellRing, Check, CheckCircle2, ChevronRight, CircleDollarSign,
  Clock3, Coffee, CookingPot, LayoutDashboard, Menu as MenuIcon, Minus,
  PackageCheck, Plus, ReceiptText, Search, Settings, ShoppingBag,
  Smartphone, WalletCards, Wifi, WifiOff, X,
} from "lucide-react";
import { useEffect, useState } from "react";
import Image from "next/image";

type View = "home" | "orders" | "new" | "kds" | "menu";
type OrderStatus = "Menunggu" | "Diterima" | "Sedang Dibuat" | "Siap Diambil" | "Selesai";
type OrderSource = "Kasir" | "Web" | "WhatsApp";
type Order = { id: string; customer: string; source: OrderSource; status: OrderStatus; time: string; elapsed: number; total: number; paid: boolean; items: string[]; note?: string };
type Product = { id: number; name: string; price: number; category: string; icon: string; image?: string; available: boolean; popular?: boolean };
type CartLine = Product & { qty: number; spicy?: string };

const money = (amount: number) => new Intl.NumberFormat("id-ID", { style: "currency", currency: "IDR", maximumFractionDigits: 0 }).format(amount);

const products: Product[] = [
  { id: 1, name: "Nasi Goreng Spesial", price: 25000, category: "Nasi Goreng", icon: "🍳", image: "https://www.indonesia.travel/contentassets/28e768566967404c84215e2a3b94b22a/nasi-goreng.jpg", available: true, popular: true },
  { id: 2, name: "Nasi Goreng Biasa", price: 18000, category: "Nasi Goreng", icon: "🍚", available: true },
  { id: 3, name: "Nasi Goreng Mawut", price: 22000, category: "Nasi Goreng", icon: "🥘", available: true },
  { id: 4, name: "Mie Goreng Jawa", price: 19000, category: "Mie & Kwetiau", icon: "🍜", available: true, popular: true },
  { id: 5, name: "Kwetiau Goreng", price: 21000, category: "Mie & Kwetiau", icon: "🥡", available: true },
  { id: 6, name: "Es Teh Manis", price: 5000, category: "Minuman", icon: "🧋", available: true },
  { id: 7, name: "Jeruk Hangat", price: 7000, category: "Minuman", icon: "🍊", available: true },
  { id: 8, name: "Kerupuk", price: 3000, category: "Tambahan", icon: "🥠", available: true },
  { id: 9, name: "Telur Mata Sapi", price: 5000, category: "Tambahan", icon: "🍳", available: true },
  { id: 10, name: "Ati Ampela", price: 7000, category: "Tambahan", icon: "🍢", available: false },
];

const initialOrders: Order[] = [
  { id: "PH-1258", customer: "Rina", source: "WhatsApp", status: "Menunggu", time: "12:06", elapsed: 3, total: 49000, paid: false, items: ["2× Nasi Goreng Spesial", "1× Es Teh Manis"], note: "Satu tidak pedas, tanpa acar" },
  { id: "PH-1257", customer: "Budi", source: "Web", status: "Sedang Dibuat", time: "11:54", elapsed: 15, total: 37000, paid: true, items: ["1× Nasi Goreng Mawut", "1× Jeruk Hangat", "1× Kerupuk"], note: "Pedas" },
  { id: "PH-1256", customer: "Pelanggan umum", source: "Kasir", status: "Siap Diambil", time: "11:50", elapsed: 19, total: 24000, paid: true, items: ["1× Mie Goreng Jawa", "1× Es Teh Manis"] },
  { id: "PH-1255", customer: "Ayu", source: "WhatsApp", status: "Diterima", time: "11:59", elapsed: 10, total: 43000, paid: false, items: ["2× Nasi Goreng Biasa", "1× Es Teh Manis"], note: "Bungkus, sendok 2" },
];

const navItems = [
  { id: "home" as View, label: "Beranda", icon: LayoutDashboard },
  { id: "orders" as View, label: "Antrean", icon: ReceiptText },
  { id: "new" as View, label: "Pesanan", icon: Plus },
  { id: "kds" as View, label: "Dapur", icon: CookingPot },
  { id: "menu" as View, label: "Menu", icon: MenuIcon },
];
const nextStatus: Partial<Record<OrderStatus, OrderStatus>> = { Menunggu: "Diterima", Diterima: "Sedang Dibuat", "Sedang Dibuat": "Siap Diambil", "Siap Diambil": "Selesai" };
const nextLabel: Partial<Record<OrderStatus, string>> = { Menunggu: "Terima pesanan", Diterima: "Mulai masak", "Sedang Dibuat": "Tandai siap", "Siap Diambil": "Selesaikan" };

function SourceBadge({ source }: { source: OrderSource }) { return <span className={`source-badge source-${source.toLowerCase()}`}>{source}</span>; }
function StatusPill({ status }: { status: OrderStatus }) { return <span className={`status-pill status-${status.toLowerCase().replaceAll(" ", "-")}`}>{status}</span>; }
function EmptyState({ icon, title, copy }: { icon: string; title: string; copy: string }) { return <div className="empty-state"><span>{icon}</span><strong>{title}</strong><p>{copy}</p></div>; }

export default function Home() {
  const [view, setView] = useState<View>("home");
  const [orders, setOrders] = useState(initialOrders);
  const [filter, setFilter] = useState("Aktif");
  const [category, setCategory] = useState("Semua");
  const [query, setQuery] = useState("");
  const [cart, setCart] = useState<CartLine[]>([{ ...products[0], qty: 1, spicy: "Sedang" }, { ...products[5], qty: 1 }]);
  const [selectedProduct, setSelectedProduct] = useState<Product | null>(null);
  const [spicy, setSpicy] = useState("Sedang");
  const [customer, setCustomer] = useState("");
  const [orderNote, setOrderNote] = useState("");
  const [paymentOpen, setPaymentOpen] = useState(false);
  const [paymentMethod, setPaymentMethod] = useState<"Tunai" | "QRIS">("Tunai");
  const [cash, setCash] = useState(100000);
  const [detail, setDetail] = useState<Order | null>(null);
  const [incoming, setIncoming] = useState(false);
  const [online, setOnline] = useState(true);
  const [toast, setToast] = useState("");
  const [availability, setAvailability] = useState<Record<number, boolean>>(Object.fromEntries(products.map((p) => [p.id, p.available])));

  useEffect(() => { const timer = window.setTimeout(() => setIncoming(true), 4500); return () => window.clearTimeout(timer); }, []);
  useEffect(() => { if (!toast) return; const timer = window.setTimeout(() => setToast(""), 2600); return () => window.clearTimeout(timer); }, [toast]);

  const activeOrders = orders.filter((o) => o.status !== "Selesai");
  const metrics = {
    waiting: orders.filter((o) => o.status === "Menunggu" || o.status === "Diterima").length,
    cooking: orders.filter((o) => o.status === "Sedang Dibuat").length,
    ready: orders.filter((o) => o.status === "Siap Diambil").length,
  };
  const cartTotal = cart.reduce((sum, line) => sum + line.price * line.qty, 0);
  const filteredProducts = products.filter((p) => (category === "Semua" || p.category === category) && p.name.toLowerCase().includes(query.toLowerCase()));
  const filteredOrders = orders.filter((order) => filter === "Aktif" ? order.status !== "Selesai" : filter === "Semua" ? true : order.status === filter);

  function showToast(message: string) { setToast(message); }
  function advanceOrder(id: string) {
    setOrders((current) => current.map((order) => {
      if (order.id !== id || !nextStatus[order.status]) return order;
      const updated = { ...order, status: nextStatus[order.status]! };
      if (detail?.id === id) setDetail(updated);
      showToast(`${id} dipindahkan ke ${updated.status}`);
      return updated;
    }));
  }
  function quickAdd(product: Product) {
    if (!availability[product.id]) return;
    if (["Nasi Goreng", "Mie & Kwetiau"].includes(product.category)) { setSelectedProduct(product); setSpicy("Sedang"); return; }
    addToCart(product, "");
  }
  function addToCart(product: Product, level: string) {
    setCart((current) => {
      const index = current.findIndex((line) => line.id === product.id && line.spicy === (level || undefined));
      if (index >= 0) return current.map((line, i) => i === index ? { ...line, qty: line.qty + 1 } : line);
      return [...current, { ...product, qty: 1, spicy: level || undefined }];
    });
    setSelectedProduct(null); showToast(`${product.name} ditambahkan`);
  }
  function changeQty(index: number, delta: number) {
    setCart((current) => current.flatMap((line, i) => i !== index ? [line] : line.qty + delta > 0 ? [{ ...line, qty: line.qty + delta }] : []));
  }
  function completePayment() {
    const newOrder: Order = {
      id: `PH-${1259 + orders.length}`, customer: customer || "Pelanggan umum", source: "Kasir", status: "Diterima",
      time: new Date().toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" }), elapsed: 0, total: cartTotal, paid: true,
      items: cart.map((line) => `${line.qty}× ${line.name}${line.spicy ? ` · ${line.spicy}` : ""}`), note: orderNote || undefined,
    };
    setOrders((current) => [newOrder, ...current]); setCart([]); setCustomer(""); setOrderNote(""); setPaymentOpen(false); setView("orders"); showToast(`${newOrder.id} berhasil dibuat`);
  }
  function acceptIncoming() {
    const newOrder: Order = { id: "PH-1264", customer: "Siti Rahma", source: "WhatsApp", status: "Diterima", time: "12:08", elapsed: 0, total: 38000, paid: false, items: ["1× Nasi Goreng Spesial · Pedas", "1× Es Teh Manis", "1× Kerupuk"], note: "Bungkus, tanpa acar" };
    setOrders((current) => current.some((o) => o.id === newOrder.id) ? current : [newOrder, ...current]); setIncoming(false); setView("orders"); showToast("Pesanan WhatsApp diterima");
  }

  return (
    <main className="app-shell">
      <aside className="side-nav" aria-label="Navigasi utama">
        <div className="brand-mark">PH</div>
        <div className="nav-stack">{navItems.map(({ id, label, icon: Icon }) => <button key={id} className={`nav-item ${view === id ? "active" : ""}`} onClick={() => setView(id)}><Icon size={21} strokeWidth={2.2} /><span>{label}</span>{id === "orders" && metrics.waiting > 0 && <b>{metrics.waiting}</b>}</button>)}</div>
        <button className="nav-item settings-item" onClick={() => showToast("Pengaturan tersedia pada fase berikutnya")}><Settings size={21} /><span>Atur</span></button>
      </aside>

      <section className="workspace">
        <header className="topbar">
          <div className="topbar-title"><div className="mobile-brand">PH</div><div><strong>PesenHub</strong><span>Outlet Sudirman · Buka</span></div></div>
          <div className="topbar-actions"><button className={`connection ${online ? "online" : "offline"}`} onClick={() => setOnline((value) => !value)}>{online ? <Wifi size={16} /> : <WifiOff size={16} />}<span>{online ? "Online" : "Offline · 2 belum sinkron"}</span></button><button className="icon-btn" aria-label="Notifikasi" onClick={() => setIncoming(true)}><Bell size={19} /><i /></button><button className="avatar">YS</button></div>
        </header>
        {!online && <div className="offline-banner"><WifiOff size={17} /> Data tersimpan di perangkat. Sinkronisasi otomatis saat internet kembali.</div>}

        <div className="content">
          {view === "home" && <div className="view-stack">
            <section className="welcome-row"><div><p className="eyebrow">Rabu, 2 September · Shift siang</p><h1>Halo, Yoga! 👋</h1><p>Fokus berikutnya sudah diurutkan untukmu.</p></div><button className="primary-btn" onClick={() => setView("new")}><Plus size={19} /> Buat pesanan</button></section>
            <section className="metric-grid" aria-label="Ringkasan antrean">
              <button className="metric-card waiting" onClick={() => { setFilter("Aktif"); setView("orders"); }}><span className="metric-icon"><Clock3 /></span><div><span>Perlu tindakan</span><strong>{metrics.waiting}</strong><small>menunggu diterima</small></div><ChevronRight /></button>
              <button className="metric-card cooking" onClick={() => { setFilter("Sedang Dibuat"); setView("orders"); }}><span className="metric-icon"><CookingPot /></span><div><span>Sedang dibuat</span><strong>{metrics.cooking}</strong><small>di dapur sekarang</small></div><ChevronRight /></button>
              <button className="metric-card ready" onClick={() => { setFilter("Siap Diambil"); setView("orders"); }}><span className="metric-icon"><PackageCheck /></span><div><span>Siap diambil</span><strong>{metrics.ready}</strong><small>segera serahkan</small></div><ChevronRight /></button>
            </section>
            <section className="home-grid">
              <div className="panel"><div className="panel-heading"><div><h2>Pesanan aktif</h2><p>Urutan berdasarkan yang paling mendesak</p></div><button className="text-btn" onClick={() => setView("orders")}>Lihat semua <ChevronRight size={16} /></button></div><div className="compact-orders">{activeOrders.slice().sort((a, b) => b.elapsed - a.elapsed).map((order) => <article className="compact-order" key={order.id} onClick={() => setDetail(order)}><div className="order-time"><strong>{order.time}</strong><span>{order.elapsed} mnt</span></div><div className="order-main"><div><b>{order.customer}</b><SourceBadge source={order.source} /></div><p>{order.items.join(" · ")}</p></div><StatusPill status={order.status} /><ChevronRight size={17} /></article>)}</div></div>
              <div className="attention-panel"><div className="attention-title"><BellRing size={19} /><div><h2>Butuh perhatian</h2><p>Jangan sampai pesanan ini terlambat.</p></div></div>{activeOrders.filter((order) => order.elapsed >= 12).map((order) => <article className="attention-card" key={order.id}><div><SourceBadge source={order.source} /><span className="late-time">{order.elapsed} mnt</span></div><h3>{order.id} · {order.customer}</h3><p>{order.items[0]}</p><button onClick={() => advanceOrder(order.id)}>{nextLabel[order.status]} <ChevronRight size={17} /></button></article>)}<div className="shift-note"><Coffee size={18} /><p><strong>Pengingat operasional</strong> Cek minuman sebelum menyerahkan pesanan siap.</p></div></div>
            </section>
          </div>}

          {view === "orders" && <div className="view-stack">
            <section className="page-heading"><div><p className="eyebrow">ANTREAN TERPADU</p><h1>Antrean pesanan</h1><p>Kasir, Web, dan WhatsApp dalam satu tempat.</p></div><button className="primary-btn" onClick={() => setView("new")}><Plus size={19} /> Pesanan baru</button></section>
            <section className="filter-bar"><div className="filter-scroll">{["Aktif", "Menunggu", "Diterima", "Sedang Dibuat", "Siap Diambil", "Selesai", "Semua"].map((item) => <button key={item} className={filter === item ? "active" : ""} onClick={() => setFilter(item)}>{item}{item === "Aktif" && <span>{activeOrders.length}</span>}</button>)}</div><label className="search-box"><Search size={18} /><input placeholder="Cari nama atau nomor order" /></label></section>
            <section className="order-board">{filteredOrders.length === 0 ? <EmptyState icon="✓" title="Tidak ada pesanan" copy="Antrean untuk status ini sedang kosong." /> : filteredOrders.map((order) => <article className={`order-card ${order.elapsed >= 12 && order.status !== "Siap Diambil" ? "late" : ""}`} key={order.id}><div className="order-card-head"><div><strong>{order.id}</strong><SourceBadge source={order.source} /></div><span className="elapsed"><Clock3 size={15} /> {order.elapsed} mnt</span></div><div className="order-customer"><div className="customer-avatar">{order.customer.charAt(0)}</div><div><h3>{order.customer}</h3><p>{order.time} · {order.paid ? "Sudah dibayar" : "Belum dibayar"}</p></div><StatusPill status={order.status} /></div><ul>{order.items.map((item) => <li key={item}>{item}</li>)}</ul>{order.note && <p className="order-note">Catatan: {order.note}</p>}<div className="order-total"><span>Total</span><strong>{money(order.total)}</strong></div><div className="card-actions"><button className="secondary-btn" onClick={() => setDetail(order)}>Lihat detail</button>{nextStatus[order.status] && <button className="primary-btn" onClick={() => advanceOrder(order.id)}>{nextLabel[order.status]} <ChevronRight size={17} /></button>}</div></article>)}</section>
          </div>}

          {view === "new" && <div className="order-entry">
            <section className="catalog-area"><div className="page-heading compact"><div><p className="eyebrow">PESANAN KASIR</p><h1>Buat pesanan</h1><p>Pilih menu, cek ringkasan, lalu bayar.</p></div></div><div className="catalog-tools"><label className="search-box grow"><Search size={18} /><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Cari menu..." /></label></div><div className="category-tabs">{["Semua", "Nasi Goreng", "Mie & Kwetiau", "Minuman", "Tambahan"].map((item) => <button key={item} className={category === item ? "active" : ""} onClick={() => setCategory(item)}>{item}</button>)}</div><div className="product-grid">{filteredProducts.map((product) => <button key={product.id} className={`product-card ${!availability[product.id] ? "sold-out" : ""}`} onClick={() => quickAdd(product)} disabled={!availability[product.id]}><div className={`product-photo ${product.image ? "has-image" : ""}`}>{product.image ? <Image src={product.image} alt="Nasi goreng dengan telur dan pelengkap" fill sizes="(max-width: 600px) 50vw, 220px" unoptimized /> : <span>{product.icon}</span>}{product.popular && <b>Favorit</b>}{!availability[product.id] && <em>Habis</em>}</div><div className="product-info"><div><strong>{product.name}</strong><span>{product.category}</span></div><footer><b>{money(product.price)}</b><i><Plus size={18} /></i></footer></div></button>)}</div></section>
            <aside className="cart-panel"><div className="cart-head"><div><h2>Pesanan baru</h2><p>{cart.reduce((sum, line) => sum + line.qty, 0)} item dipilih</p></div><ShoppingBag /></div><label className="field-label">Nama pelanggan <span>Opsional</span><input value={customer} onChange={(e) => setCustomer(e.target.value)} placeholder="Pelanggan umum" /></label><div className="cart-lines">{cart.length === 0 ? <EmptyState icon="🛍️" title="Keranjang kosong" copy="Ketuk menu untuk menambah pesanan." /> : cart.map((line, index) => <article className="cart-line" key={`${line.id}-${line.spicy}-${index}`}><div className="line-icon">{line.icon}</div><div className="line-copy"><strong>{line.name}</strong>{line.spicy && <span>Pedas: {line.spicy}</span>}<b>{money(line.price * line.qty)}</b></div><div className="qty-control"><button onClick={() => changeQty(index, -1)}><Minus size={15} /></button><span>{line.qty}</span><button onClick={() => changeQty(index, 1)}><Plus size={15} /></button></div></article>)}</div><label className="field-label note-field">Catatan pesanan <span>Opsional</span><textarea value={orderNote} onChange={(e) => setOrderNote(e.target.value)} placeholder="Contoh: bungkus, tanpa acar" /></label><div className="cart-summary"><div><span>Subtotal</span><b>{money(cartTotal)}</b></div><div><span>Biaya lain</span><b>Rp0</b></div><div className="grand-total"><span>Total</span><strong>{money(cartTotal)}</strong></div></div><button className="checkout-btn" disabled={!cart.length} onClick={() => setPaymentOpen(true)}><span>Lanjut pembayaran</span><strong>{money(cartTotal)}</strong><ChevronRight size={19} /></button></aside>
          </div>}

          {view === "kds" && <div className="view-stack"><section className="page-heading"><div><p className="eyebrow">MODE DAPUR</p><h1>Produksi pesanan</h1><p>Tampilan besar untuk dibaca sambil memasak dan menyiapkan minuman.</p></div><div className="kds-legend"><span><i className="dot orange" /> Baru</span><span><i className="dot blue" /> Dimasak</span><span><i className="dot green" /> Siap</span></div></section><section className="kds-board">{(["Diterima", "Sedang Dibuat", "Siap Diambil"] as OrderStatus[]).map((status) => { const columnOrders = orders.filter((order) => order.status === status); return <div className={`kds-column kds-${status.toLowerCase().replaceAll(" ", "-")}`} key={status}><header><div><span>{status === "Diterima" ? "BARU" : status === "Sedang Dibuat" ? "DIMASAK" : "SIAP"}</span><h2>{status}</h2></div><b>{columnOrders.length}</b></header><div className="kds-list">{columnOrders.length === 0 ? <EmptyState icon="✓" title="Kosong" copy="Belum ada tiket." /> : columnOrders.map((order) => <article className="kds-ticket" key={order.id}><div className="ticket-head"><div><strong>{order.id}</strong><SourceBadge source={order.source} /></div><b className={order.elapsed >= 12 ? "late-time" : ""}>{order.elapsed} mnt</b></div><h3>{order.customer}</h3><ul>{order.items.map((item) => <li key={item}>{item}</li>)}</ul>{order.note && <p>⚠ {order.note}</p>}{nextStatus[order.status] && <button onClick={() => advanceOrder(order.id)}>{nextLabel[order.status]} <ChevronRight size={18} /></button>}</article>)}</div></div>; })}</section></div>}

          {view === "menu" && <div className="view-stack"><section className="page-heading"><div><p className="eyebrow">KETERSEDIAAN HARI INI</p><h1>Menu outlet</h1><p>Matikan menu yang habis agar tidak dapat dipesan.</p></div><div className="menu-count"><strong>{Object.values(availability).filter(Boolean).length}</strong><span>dari {products.length} tersedia</span></div></section><section className="menu-management">{products.map((product) => <article className="menu-row" key={product.id}><div className="menu-emoji">{product.icon}</div><div className="menu-copy"><strong>{product.name}</strong><span>{product.category} · {money(product.price)}</span></div><label className="switch"><input type="checkbox" checked={availability[product.id]} onChange={() => setAvailability((current) => ({ ...current, [product.id]: !current[product.id] }))} /><span /></label><b className={availability[product.id] ? "available" : "unavailable"}>{availability[product.id] ? "Tersedia" : "Habis"}</b></article>)}</section></div>}
        </div>
      </section>

      <nav className="bottom-nav" aria-label="Navigasi mobile">{navItems.map(({ id, label, icon: Icon }) => <button key={id} className={view === id ? "active" : ""} onClick={() => setView(id)}><Icon size={21} /><span>{label}</span>{id === "orders" && metrics.waiting > 0 && <b>{metrics.waiting}</b>}</button>)}</nav>

      {incoming && <div className="modal-backdrop priority-backdrop"><section className="incoming-modal" role="dialog" aria-modal="true" aria-label="Pesanan WhatsApp baru"><div className="incoming-head"><div className="pulse-icon"><BellRing /></div><div><p>PESANAN BARU</p><h2>WhatsApp · Siti Rahma</h2></div><button className="close-btn" onClick={() => setIncoming(false)}><X /></button></div><div className="incoming-body"><div className="incoming-meta"><span>#PH-1264 · 12:08</span><strong>{money(38000)}</strong></div><ul><li><b>1×</b> Nasi Goreng Spesial · Pedas</li><li><b>1×</b> Es Teh Manis</li><li><b>1×</b> Kerupuk</li></ul><p className="incoming-note">Bungkus, tanpa acar</p></div><div className="incoming-actions"><button className="reject-btn" onClick={() => setIncoming(false)}>Tolak</button><button className="accept-btn" onClick={acceptIncoming}><Check size={19} /> Terima pesanan</button></div></section></div>}

      {selectedProduct && <div className="modal-backdrop" onMouseDown={() => setSelectedProduct(null)}><section className="option-modal" onMouseDown={(e) => e.stopPropagation()}><div className="modal-title"><div><p>TAMBAH KE PESANAN</p><h2>{selectedProduct.name}</h2></div><button className="close-btn" onClick={() => setSelectedProduct(null)}><X /></button></div><div className="dish-preview"><span>{selectedProduct.icon}</span><div><b>{money(selectedProduct.price)}</b><p>Pilih tingkat kepedasan sebelum menambahkan.</p></div></div><fieldset><legend>Level pedas <span>Wajib</span></legend><div className="option-grid">{["Tidak pedas", "Sedang", "Pedas", "Extra pedas"].map((level) => <button key={level} className={spicy === level ? "selected" : ""} onClick={() => setSpicy(level)}><span>{level}</span>{spicy === level && <Check size={17} />}</button>)}</div></fieldset><button className="full-primary" onClick={() => addToCart(selectedProduct, spicy)}><Plus size={19} /> Tambahkan · {money(selectedProduct.price)}</button></section></div>}

      {paymentOpen && <div className="modal-backdrop" onMouseDown={() => setPaymentOpen(false)}><section className="payment-modal" onMouseDown={(e) => e.stopPropagation()}><div className="modal-title"><div><p>PEMBAYARAN</p><h2>Pilih cara bayar</h2></div><button className="close-btn" onClick={() => setPaymentOpen(false)}><X /></button></div><div className="payment-layout"><div><div className="payment-methods"><button className={paymentMethod === "Tunai" ? "selected" : ""} onClick={() => setPaymentMethod("Tunai")}><WalletCards /><div><strong>Tunai</strong><span>Hitung kembalian langsung</span></div>{paymentMethod === "Tunai" && <CheckCircle2 />}</button><button className={paymentMethod === "QRIS" ? "selected" : ""} onClick={() => setPaymentMethod("QRIS")}><Smartphone /><div><strong>QRIS Midtrans</strong><span>Tampilkan kode pembayaran</span></div>{paymentMethod === "QRIS" && <CheckCircle2 />}</button></div>{paymentMethod === "Tunai" ? <div className="cash-panel"><p>Uang diterima</p><div className="cash-presets">{[50000, 100000, cartTotal].map((amount) => <button key={amount} className={cash === amount ? "active" : ""} onClick={() => setCash(amount)}>{amount === cartTotal ? "Uang pas" : money(amount)}</button>)}</div><label>Nominal<input type="number" value={cash} onChange={(e) => setCash(Number(e.target.value))} /></label><div className="change-row"><span>Kembalian</span><strong>{money(Math.max(0, cash - cartTotal))}</strong></div></div> : <div className="qris-panel"><div className="qr-placeholder"><span>PH</span></div><div><strong>QRIS siap dibuat</strong><p>Pada aplikasi asli, QR dinamis dibuat oleh Midtrans setelah konfirmasi.</p></div></div>}</div><aside className="payment-summary"><ReceiptText /><span>Total pembayaran</span><strong>{money(cartTotal)}</strong><p>{cart.reduce((sum, line) => sum + line.qty, 0)} item · {customer || "Pelanggan umum"}</p></aside></div><button className="full-primary" onClick={completePayment} disabled={paymentMethod === "Tunai" && cash < cartTotal}><Check size={19} /> {paymentMethod === "Tunai" ? "Konfirmasi pembayaran" : "Buat QRIS"}</button></section></div>}

      {detail && <div className="modal-backdrop" onMouseDown={() => setDetail(null)}><section className="detail-drawer" onMouseDown={(e) => e.stopPropagation()}><div className="modal-title"><div><p>DETAIL PESANAN</p><h2>{detail.id}</h2></div><button className="close-btn" onClick={() => setDetail(null)}><X /></button></div><div className="detail-customer"><div className="customer-avatar large">{detail.customer.charAt(0)}</div><div><h3>{detail.customer}</h3><p>{detail.time} · <SourceBadge source={detail.source} /></p></div><StatusPill status={detail.status} /></div><div className="status-track">{["Diterima", "Sedang Dibuat", "Siap Diambil", "Selesai"].map((status, index) => { const current = ["Menunggu", "Diterima", "Sedang Dibuat", "Siap Diambil", "Selesai"].indexOf(detail.status); const point = index + 1; return <div key={status} className={current >= point ? "done" : ""}><i>{current > point ? <Check size={14} /> : point}</i><span>{status}</span></div>; })}</div><section className="detail-section"><h3>Isi pesanan</h3>{detail.items.map((item) => <div className="detail-line" key={item}><span>{item}</span></div>)}{detail.note && <p className="detail-note">Catatan: {detail.note}</p>}</section><section className="detail-section"><div className="detail-total"><span>Total</span><strong>{money(detail.total)}</strong></div><div className="payment-chip"><CircleDollarSign size={17} /><span>{detail.paid ? "Sudah dibayar" : "Belum dibayar"}</span></div></section>{nextStatus[detail.status] && <button className="full-primary sticky-action" onClick={() => advanceOrder(detail.id)}>{nextLabel[detail.status]} <ChevronRight size={18} /></button>}</section></div>}

      {toast && <div className="toast"><CheckCircle2 size={19} /> {toast}</div>}
    </main>
  );
}
