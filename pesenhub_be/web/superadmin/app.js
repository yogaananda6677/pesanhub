(function () {
  'use strict';

  // Configuration & State
  const STORAGE_KEY = 'pesenhub_superadmin_token';
  const THEME_KEY = 'pesenhub_theme';
  let authToken = sessionStorage.getItem(STORAGE_KEY) || '';
  let currentUser = null;
  let autoRefreshTimer = null;
  let currentTab = 'health';
  let userStatusFilter = 'ALL';
  let userSearchQuery = '';
  let pendingAction = null; // { type, id, name, target }
  let currentInspectingWAUserId = null;
  let currentInspectingWAUserName = '';

  // Theme Elements
  const btnThemeToggle = document.getElementById('btn-theme-toggle');
  const themeToggleIcon = document.getElementById('theme-toggle-icon');
  const themeToggleText = document.getElementById('theme-toggle-text');

  // DOM Elements - Auth & Navigation
  const authSection = document.getElementById('auth-section');
  const portalSection = document.getElementById('portal-section');
  const formLogin = document.getElementById('form-login');
  const inputUsername = document.getElementById('input-username');
  const inputPassword = document.getElementById('input-password');
  const btnSubmitLogin = document.getElementById('btn-submit-login');
  const authError = document.getElementById('auth-error');
  const userProfile = document.getElementById('user-profile');
  const userEmail = document.getElementById('user-email');
  const btnLogout = document.getElementById('btn-logout');

  const tabBtns = document.querySelectorAll('.tab-btn');
  const tabPanels = document.querySelectorAll('.tab-panel');
  const pendingBadge = document.getElementById('pending-badge');

  // Telemetry Elements
  const systemQuickStatus = document.getElementById('system-quick-status');
  const quickStatusText = document.getElementById('quick-status-text');
  const healthCardsContainer = document.getElementById('health-cards-container');
  const selectRange = document.getElementById('select-range');
  const toggleAutoRefresh = document.getElementById('toggle-autorefresh');
  const btnRefreshHealth = document.getElementById('btn-refresh-health');
  const healthStaleBanner = document.getElementById('health-stale-banner');
  const staleTime = document.getElementById('stale-time');

  // Metrics Elements
  const metricRate = document.getElementById('metric-rate');
  const metricSuccessRate = document.getElementById('metric-success-rate');
  const metricLatency = document.getElementById('metric-latency');
  const metricTotalRequests = document.getElementById('metric-total-requests');
  const metricWACount = document.getElementById('metric-wa-count');
  const metricQueueActive = document.getElementById('metric-queue-active');
  const metricQueueDetail = document.getElementById('metric-queue-detail');

  // Users Elements
  const usersTableBody = document.getElementById('users-table-body');
  const inputUserSearch = document.getElementById('input-user-search');
  const btnRefreshUsers = document.getElementById('btn-refresh-users');
  const btnOpenInvite = document.getElementById('btn-open-invite');
  const pillBtns = document.querySelectorAll('.pill-btn');

  // Audits Elements
  const auditsTableBody = document.getElementById('audits-table-body');
  const btnRefreshAudits = document.getElementById('btn-refresh-audits');

  // Dialog Elements - WhatsApp Gateway Info
  const dialogWaInfo = document.getElementById('dialog-wa-info');
  const btnCloseWa = document.getElementById('btn-close-wa');
  const btnCloseWaFooter = document.getElementById('btn-close-wa-footer');
  const btnRefreshWaSingle = document.getElementById('btn-refresh-wa-single');
  const waInfoLoading = document.getElementById('wa-info-loading');
  const waInfoContent = document.getElementById('wa-info-content');
  const waInfoError = document.getElementById('wa-info-error');
  const waStatusBanner = document.getElementById('wa-status-banner');
  const waModalDot = document.getElementById('wa-modal-dot');
  const waModalStatusText = document.getElementById('wa-modal-status-text');
  const waInfoUser = document.getElementById('wa-info-user');
  const waInfoPhone = document.getElementById('wa-info-phone');
  const waInfoDevice = document.getElementById('wa-info-device');
  const waInfoMessage = document.getElementById('wa-info-message');

  // Dialog Elements - Invite Cashier
  const dialogInvite = document.getElementById('dialog-invite');
  const formInvite = document.getElementById('form-invite');
  const inviteEmail = document.getElementById('invite-email');
  const inviteOutlet = document.getElementById('invite-outlet');
  const inviteError = document.getElementById('invite-error');
  const btnCloseInvite = document.getElementById('btn-close-invite');
  const btnCancelInvite = document.getElementById('btn-cancel-invite');

  // Dialog Elements - Action Confirmation
  const dialogAction = document.getElementById('dialog-action');
  const formAction = document.getElementById('form-action');
  const actionTargetDesc = document.getElementById('action-target-desc');
  const actionDetailText = document.getElementById('action-detail-text');
  const actionReason = document.getElementById('action-reason');
  const actionError = document.getElementById('action-error');
  const btnConfirmAction = document.getElementById('btn-confirm-action');
  const btnCloseAction = document.getElementById('btn-close-action');
  const btnCancelAction = document.getElementById('btn-cancel-action');

  const toastContainer = document.getElementById('toast-container');

  // ==========================================
  // THEME MANAGEMENT (Light / Dark Mode)
  // ==========================================
  function getCurrentTheme() {
    return document.documentElement.getAttribute('data-theme') || 'dark';
  }

  function updateThemeUI(theme) {
    if (theme === 'light') {
      if (themeToggleIcon) themeToggleIcon.textContent = '☀️';
      if (themeToggleText) themeToggleText.textContent = 'Mode Terang';
      if (btnThemeToggle) btnThemeToggle.setAttribute('title', 'Beralih ke Mode Gelap');
    } else {
      if (themeToggleIcon) themeToggleIcon.textContent = '🌙';
      if (themeToggleText) themeToggleText.textContent = 'Mode Gelap';
      if (btnThemeToggle) btnThemeToggle.setAttribute('title', 'Beralih ke Mode Terang');
    }
  }

  function initTheme() {
    const current = getCurrentTheme();
    updateThemeUI(current);

    if (btnThemeToggle) {
      btnThemeToggle.addEventListener('click', () => {
        const next = getCurrentTheme() === 'dark' ? 'light' : 'dark';
        document.documentElement.setAttribute('data-theme', next);
        try {
          localStorage.setItem(THEME_KEY, next);
        } catch (_) {}
        updateThemeUI(next);
        showToast(`Tema diubah ke ${next === 'light' ? 'Mode Terang' : 'Mode Gelap'}.`, 'info');
      });
    }
  }

  // Toast Notification
  function showToast(message, type = 'info') {
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    toastContainer.appendChild(toast);
    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transition = 'opacity 0.3s ease';
      setTimeout(() => toast.remove(), 300);
    }, 4000);
  }

  // API Client Helper
  async function apiFetch(url, options = {}) {
    options.headers = options.headers || {};
    if (authToken) {
      options.headers['Authorization'] = `Bearer ${authToken}`;
    }
    if (options.body && typeof options.body === 'object' && !(options.body instanceof FormData)) {
      options.headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(options.body);
    }

    try {
      const response = await fetch(url, options);
      if (response.status === 401 || response.status === 403) {
        if (url.includes('/superadmin/')) {
          console.warn('Session expired or forbidden:', response.status);
          handleAuthFailure('Sesi kedaluwarsa atau otorisasi Superadmin tidak valid.');
          throw new Error('Unauthorized');
        }
      }
      return response;
    } catch (err) {
      throw err;
    }
  }

  // Authentication Flow
  async function initAuth() {
    if (!authToken) {
      showAuthSection();
      return;
    }

    try {
      const res = await apiFetch('/api/v1/auth/me');
      if (!res.ok) {
        handleAuthFailure('Sesi kedaluwarsa. Silakan login kembali.');
        return;
      }
      const data = await res.json();
      if (data.role !== 'SUPERADMIN') {
        handleAuthFailure(`Akses ditolak: Akun ini memiliki role ${data.role}. Hanya SUPERADMIN yang diizinkan.`);
        return;
      }

      currentUser = data;
      showPortalSection();
      loadActiveTab();
    } catch (err) {
      handleAuthFailure('Gagal memverifikasi sesi: ' + (err.message || 'Koneksi error'));
    }
  }

  function handleAuthFailure(message) {
    authToken = '';
    currentUser = null;
    sessionStorage.removeItem(STORAGE_KEY);
    showAuthSection();
    authError.textContent = message;
    authError.classList.remove('hidden');
    stopAutoRefresh();
  }

  function showAuthSection() {
    authSection.classList.remove('hidden');
    portalSection.classList.add('hidden');
    userProfile.classList.add('hidden');
    if (inputPassword) inputPassword.value = '';
  }

  function showPortalSection() {
    authSection.classList.add('hidden');
    portalSection.classList.remove('hidden');
    userProfile.classList.remove('hidden');
    userEmail.textContent = currentUser ? (currentUser.email || 'superadmin') : 'superadmin';
    authError.classList.add('hidden');
    setupAutoRefresh();
  }

  formLogin.addEventListener('submit', async (e) => {
    e.preventDefault();
    const username = inputUsername ? inputUsername.value.trim() : '';
    const password = inputPassword ? inputPassword.value : '';
    if (!username || !password) return;

    authError.classList.add('hidden');
    if (btnSubmitLogin) {
      btnSubmitLogin.disabled = true;
      btnSubmitLogin.textContent = 'Memverifikasi...';
    }

    try {
      const res = await fetch('/api/v1/superadmin/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
      });

      if (!res.ok) {
        let errMsg = 'Username atau password salah.';
        try {
          const errData = await res.json();
          if (errData.error && errData.error.message) {
            errMsg = errData.error.message;
          }
        } catch (_) {}
        handleAuthFailure(errMsg);
        return;
      }

      const data = await res.json();
      authToken = data.access_token;
      sessionStorage.setItem(STORAGE_KEY, authToken);
      currentUser = data.user || { role: 'SUPERADMIN', email: username };

      showPortalSection();
      loadActiveTab();
    } catch (err) {
      handleAuthFailure('Gagal terhubung ke server: ' + (err.message || 'Koneksi error'));
    } finally {
      if (btnSubmitLogin) {
        btnSubmitLogin.disabled = false;
        btnSubmitLogin.textContent = 'Masuk ke Portal';
      }
    }
  });

  btnLogout.addEventListener('click', async () => {
    try {
      await apiFetch('/api/v1/auth/logout', { method: 'POST' });
    } catch (_) {}
    handleAuthFailure('Anda telah keluar.');
  });

  // Tab Navigation
  tabBtns.forEach((btn) => {
    btn.addEventListener('click', () => {
      const tab = btn.getAttribute('data-tab');
      switchTab(tab);
    });
  });

  function switchTab(tab) {
    currentTab = tab;
    tabBtns.forEach((btn) => {
      const isActive = btn.getAttribute('data-tab') === tab;
      btn.classList.toggle('active', isActive);
      btn.setAttribute('aria-selected', isActive ? 'true' : 'false');
    });

    tabPanels.forEach((panel) => {
      panel.classList.toggle('hidden', panel.id !== `panel-${tab}`);
    });

    loadActiveTab();
  }

  function loadActiveTab() {
    if (!authToken) return;
    if (currentTab === 'health') {
      fetchHealthSnapshot();
      fetchTrafficTelemetry();
    } else if (currentTab === 'users') {
      fetchUsers();
    } else if (currentTab === 'audits') {
      fetchAudits();
    }
  }

  // Auto-refresh logic
  function setupAutoRefresh() {
    stopAutoRefresh();
    if (toggleAutoRefresh && toggleAutoRefresh.checked) {
      autoRefreshTimer = setInterval(() => {
        if (currentTab === 'health') {
          fetchHealthSnapshot(true);
          fetchTrafficTelemetry(true);
        } else if (currentTab === 'users') {
          fetchUsers(true);
        }
      }, 30000);
    }
  }

  function stopAutoRefresh() {
    if (autoRefreshTimer) {
      clearInterval(autoRefreshTimer);
      autoRefreshTimer = null;
    }
  }

  if (toggleAutoRefresh) {
    toggleAutoRefresh.addEventListener('change', () => {
      if (toggleAutoRefresh.checked) {
        setupAutoRefresh();
        showToast('Auto-refresh diaktifkan (setiap 30 detik).', 'info');
      } else {
        stopAutoRefresh();
        showToast('Auto-refresh dijeda.', 'info');
      }
    });
  }

  // ==========================================
  // TAB 1: System Health & Telemetry
  // ==========================================
  async function fetchHealthSnapshot(isBackground = false) {
    try {
      const res = await apiFetch('/api/v1/superadmin/health/snapshot');
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      renderHealthSnapshot(data);
      healthStaleBanner.classList.add('hidden');
    } catch (err) {
      if (!isBackground) {
        showToast('Gagal memuat status sistem: ' + err.message, 'error');
      }
      healthStaleBanner.classList.remove('hidden');
      staleTime.textContent = new Date().toLocaleTimeString();
    }
  }

  function renderHealthSnapshot(data) {
    const overall = data.overall_status || 'unknown';
    systemQuickStatus.className = `status-pill status-${overall}`;
    quickStatusText.textContent = overall === 'healthy' ? 'Sistem Normal' : overall === 'degraded' ? 'Performa Terdegradasi' : 'Sistem Bermasalah';

    healthCardsContainer.innerHTML = '';
    if (!data.components || data.components.length === 0) {
      healthCardsContainer.innerHTML = '<div class="card">Tidak ada data komponen.</div>';
      return;
    }

    data.components.forEach((comp) => {
      const card = document.createElement('div');
      card.className = 'health-card';

      const titleMap = {
        api: 'API Gateway',
        database: 'MySQL Database',
        gowa: 'WhatsApp Gateway (GOWA)',
        outbox_worker: 'Notifikasi Outbox Worker',
        realtime_ws: 'Real-Time WebSocket',
        mobile_sync: 'Mobile Offline Sync'
      };

      let detailsHtml = '';
      if (comp.details && Object.keys(comp.details).length > 0) {
        const detailItems = Object.entries(comp.details)
          .map(([k, v]) => `<div><strong>${k}:</strong> ${escapeHtml(String(v))}</div>`)
          .join('');
        detailsHtml = `<div class="component-details">${detailItems}</div>`;
      }

      card.innerHTML = `
        <div class="health-card-top">
          <span class="component-title">${titleMap[comp.component] || escapeHtml(comp.component)}</span>
          <span class="status-pill status-${comp.status}">
            <span class="status-dot"></span> ${escapeHtml(comp.status.toUpperCase())}
          </span>
        </div>
        <p class="component-message">${escapeHtml(comp.message || '-')}</p>
        ${detailsHtml}
        <div class="help-text" style="margin-top: 0.75rem;">
          Pembaruan: ${new Date(comp.freshness).toLocaleTimeString()}
        </div>
      `;
      healthCardsContainer.appendChild(card);
    });
  }

  async function fetchTrafficTelemetry(isBackground = false) {
    const range = selectRange ? selectRange.value : '24h';
    try {
      const res = await apiFetch(`/api/v1/superadmin/telemetry/traffic?range=${range}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      renderTrafficTelemetry(data);
    } catch (err) {
      if (!isBackground) {
        showToast('Gagal memuat metrik telemetri: ' + err.message, 'error');
      }
    }
  }

  function renderTrafficTelemetry(m) {
    metricRate.textContent = (m.request_rate_per_min || 0).toFixed(1) + ' /mnt';
    metricSuccessRate.textContent = (m.success_rate || 100).toFixed(1) + '%';
    metricLatency.textContent = `${m.latency_p50_ms || 0} / ${m.latency_p95_ms || 0} ms`;
    metricTotalRequests.textContent = Number(m.total_requests || 0).toLocaleString();
    metricWACount.textContent = `${m.wa_inbound_count || 0} / ${m.wa_outbound_count || 0}`;

    const activeTotal = (m.queue_pending || 0) + (m.queue_preparing || 0) + (m.queue_ready || 0);
    metricQueueActive.textContent = activeTotal;
    metricQueueDetail.textContent = `Pending: ${m.queue_pending || 0} | Masak: ${m.queue_preparing || 0} | Siap: ${m.queue_ready || 0}`;
  }

  if (selectRange) {
    selectRange.addEventListener('change', () => fetchTrafficTelemetry());
  }
  if (btnRefreshHealth) {
    btnRefreshHealth.addEventListener('click', () => {
      fetchHealthSnapshot();
      fetchTrafficTelemetry();
      showToast('Data telemetri disegarkan.', 'info');
    });
  }

  // ==========================================
  // TAB 2: Users Management & WA Status
  // ==========================================
  pillBtns.forEach((btn) => {
    btn.addEventListener('click', () => {
      pillBtns.forEach((b) => {
        b.classList.remove('active');
        b.setAttribute('aria-checked', 'false');
      });
      btn.classList.add('active');
      btn.setAttribute('aria-checked', 'true');
      userStatusFilter = btn.getAttribute('data-status');
      fetchUsers();
    });
  });

  let searchTimeout = null;
  inputUserSearch.addEventListener('input', () => {
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(() => {
      userSearchQuery = inputUserSearch.value.trim();
      fetchUsers();
    }, 300);
  });

  if (btnRefreshUsers) {
    btnRefreshUsers.addEventListener('click', () => {
      fetchUsers();
      showToast('Daftar pengguna disegarkan.', 'info');
    });
  }

  async function fetchUsers(isBackground = false) {
    if (userStatusFilter === 'INVITED') {
      await fetchInvitations(isBackground);
      return;
    }

    try {
      const usersUrl = `/api/v1/superadmin/users?status=${userStatusFilter}&q=${encodeURIComponent(userSearchQuery)}`;
      
      // Parallel fetch users list and WA gateway overview status
      const [usersRes, waRes] = await Promise.all([
        apiFetch(usersUrl),
        apiFetch('/api/v1/superadmin/whatsapp/status').catch(() => null)
      ]);

      if (!usersRes.ok) throw new Error(`HTTP ${usersRes.status}`);
      const body = await usersRes.json();
      const users = body.data || [];

      // Build WA status lookup map
      const waMap = new Map();
      if (waRes && waRes.ok) {
        try {
          const waData = await waRes.json();
          if (Array.isArray(waData.accounts)) {
            waData.accounts.forEach((acc) => {
              if (acc.user_id) waMap.set(acc.user_id, acc);
            });
          }
        } catch (_) {}
      }

      renderUsersTable(users, waMap);
      updatePendingBadge(users);
    } catch (err) {
      if (!isBackground) {
        showToast('Gagal memuat pengguna: ' + err.message, 'error');
      }
    }
  }

  async function fetchInvitations(isBackground = false) {
    try {
      const res = await apiFetch('/api/v1/superadmin/users/invitations');
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const body = await res.json();
      renderInvitationsTable(body.data || []);
    } catch (err) {
      if (!isBackground) {
        showToast('Gagal memuat undangan: ' + err.message, 'error');
      }
    }
  }

  function updatePendingBadge(users) {
    const pendingCount = users.filter((u) => u.status === 'PENDING_APPROVAL').length;
    if (pendingCount > 0) {
      pendingBadge.textContent = pendingCount;
      pendingBadge.classList.remove('hidden');
    } else {
      pendingBadge.classList.add('hidden');
    }
  }

  function renderUsersTable(users, waMap) {
    usersTableBody.innerHTML = '';
    if (users.length === 0) {
      usersTableBody.innerHTML = '<tr><td colspan="8" class="text-center py-4">Tidak ada pengguna yang cocok dengan filter.</td></tr>';
      return;
    }

    users.forEach((user) => {
      const tr = document.createElement('tr');

      let statusBadgeClass = 'badge-pending';
      if (user.status === 'APPROVED') statusBadgeClass = 'badge-approved';
      if (user.status === 'SUSPENDED') statusBadgeClass = 'badge-suspended';
      if (user.status === 'REJECTED') statusBadgeClass = 'badge-rejected';

      // WhatsApp Gateway column rendering
      let waHtml = '<span style="color:var(--text-muted);font-size:0.8125rem;">-</span>';
      if (user.role === 'ADMIN') {
        const waStatus = waMap ? waMap.get(user.id) : null;
        if (waStatus) {
          if (waStatus.status === 'CONNECTED') {
            waHtml = `
              <button type="button" class="btn-wa-status badge-wa-connected btn-inspect-wa" data-user-id="${user.id}" data-user-name="${escapeHtml(user.email)}" title="Klik untuk rincian konfigurasi WA">
                <span class="status-dot" style="background-color: var(--success-color);"></span> Terhubung
              </button>
            `;
          } else if (waStatus.status === 'GATEWAY_DOWN') {
            waHtml = `
              <button type="button" class="btn-wa-status badge-wa-down btn-inspect-wa" data-user-id="${user.id}" data-user-name="${escapeHtml(user.email)}" title="Klik untuk rincian konfigurasi WA">
                <span class="status-dot" style="background-color: var(--danger-color);"></span> GOWA Down
              </button>
            `;
          } else {
            waHtml = `
              <button type="button" class="btn-wa-status badge-wa-disconnected btn-inspect-wa" data-user-id="${user.id}" data-user-name="${escapeHtml(user.email)}" title="Klik untuk rincian konfigurasi WA">
                <span class="status-dot" style="background-color: var(--warning-color);"></span> Belum Konek
              </button>
            `;
          }
        } else {
          waHtml = `
            <button type="button" class="btn-wa-status badge-wa-unknown btn-inspect-wa" data-user-id="${user.id}" data-user-name="${escapeHtml(user.email)}" title="Klik untuk periksa status WA">
              <span>🔍</span> Cek WA
            </button>
          `;
        }
      }

      let actionsHtml = '';
      if (user.status === 'PENDING_APPROVAL') {
        actionsHtml = `
          <button type="button" class="btn btn-sm btn-success btn-user-action" data-action="approve" data-id="${user.id}" data-name="${escapeHtml(user.email)}">Setujui</button>
          <button type="button" class="btn btn-sm btn-danger btn-user-action" data-action="reject" data-id="${user.id}" data-name="${escapeHtml(user.email)}">Tolak</button>
        `;
      } else if (user.status === 'APPROVED') {
        actionsHtml = `
          <button type="button" class="btn btn-sm btn-warning btn-user-action" data-action="suspend" data-id="${user.id}" data-name="${escapeHtml(user.email)}">Tangguhkan</button>
          <button type="button" class="btn btn-sm btn-outline btn-user-action" data-action="revoke_sessions" data-id="${user.id}" data-name="${escapeHtml(user.email)}">Cabut Sesi</button>
        `;
      } else if (user.status === 'SUSPENDED' || user.status === 'REJECTED') {
        actionsHtml = `
          <button type="button" class="btn btn-sm btn-primary btn-user-action" data-action="reactivate" data-id="${user.id}" data-name="${escapeHtml(user.email)}">Aktifkan Kembali</button>
        `;
      }

      tr.innerHTML = `
        <td><strong>${escapeHtml(user.email)}</strong></td>
        <td>${escapeHtml(user.display_name || '-')}</td>
        <td><span class="role-tag">${escapeHtml(user.role)}</span></td>
        <td><span class="badge ${statusBadgeClass}">${escapeHtml(user.status)}</span></td>
        <td>${waHtml}</td>
        <td>${user.active_session_count || 0} sesi</td>
        <td>${new Date(user.created_at).toLocaleDateString()}</td>
        <td class="text-right"><div class="action-buttons">${actionsHtml}</div></td>
      `;
      usersTableBody.appendChild(tr);
    });

    bindActionButtons();
    bindWhatsAppInspectButtons();
  }

  function renderInvitationsTable(invitations) {
    usersTableBody.innerHTML = '';
    if (invitations.length === 0) {
      usersTableBody.innerHTML = '<tr><td colspan="8" class="text-center py-4">Belum ada undangan aktif.</td></tr>';
      return;
    }

    invitations.forEach((inv) => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${escapeHtml(inv.email)}</strong></td>
        <td>Outlet: ${escapeHtml(inv.outlet_name || '-')}</td>
        <td><span class="role-tag">CASHIER (UNDANGAN)</span></td>
        <td><span class="badge badge-pending">UNDANGAN AKTIF</span></td>
        <td><span style="color:var(--text-muted);font-size:0.8125rem;">-</span></td>
        <td>-</td>
        <td>Kadaluarsa: ${new Date(inv.expires_at).toLocaleDateString()}</td>
        <td class="text-right">
          <button type="button" class="btn btn-sm btn-danger btn-user-action" data-action="revoke_invitation" data-id="${inv.id}" data-name="${escapeHtml(inv.email)}">Cabut Undangan</button>
        </td>
      `;
      usersTableBody.appendChild(tr);
    });

    bindActionButtons();
  }

  function bindActionButtons() {
    document.querySelectorAll('.btn-user-action').forEach((btn) => {
      btn.addEventListener('click', () => {
        const action = btn.getAttribute('data-action');
        const id = btn.getAttribute('data-id');
        const name = btn.getAttribute('data-name');
        openActionDialog(action, id, name);
      });
    });
  }

  function bindWhatsAppInspectButtons() {
    document.querySelectorAll('.btn-inspect-wa').forEach((btn) => {
      btn.addEventListener('click', () => {
        const userId = btn.getAttribute('data-user-id');
        const userName = btn.getAttribute('data-user-name');
        openWhatsAppInfoDialog(userId, userName);
      });
    });
  }

  // ==========================================
  // WHATSAPP GATEWAY INFO MODAL
  // ==========================================
  async function openWhatsAppInfoDialog(userId, userName) {
    currentInspectingWAUserId = userId;
    currentInspectingWAUserName = userName;

    waInfoLoading.classList.remove('hidden');
    waInfoContent.classList.add('hidden');
    waInfoError.classList.add('hidden');

    dialogWaInfo.showModal();

    await loadWhatsAppStatus(userId, userName);
  }

  async function loadWhatsAppStatus(userId, userName) {
    waInfoLoading.classList.remove('hidden');
    waInfoContent.classList.add('hidden');
    waInfoError.classList.add('hidden');

    try {
      const res = await apiFetch(`/api/v1/superadmin/users/${userId}/whatsapp`);
      if (!res.ok) {
        const errJson = await res.json().catch(() => ({}));
        throw new Error(errJson.error ? errJson.error.message : `HTTP ${res.status}`);
      }
      const data = await res.json();

      // Render modal content
      waInfoUser.textContent = `${data.display_name || userName || '-'} (${data.email_masked || '-'})`;
      waInfoPhone.textContent = data.phone_masked || '(Belum terdaftar)';
      waInfoDevice.textContent = data.device_id || '(Default Device)';
      waInfoMessage.textContent = data.message || '-';

      // Set Banner
      waStatusBanner.className = 'wa-status-banner mb-3';
      if (data.status === 'CONNECTED') {
        waStatusBanner.classList.add('status-healthy');
        waModalDot.style.backgroundColor = 'var(--success-color)';
        waModalStatusText.textContent = 'Status: Terhubung Aktif (Online)';
      } else if (data.status === 'GATEWAY_DOWN') {
        waStatusBanner.classList.add('status-down');
        waModalDot.style.backgroundColor = 'var(--danger-color)';
        waModalStatusText.textContent = 'Status: Gateway GOWA Tidak Dapat Dihubungi';
      } else {
        waStatusBanner.classList.add('status-degraded');
        waModalDot.style.backgroundColor = 'var(--warning-color)';
        waModalStatusText.textContent = 'Status: Belum Terhubung (Menunggu Scan QR)';
      }

      waInfoLoading.classList.add('hidden');
      waInfoContent.classList.remove('hidden');
    } catch (err) {
      waInfoLoading.classList.add('hidden');
      waInfoError.textContent = 'Gagal memeriksa status WhatsApp: ' + (err.message || 'Koneksi error');
      waInfoError.classList.remove('hidden');
    }
  }

  if (btnCloseWa) {
    btnCloseWa.addEventListener('click', () => dialogWaInfo.close());
  }
  if (btnCloseWaFooter) {
    btnCloseWaFooter.addEventListener('click', () => dialogWaInfo.close());
  }
  if (btnRefreshWaSingle) {
    btnRefreshWaSingle.addEventListener('click', () => {
      if (currentInspectingWAUserId) {
        loadWhatsAppStatus(currentInspectingWAUserId, currentInspectingWAUserName);
        showToast('Memeriksa ulang status WhatsApp...', 'info');
      }
    });
  }

  // ==========================================
  // DIALOG ACTION HANDLERS
  // ==========================================
  function openActionDialog(action, id, name) {
    pendingAction = { action, id, name };
    actionError.classList.add('hidden');
    actionReason.value = '';

    btnConfirmAction.className = 'btn';

    if (action === 'approve') {
      actionTargetDesc.textContent = `Setujui Akun: ${name}`;
      actionDetailText.textContent = 'Akun Admin ini akan disetujui untuk mengelola outlet dan login penuh ke aplikasi mobile.';
      btnConfirmAction.classList.add('btn-success');
      btnConfirmAction.textContent = 'Ya, Setujui Akun';
    } else if (action === 'reject') {
      actionTargetDesc.textContent = `Tolak Akun: ${name}`;
      actionDetailText.textContent = 'Pendaftaran akun Admin ini akan ditolak. Seluruh sesi aktif akan segera dibatalkan.';
      btnConfirmAction.classList.add('btn-danger');
      btnConfirmAction.textContent = 'Tolak Pendaftaran';
    } else if (action === 'suspend') {
      actionTargetDesc.textContent = `Tangguhkan Akun: ${name}`;
      actionDetailText.textContent = 'PERINGATAN: Akun ini akan segera ditangguhkan dan seluruh sesi aktif di perangkat mobile akan dicabut!';
      btnConfirmAction.classList.add('btn-warning');
      btnConfirmAction.textContent = 'Tangguhkan Akun';
    } else if (action === 'reactivate') {
      actionTargetDesc.textContent = `Aktifkan Kembali: ${name}`;
      actionDetailText.textContent = 'Akun ini akan dikembalikan ke status APPROVED sehingga Admin dapat login kembali.';
      btnConfirmAction.classList.add('btn-primary');
      btnConfirmAction.textContent = 'Aktifkan Kembali';
    } else if (action === 'revoke_sessions') {
      actionTargetDesc.textContent = `Cabut Seluruh Sesi: ${name}`;
      actionDetailText.textContent = 'Tindakan ini akan memaksa logout akun ini dari seluruh perangkat mobile atau web.';
      btnConfirmAction.classList.add('btn-danger');
      btnConfirmAction.textContent = 'Cabut Sesi Sekarang';
    } else if (action === 'revoke_invitation') {
      actionTargetDesc.textContent = `Cabut Undangan: ${name}`;
      actionDetailText.textContent = 'Undangan Kasir ini akan dibatalkan dan tidak dapat digunakan untuk aktivasi login.';
      btnConfirmAction.classList.add('btn-danger');
      btnConfirmAction.textContent = 'Batalkan Undangan';
    }

    dialogAction.showModal();
  }

  formAction.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (!pendingAction) return;

    const { action, id, name } = pendingAction;
    const reason = actionReason.value.trim();

    try {
      let res;
      if (action === 'approve') {
        res = await apiFetch(`/api/v1/superadmin/users/${id}/approve`, { method: 'POST', body: { reason } });
      } else if (action === 'reject') {
        res = await apiFetch(`/api/v1/superadmin/users/${id}/reject`, { method: 'POST', body: { reason } });
      } else if (action === 'suspend') {
        res = await apiFetch(`/api/v1/superadmin/users/${id}/suspend`, { method: 'POST', body: { reason } });
      } else if (action === 'reactivate') {
        res = await apiFetch(`/api/v1/superadmin/users/${id}/reactivate`, { method: 'POST', body: { reason } });
      } else if (action === 'revoke_sessions') {
        res = await apiFetch(`/api/v1/superadmin/users/${id}/revoke-sessions`, { method: 'POST' });
      } else if (action === 'revoke_invitation') {
        res = await apiFetch(`/api/v1/superadmin/users/invitations/${id}`, { method: 'DELETE' });
      }

      if (!res.ok) {
        const errJson = await res.json().catch(() => ({}));
        throw new Error(errJson.error ? errJson.error.message : `HTTP ${res.status}`);
      }

      dialogAction.close();
      showToast(`Tindakan pada ${name} berhasil dieksekusi.`, 'success');
      fetchUsers();
    } catch (err) {
      actionError.textContent = err.message || 'Gagal mengeksekusi tindakan.';
      actionError.classList.remove('hidden');
    }
  });

  btnCloseAction.addEventListener('click', () => dialogAction.close());
  btnCancelAction.addEventListener('click', () => dialogAction.close());

  // Invite Dialog Handlers
  btnOpenInvite.addEventListener('click', () => {
    inviteError.classList.add('hidden');
    inviteEmail.value = '';
    inviteOutlet.value = '';
    dialogInvite.showModal();
  });

  btnCloseInvite.addEventListener('click', () => dialogInvite.close());
  btnCancelInvite.addEventListener('click', () => dialogInvite.close());

  formInvite.addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = inviteEmail.value.trim();
    const outletName = inviteOutlet.value.trim();

    if (!email) return;

    try {
      const res = await apiFetch('/api/v1/superadmin/users/invite', {
        method: 'POST',
        body: { email, outlet_name: outletName }
      });

      if (!res.ok) {
        const errJson = await res.json().catch(() => ({}));
        throw new Error(errJson.error ? errJson.error.message : `HTTP ${res.status}`);
      }

      dialogInvite.close();
      showToast(`Undangan untuk ${email} berhasil dikirim.`, 'success');
      if (userStatusFilter === 'INVITED') {
        fetchInvitations();
      } else {
        fetchUsers();
      }
    } catch (err) {
      inviteError.textContent = err.message || 'Gagal mengirim undangan.';
      inviteError.classList.remove('hidden');
    }
  });

  // ==========================================
  // TAB 3: Activity Audits
  // ==========================================
  async function fetchAudits(isBackground = false) {
    try {
      const res = await apiFetch('/api/v1/superadmin/audits');
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const body = await res.json();
      renderAuditsTable(body.data || []);
    } catch (err) {
      if (!isBackground) {
        showToast('Gagal memuat log audit: ' + err.message, 'error');
      }
    }
  }

  function renderAuditsTable(audits) {
    auditsTableBody.innerHTML = '';
    if (audits.length === 0) {
      auditsTableBody.innerHTML = '<tr><td colspan="6" class="text-center py-4">Belum ada riwayat audit aktivitas.</td></tr>';
      return;
    }

    audits.forEach((a) => {
      const tr = document.createElement('tr');
      const transitionText = a.from_status ? `${a.from_status} → ${a.to_status}` : a.to_status;
      tr.innerHTML = `
        <td>${new Date(a.created_at).toLocaleString()}</td>
        <td><strong>${escapeHtml(a.target_email || a.user_id)}</strong></td>
        <td><span class="role-tag">${escapeHtml(transitionText)}</span></td>
        <td>${escapeHtml(a.reason || '-')}</td>
        <td>${escapeHtml(a.actor_email || a.actor_user_id || 'System')}</td>
        <td><code style="font-size: 0.75rem;">${escapeHtml(a.request_id || '-')}</code></td>
      `;
      auditsTableBody.appendChild(tr);
    });
  }

  if (btnRefreshAudits) {
    btnRefreshAudits.addEventListener('click', () => {
      fetchAudits();
      showToast('Log audit disegarkan.', 'info');
    });
  }

  // Utilities
  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // Initialize
  initTheme();
  initAuth();
})();
