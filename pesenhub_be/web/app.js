(() => {
  'use strict';

  let catalogData = [];
  let currentCategory = null;
  let cart = {}; // menuId -> { quantity, notes, selections: { [groupId]: [optionId] } }
  let activeTrackingToken = null;
  let trackingPollTimer = null;
  let isSubmitting = false;

  const formatIDR = (amount) => {
    return 'Rp ' + Number(amount || 0).toLocaleString('id-ID');
  };

  const getUUID = () => {
    if (crypto.randomUUID) return crypto.randomUUID();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = Math.random() * 16 | 0, v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  };

  const elements = {
    viewOrder: document.getElementById('view-order'),
    viewTracking: document.getElementById('view-tracking'),
    inputName: document.getElementById('input-customer-name'),
    inputPhone: document.getElementById('input-customer-phone'),
    inputNotes: document.getElementById('input-order-notes'),
    errName: document.getElementById('err-customer-name'),
    errPhone: document.getElementById('err-customer-phone'),
    errItems: document.getElementById('err-items'),
    globalAlert: document.getElementById('global-alert'),
    categoryTabs: document.getElementById('category-tabs'),
    menuList: document.getElementById('menu-list'),
    cartSummaryItems: document.getElementById('cart-summary-items'),
    totalDisplay: document.getElementById('total-amount-display'),
    btnSubmit: document.getElementById('btn-submit-order'),
    btnNewOrder: document.getElementById('btn-new-order'),
    trackingBadge: document.getElementById('tracking-status-badge'),
    trackingOrderNum: document.getElementById('tracking-order-number'),
    trackingCustomerName: document.getElementById('tracking-customer-name'),
    trackingItemsList: document.getElementById('tracking-items-list'),
    trackingTotal: document.getElementById('tracking-total-amount'),
  };

  const showAlert = (msg) => {
    elements.globalAlert.textContent = msg;
    elements.globalAlert.classList.remove('hidden');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const hideAlert = () => {
    elements.globalAlert.textContent = '';
    elements.globalAlert.classList.add('hidden');
  };

  const init = async () => {
    // Check url params for tracking token
    const params = new URLSearchParams(window.location.search);
    const token = params.get('token') || localStorage.getItem('pesenhub_tracking_token');

    if (token) {
      loadTracking(token);
    }

    try {
      const res = await fetch('/api/v1/public/menu');
      if (!res.ok) throw new Error('Gagal memuat katalog');
      const data = await res.json();
      catalogData = data.categories || [];
      renderCategories();
      renderMenu();
    } catch (e) {
      showAlert('Gagal menghubungi server untuk memuat menu. Silakan muat ulang halaman.');
    }

    attachEvents();
  };

  const renderCategories = () => {
    elements.categoryTabs.innerHTML = '';
    if (!catalogData.length) return;

    // "Semua" tab
    const allBtn = document.createElement('button');
    allBtn.type = 'button';
    allBtn.className = 'tab-btn' + (currentCategory === null ? ' active' : '');
    allBtn.textContent = 'Semua Menu';
    allBtn.addEventListener('click', () => {
      currentCategory = null;
      renderCategories();
      renderMenu();
    });
    elements.categoryTabs.appendChild(allBtn);

    catalogData.forEach((cat) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'tab-btn' + (currentCategory === cat.id ? ' active' : '');
      btn.textContent = cat.name;
      btn.addEventListener('click', () => {
        currentCategory = cat.id;
        renderCategories();
        renderMenu();
      });
      elements.categoryTabs.appendChild(btn);
    });
  };

  const renderMenu = () => {
    elements.menuList.innerHTML = '';
    let displayedCategories = catalogData;
    if (currentCategory) {
      displayedCategories = catalogData.filter((c) => c.id === currentCategory);
    }

    if (!displayedCategories.length) {
      elements.menuList.innerHTML = '<p style="text-align:center;color:var(--text-muted);padding:1rem">Belum ada menu di kategori ini.</p>';
      return;
    }

    displayedCategories.forEach((cat) => {
      (cat.items || []).forEach((item) => {
        const itemEl = document.createElement('div');
        itemEl.className = 'menu-item' + (!item.is_available ? ' unavailable' : '');

        const itemInfo = document.createElement('div');
        itemInfo.className = 'menu-item-info';

        const title = document.createElement('div');
        title.className = 'menu-item-title';
        title.textContent = item.name;

        const price = document.createElement('div');
        price.className = 'menu-item-price';
        price.textContent = formatIDR(item.price_amount) + (!item.is_available ? ' (Habis)' : '');

        itemInfo.appendChild(title);
        itemInfo.appendChild(price);

        // Render modifier groups if available
        if (item.modifier_groups && item.modifier_groups.length > 0 && item.is_available) {
          const modBox = document.createElement('div');
          modBox.className = 'modifiers-box';

          item.modifier_groups.forEach((g) => {
            const gTitle = document.createElement('div');
            gTitle.style.fontWeight = '600';
            gTitle.textContent = g.name + (g.min_select > 0 ? ' (Wajib)' : ' (Opsional)');
            modBox.appendChild(gTitle);

            (g.options || []).forEach((opt) => {
              const optLabel = document.createElement('label');
              optLabel.className = 'modifier-option-label';

              const radio = document.createElement('input');
              radio.type = g.max_select === 1 ? 'radio' : 'checkbox';
              radio.name = `mod-${item.id}-${g.id}`;
              radio.value = opt.id;
              radio.disabled = !opt.is_available;

              // Check if selected in cart
              if (cart[item.id] && cart[item.id].selections && cart[item.id].selections[g.id]) {
                if (cart[item.id].selections[g.id].includes(opt.id)) {
                  radio.checked = true;
                }
              }

              radio.addEventListener('change', () => {
                if (!cart[item.id]) {
                  cart[item.id] = { quantity: 1, notes: '', selections: {} };
                }
                if (!cart[item.id].selections[g.id]) {
                  cart[item.id].selections[g.id] = [];
                }
                if (g.max_select === 1) {
                  cart[item.id].selections[g.id] = [opt.id];
                } else {
                  if (radio.checked) {
                    cart[item.id].selections[g.id].push(opt.id);
                  } else {
                    cart[item.id].selections[g.id] = cart[item.id].selections[g.id].filter(id => id !== opt.id);
                  }
                }
                updateCartPreview();
              });

              optLabel.appendChild(radio);
              const optSpan = document.createElement('span');
              optSpan.textContent = opt.name + (opt.price_delta_amount > 0 ? ` (+${formatIDR(opt.price_delta_amount)})` : '') + (!opt.is_available ? ' [Habis]' : '');
              optLabel.appendChild(optSpan);
              modBox.appendChild(optLabel);
            });
          });

          itemInfo.appendChild(modBox);
        }

        const ctrl = document.createElement('div');
        ctrl.className = 'menu-item-ctrl';

        const qty = (cart[item.id] && cart[item.id].quantity) || 0;

        if (item.is_available) {
          const minusBtn = document.createElement('button');
          minusBtn.type = 'button';
          minusBtn.className = 'qty-btn';
          minusBtn.textContent = '−';
          minusBtn.setAttribute('aria-label', `Kurangi ${item.name}`);
          minusBtn.addEventListener('click', () => {
            changeQty(item.id, -1);
          });

          const qtyVal = document.createElement('span');
          qtyVal.className = 'qty-val';
          qtyVal.textContent = qty;

          const plusBtn = document.createElement('button');
          plusBtn.type = 'button';
          plusBtn.className = 'qty-btn';
          plusBtn.textContent = '+';
          plusBtn.setAttribute('aria-label', `Tambah ${item.name}`);
          plusBtn.addEventListener('click', () => {
            changeQty(item.id, 1);
          });

          ctrl.appendChild(minusBtn);
          ctrl.appendChild(qtyVal);
          ctrl.appendChild(plusBtn);
        }

        itemEl.appendChild(itemInfo);
        itemEl.appendChild(ctrl);
        elements.menuList.appendChild(itemEl);
      });
    });
  };

  const changeQty = (menuId, delta) => {
    if (!cart[menuId]) {
      cart[menuId] = { quantity: 0, notes: '', selections: {} };
    }
    cart[menuId].quantity = Math.max(0, cart[menuId].quantity + delta);
    if (cart[menuId].quantity === 0) {
      delete cart[menuId];
    }
    renderMenu();
    updateCartPreview();
  };

  const buildItemsPayload = () => {
    const items = [];
    for (const [menuId, data] of Object.entries(cart)) {
      if (data.quantity > 0) {
        const groups = [];
        for (const [groupId, optIds] of Object.entries(data.selections || {})) {
          if (optIds && optIds.length > 0) {
            groups.push({ group_id: groupId, option_ids: optIds });
          }
        }
        items.push({
          menu_id: menuId,
          quantity: data.quantity,
          notes: data.notes || '',
          modifier_groups: groups
        });
      }
    }
    return items;
  };

  const updateCartPreview = async () => {
    const items = buildItemsPayload();
    if (!items.length) {
      elements.cartSummaryItems.innerHTML = '<p style="color:var(--text-muted);font-size:0.9rem">Belum ada menu yang dipilih.</p>';
      elements.totalDisplay.textContent = formatIDR(0);
      elements.btnSubmit.disabled = true;
      elements.errItems.classList.remove('visible');
      return;
    }

    elements.errItems.classList.remove('visible');
    try {
      const res = await fetch('/api/v1/public/orders/preview', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ items }),
      });

      if (!res.ok) {
        const errData = await res.json();
        throw new Error(errData.message || 'Pilihan menu atau opsi tidak valid');
      }

      const { data } = await res.json();
      elements.totalDisplay.textContent = formatIDR(data.total_amount);

      elements.cartSummaryItems.innerHTML = '';
      (data.items || []).forEach((it) => {
        const row = document.createElement('div');
        row.className = 'summary-row';
        const modText = it.modifiers && it.modifiers.length > 0 ? ` (${it.modifiers.map(m => m.name).join(', ')})` : '';
        row.innerHTML = `<span>${it.name}${modText} x ${it.quantity}</span><span>${formatIDR(it.line_total_amount)}</span>`;
        elements.cartSummaryItems.appendChild(row);
      });

      validateInputs();
    } catch (e) {
      elements.totalDisplay.textContent = 'Error kalkulasi';
      elements.btnSubmit.disabled = true;
    }
  };

  const validateInputs = () => {
    let isValid = true;
    const name = elements.inputName.value.trim();
    const phone = elements.inputPhone.value.trim();
    const items = buildItemsPayload();

    if (!name) {
      elements.errName.classList.remove('visible');
      isValid = false;
    } else {
      elements.errName.classList.remove('visible');
      elements.inputName.classList.remove('is-invalid');
    }

    if (!phone || !(phone.startsWith('08') || phone.startsWith('+628') || phone.startsWith('628')) || phone.length < 10) {
      isValid = false;
    } else {
      elements.errPhone.classList.remove('visible');
      elements.inputPhone.classList.remove('is-invalid');
    }

    if (!items.length) {
      isValid = false;
    }

    elements.btnSubmit.disabled = !isValid || isSubmitting;
    return isValid;
  };

  const submitOrder = async () => {
    hideAlert();
    const name = elements.inputName.value.trim();
    const phone = elements.inputPhone.value.trim();
    const notes = elements.inputNotes.value.trim();
    const items = buildItemsPayload();

    let hasClientError = false;
    if (!name) {
      elements.errName.classList.add('visible');
      elements.inputName.classList.add('is-invalid');
      hasClientError = true;
    }
    if (!phone || !(phone.startsWith('08') || phone.startsWith('+628') || phone.startsWith('628')) || phone.length < 10) {
      elements.errPhone.classList.add('visible');
      elements.inputPhone.classList.add('is-invalid');
      hasClientError = true;
    }
    if (!items.length) {
      elements.errItems.classList.add('visible');
      hasClientError = true;
    }

    if (hasClientError) return;

    // Double submit guard
    isSubmitting = true;
    elements.btnSubmit.disabled = true;
    elements.btnSubmit.innerHTML = '<span>Mengirim Pesanan...</span>';

    // Idempotency key
    let idempotencyKey = sessionStorage.getItem('pesenhub_active_idempotency_key');
    if (!idempotencyKey) {
      idempotencyKey = 'web-' + getUUID();
      sessionStorage.setItem('pesenhub_active_idempotency_key', idempotencyKey);
    }

    try {
      const res = await fetch('/api/v1/public/orders', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': idempotencyKey,
        },
        body: JSON.stringify({
          customer_name: name,
          customer_phone: phone,
          notes: notes,
          items: items,
        }),
      });

      const json = await res.json();
      if (!res.ok) {
        if (json.details && json.details.length > 0) {
          json.details.forEach((d) => {
            if (d.field === 'customer_name') {
              elements.errName.textContent = d.reason || 'Nama pemesan tidak valid';
              elements.errName.classList.add('visible');
              elements.inputName.classList.add('is-invalid');
            }
            if (d.field === 'customer_phone') {
              elements.errPhone.textContent = d.reason || 'Nomor WhatsApp tidak valid';
              elements.errPhone.classList.add('visible');
              elements.inputPhone.classList.add('is-invalid');
            }
          });
        }
        throw new Error(json.message || 'Gagal mengirim pesanan');
      }

      sessionStorage.removeItem('pesenhub_active_idempotency_key');
      const order = json.data;
      localStorage.setItem('pesenhub_tracking_token', order.public_tracking_token);

      // Update URL without reload
      const url = new URL(window.location);
      url.searchParams.set('token', order.public_tracking_token);
      window.history.pushState({}, '', url);

      loadTracking(order.public_tracking_token);
    } catch (e) {
      showAlert(e.message || 'Terjadi kesalahan saat memproses pesanan.');
    } finally {
      isSubmitting = false;
      elements.btnSubmit.disabled = false;
      elements.btnSubmit.innerHTML = '<span>Kirim Pesanan</span>';
      validateInputs();
    }
  };

  const statusMap = {
    PENDING: { label: 'Menunggu Konfirmasi', cls: 'badge-pending' },
    ACCEPTED: { label: 'Diterima Kasir', cls: 'badge-accepted' },
    PREPARING: { label: 'Sedang Dimasak', cls: 'badge-preparing' },
    READY_FOR_PICKUP: { label: 'Siap Diambil', cls: 'badge-ready' },
    COMPLETED: { label: 'Pesanan Selesai', cls: 'badge-completed' },
    REJECTED: { label: 'Ditolak', cls: 'badge-completed' },
    CANCELLED: { label: 'Dibatalkan', cls: 'badge-completed' },
  };

  const loadTracking = async (token) => {
    activeTrackingToken = token;
    elements.viewOrder.classList.add('hidden');
    elements.viewTracking.classList.remove('hidden');

    const fetchStatus = async () => {
      try {
        const res = await fetch(`/api/v1/public/orders/${activeTrackingToken}`);
        if (res.status === 404) {
          showAlert('Pesanan tidak ditemukan atau tautan tidak valid.');
          resetToOrderView();
          return;
        }
        const { data } = await res.json();
        elements.trackingOrderNum.textContent = data.order_number;
        elements.trackingCustomerName.textContent = data.customer_name;
        elements.trackingTotal.textContent = formatIDR(data.total_amount);

        const st = statusMap[data.status] || { label: data.status, cls: 'badge-pending' };
        elements.trackingBadge.textContent = st.label;
        elements.trackingBadge.className = 'badge ' + st.cls;

        elements.trackingItemsList.innerHTML = '';
        (data.items || []).forEach((it) => {
          const row = document.createElement('div');
          row.className = 'summary-row';
          const modText = it.modifiers && it.modifiers.length > 0 ? ` (${it.modifiers.map(m => m.name).join(', ')})` : '';
          row.innerHTML = `<span>${it.name}${modText} x ${it.quantity}</span><span>${formatIDR(it.line_total_amount)}</span>`;
          elements.trackingItemsList.appendChild(row);
        });
      } catch (e) {
        // Silently retry on next poll
      }
    };

    fetchStatus();
    if (trackingPollTimer) clearInterval(trackingPollTimer);
    trackingPollTimer = setInterval(fetchStatus, 5000);
  };

  const resetToOrderView = () => {
    if (trackingPollTimer) clearInterval(trackingPollTimer);
    activeTrackingToken = null;
    localStorage.removeItem('pesenhub_tracking_token');
    const url = new URL(window.location);
    url.searchParams.delete('token');
    window.history.pushState({}, '', url);

    cart = {};
    elements.inputName.value = '';
    elements.inputPhone.value = '';
    elements.inputNotes.value = '';
    elements.viewTracking.classList.add('hidden');
    elements.viewOrder.classList.remove('hidden');
    renderMenu();
    updateCartPreview();
  };

  const attachEvents = () => {
    elements.inputName.addEventListener('input', validateInputs);
    elements.inputPhone.addEventListener('input', validateInputs);
    elements.btnSubmit.addEventListener('click', submitOrder);
    elements.btnNewOrder.addEventListener('click', resetToOrderView);
  };

  document.addEventListener('DOMContentLoaded', init);
})();
