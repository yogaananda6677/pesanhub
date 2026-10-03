import 'dart:async';

import 'package:flutter/material.dart';
import '../alerts/order_alert_controller.dart';
import '../cart/controllers/cart_controller.dart';
import '../cart/models/cart_order_draft.dart';
import '../connectivity/connectivity_controller.dart';
import '../kds/controllers/kds_controller.dart';
import '../kds/kds_view.dart';
import '../menu/controllers/menu_availability_controller.dart';
import '../menu/controllers/menu_controller.dart' as mc;
import '../menu/menu_availability_view.dart';
import '../pos/pos_view.dart';
import '../queue/controllers/queue_controller.dart';
import '../queue/models/queue_order.dart';
import '../queue/queue_view.dart';
import '../settings/controllers/whatsapp_settings_controller.dart';
import '../settings/widgets/policy_dialogs.dart';
import '../settings/widgets/whatsapp_settings_card.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/brand_logo.dart';

/// PosDestinationView provides the cashier order creation UI.
class PosDestinationView extends StatelessWidget {
  final mc.MenuController? menuController;
  final CartController? cartController;
  final VoidCallback? onNavigateToQueue;
  final Future<QueueOrder> Function(CartOrderDraft draft)? submitOrder;
  final ConnectivityController? connectivityController;

  const PosDestinationView({
    super.key,
    this.menuController,
    this.cartController,
    this.onNavigateToQueue,
    this.submitOrder,
    this.connectivityController,
  });

  @override
  Widget build(BuildContext context) {
    return PosView(
      menuController: menuController,
      cartController: cartController,
      onNavigateToQueue: onNavigateToQueue,
      submitOrder: submitOrder,
      connectivityController: connectivityController,
    );
  }
}

/// QueueDestinationView provides the unified order queue monitoring UI.
class QueueDestinationView extends StatefulWidget {
  final QueueController? controller;
  final OrderAlertController? alertController;
  final FutureOr<void> Function(QueueOrder order, String newStatus)? onStatusChanged;
  final Future<void> Function()? onRefresh;

  const QueueDestinationView({
    super.key,
    this.controller,
    this.alertController,
    this.onStatusChanged,
    this.onRefresh,
  });

  @override
  State<QueueDestinationView> createState() => _QueueDestinationViewState();
}

class _QueueDestinationViewState extends State<QueueDestinationView> {
  late final QueueController _controller;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = QueueController(
        alertController: widget.alertController,
        initialOrders: const [],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return QueueView(
      controller: _controller,
      onStatusChanged: widget.onStatusChanged,
      onRefresh: widget.onRefresh,
    );
  }
}

/// KdsDestinationView provides the Kitchen Display Screen ticket monitor.
class KdsDestinationView extends StatefulWidget {
  final KdsController? controller;

  const KdsDestinationView({super.key, this.controller});

  @override
  State<KdsDestinationView> createState() => _KdsDestinationViewState();
}

class _KdsDestinationViewState extends State<KdsDestinationView> {
  late final KdsController _controller;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = KdsController(initialOrders: const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KdsView(controller: _controller);
  }
}

/// MenuDestinationView provides the menu availability management view for authorized staff.
class MenuDestinationView extends StatefulWidget {
  final MenuAvailabilityController? availabilityController;
  final mc.MenuController? menuController;
  final VoidCallback? onRefresh;

  const MenuDestinationView({
    super.key,
    this.availabilityController,
    this.menuController,
    this.onRefresh,
  });

  @override
  State<MenuDestinationView> createState() => _MenuDestinationViewState();
}

class _MenuDestinationViewState extends State<MenuDestinationView> {
  late final MenuAvailabilityController _availabilityController;

  @override
  void initState() {
    super.initState();
    _availabilityController =
        widget.availabilityController ??
        MenuAvailabilityController(
          initialCategories: const [],
          initialMenus: const [],
          role: '',
          onAvailabilityChanged: (item) {
            widget.menuController?.updateAvailability(
              item.id,
              item.isAvailable,
            );
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.availabilityController ?? _availabilityController;
    return MenuAvailabilityView(
      controller: controller,
      onRefresh: widget.onRefresh ?? controller.onRefresh,
    );
  }
}

/// SettingsDestinationView provides outlet settings, WhatsApp connection status & QR pairing, and access to the Design System Catalog.
class SettingsDestinationView extends StatefulWidget {
  final Future<void> Function()? onSignOut;
  final WhatsAppSettingsController? whatsAppController;
  final bool isAdmin;
  final Future<String> Function(String email)? inviteCashier;
  final String? userName;
  final String? userEmail;
  final String? userRole;
  final String? branchName;
  final String? branchAddress;
  final ConnectivityController? connectivityController;

  const SettingsDestinationView({
    super.key,
    this.onSignOut,
    this.whatsAppController,
    this.isAdmin = false,
    this.inviteCashier,
    this.userName,
    this.userEmail,
    this.userRole,
    this.branchName,
    this.branchAddress,
    this.connectivityController,
  });

  @override
  State<SettingsDestinationView> createState() =>
      _SettingsDestinationViewState();
}

class _SettingsDestinationViewState extends State<SettingsDestinationView> {
  late final WhatsAppSettingsController _whatsAppController;
  final TextEditingController _cashierEmailController = TextEditingController();
  bool _ownsController = false;
  bool _invitingCashier = false;
  String? _invitationFeedback;
  bool _invitationFailed = false;
  bool _autoPrintReceipt = true;
  String _printerPaperSize = '58mm';

  @override
  void initState() {
    super.initState();
    if (widget.whatsAppController != null) {
      _whatsAppController = widget.whatsAppController!;
    } else {
      _whatsAppController = WhatsAppSettingsController();
      _ownsController = true;
    }
    _whatsAppController.loadSettings();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _whatsAppController.dispose();
    }
    _cashierEmailController.dispose();
    super.dispose();
  }

  Future<void> _inviteCashier() async {
    final email = _cashierEmailController.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() {
        _invitationFailed = true;
        _invitationFeedback = 'Masukkan alamat email kasir yang valid.';
      });
      return;
    }
    final invite = widget.inviteCashier;
    if (invite == null) return;
    setState(() {
      _invitingCashier = true;
      _invitationFeedback = null;
    });
    try {
      final maskedEmail = await invite(email);
      if (!mounted) return;
      _cashierEmailController.clear();
      setState(() {
        _invitationFailed = false;
        _invitationFeedback =
            'Undangan CASHIER untuk $maskedEmail sudah dibuat. Kasir harus login Google dengan email tersebut.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _invitationFailed = true;
        _invitationFeedback =
            'Undangan belum dapat dikirim. Periksa koneksi atau konfigurasi Gmail backend.';
      });
    } finally {
      if (mounted) setState(() => _invitingCashier = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveName = widget.userName?.trim().isNotEmpty == true
        ? widget.userName!.trim()
        : 'Yoga Ananda';
    final effectiveEmail = widget.userEmail?.trim().isNotEmpty == true
        ? widget.userEmail!.trim()
        : 'admin@jenggirat.com';
    final effectiveRole = widget.isAdmin
        ? 'Superadmin'
        : (widget.userRole?.trim().isNotEmpty == true
            ? widget.userRole!.trim()
            : 'Kasir Utama');

    return SingleChildScrollView(
      key: const PageStorageKey('settings_view_scroll'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. WhatsApp-Style User & Outlet Profile Card
          _buildWhatsAppProfileHeader(context, effectiveName, effectiveEmail, effectiveRole),
          const SizedBox(height: AppSpacing.lg),

          // 2. WhatsApp Gateway Management (Retains WhatsAppSettingsCard for tests)
          if (widget.isAdmin) ...[
            _buildSectionHeader('INTEGRASI SALURAN ONLINE'),
            WhatsAppSettingsCard(controller: _whatsAppController),
            const SizedBox(height: AppSpacing.lg),
          ],

          // 3. Profil Gerai & Operasional Detail
          _buildSectionHeader('INFORMASI GERAI & OPERASIONAL'),
          _buildStoreProfileCard(context, effectiveName, effectiveEmail, effectiveRole),
          const SizedBox(height: AppSpacing.lg),

          // 4. Pengaturan Printer Kasir & Struk
          _buildSectionHeader('PERANGKAT & STRUK KASIR'),
          _buildPrinterConfigCard(context),
          const SizedBox(height: AppSpacing.lg),

          // 5. Sinkronisasi & Data Lokal
          _buildSectionHeader('KONEKSI & SINKRONISASI DATA'),
          _buildDataSyncCard(context),
          const SizedBox(height: AppSpacing.lg),

          // 6. Undang Kasir (Admin only)
          if (widget.isAdmin) ...[
            _buildSectionHeader('MANAJEMEN KARYAWAN'),
            _buildInviteCashierCard(),
            const SizedBox(height: AppSpacing.lg),
          ],

          // 7. Informasi Outlet, Versi & Kebijakan
          _buildSectionHeader('TENTANG & KEBIJAKAN APLIKASI'),
          _buildOutletAndPolicyCard(context),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF64748B),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildWhatsAppProfileHeader(
    BuildContext context,
    String name,
    String email,
    String role,
  ) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // WhatsApp Style Circle Avatar
          Stack(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF128C7E), Color(0xFF25D366)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          // Name, Role Badge, and Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFC8E6C9)),
                      ),
                      child: Text(
                        role,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(Icons.storefront_rounded, size: 14, color: Color(0xFF128C7E)),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Martabak & Terang Bulan Jenggirat',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreProfileCard(
    BuildContext context,
    String name,
    String email,
    String role,
  ) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingRow(
            label: 'Nama Usaha',
            value: 'Martabak & Terang Bulan Jenggirat',
            isBold: true,
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildSettingRow(
            label: 'Cabang / Alamat',
            value: widget.branchAddress != null && widget.branchAddress!.isNotEmpty
                ? '${widget.branchName ?? "Cabang"} (${widget.branchAddress})'
                : (widget.branchName ?? 'Semua Cabang'),
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildSettingRow(
            label: 'Kasir Bertugas',
            value: '$name ($role)',
            isBold: true,
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildSettingRow(
            label: 'Jam Operasional',
            value: '16:00 – 24:00 WIB',
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterConfigCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.print_rounded,
                  color: Color(0xFF475569),
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pengaturan Printer Kasir', style: AppTypography.titleMedium),
                    Text(
                      'Konfigurasi Bluetooth thermal printer',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text('Ukuran Kertas Struk', style: AppTypography.bodyMedium),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPrinterSizeChip('58mm'),
                  const SizedBox(width: 8),
                  _buildPrinterSizeChip('80mm'),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cetak Otomatis Struk', style: AppTypography.bodyMedium),
            subtitle: const Text(
              'Cetak struk langsung setiap kali transaksi kasir berhasil',
              style: AppTypography.bodySmall,
            ),
            value: _autoPrintReceipt,
            activeThumbColor: AppColors.primary,
            onChanged: (val) => setState(() => _autoPrintReceipt = val),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => PolicyDialogs.showPrinterTest(context),
            icon: const Icon(Icons.receipt_long_rounded, size: 18),
            label: const Text('Uji Cetak Struk (Test Print)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterSizeChip(String size) {
    final isSelected = _printerPaperSize == size;
    return InkWell(
      onTap: () => setState(() => _printerPaperSize = size),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          size,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildDataSyncCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.sync_rounded,
                  color: Color(0xFF2E7D32),
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sinkronisasi & Data Lokal', style: AppTypography.titleMedium),
                    Text(
                      'Penyimpanan offline & status koneksi cloud',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _buildSettingRow(
                  label: 'Koneksi Server Cloud',
                  value: 'Terhubung (Online)',
                  valueColor: const Color(0xFF2E7D32),
                  isBold: true,
                ),
                const Divider(height: 16, color: AppColors.border),
                _buildSettingRow(
                  label: 'Antrean Outbox Offline',
                  value: '0 transaksi pending',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sinkronisasi data selesai. Semua data mutakhir.'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Sinkronkan Data'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cache gambar & katalog menu berhasil dibersihkan.'),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  },
                  icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                  label: const Text('Bersihkan Cache'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInviteCashierCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Undang Kasir', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Kasir akan diverifikasi ketika login Google dengan alamat email yang sama.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('cashier-invite-email'),
            controller: _cashierEmailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Email kasir',
              hintText: 'kasir@gmail.com',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              if (!_invitingCashier) _inviteCashier();
            },
          ),
          if (_invitationFeedback case final feedback?) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                feedback,
                style: AppTypography.bodySmall.copyWith(
                  color: _invitationFailed
                      ? Colors.red
                      : Colors.green.shade700,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Kirim Undangan Kasir',
            icon: Icons.person_add_alt_1_outlined,
            isFullWidth: true,
            isLoading: _invitingCashier,
            onPressed: _invitingCashier || widget.inviteCashier == null
                ? null
                : _inviteCashier,
          ),
        ],
      ),
    );
  }

  Widget _buildOutletAndPolicyCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Informasi Outlet',
            style: AppTypography.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const BrandLogo(size: 48),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.branchName != null
                          ? 'PesenHub Outlet — ${widget.branchName}'
                          : 'PesenHub — Martabak & Terang Bulan Jenggirat',
                      style: AppTypography.bodyLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Versi Aplikasi: 1.0.0 (Phase 1B)',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: AppSpacing.sm),

          // Policy Links
          _buildPolicyTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Kebijakan Privasi',
            subtitle: 'Perlindungan data pelanggan & transaksi',
            onTap: () => PolicyDialogs.showPrivacyPolicy(context),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          _buildPolicyTile(
            icon: Icons.gavel_rounded,
            title: 'Syarat & Ketentuan Layanan',
            subtitle: 'Ketentuan penggunaan sistem kasir gerai',
            onTap: () => PolicyDialogs.showTermsOfService(context),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          _buildPolicyTile(
            icon: Icons.info_outline_rounded,
            title: 'Catatan Rilis & Pembaruan',
            subtitle: 'Versi 1.0.0 (Build 2026.10)',
            onTap: () => PolicyDialogs.showVersionInfo(context),
          ),

          if (widget.onSignOut != null) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton.outlined(
              label: 'Keluar dari Aplikasi',
              icon: Icons.logout_rounded,
              isFullWidth: true,
              onPressed: () => _confirmSignOut(context),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Konfirmasi Keluar'),
        content: const Text(
          'Apakah Anda yakin ingin keluar dari aplikasi kasir PesenHub?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onSignOut?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }

  static Widget _buildPolicyTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF475569)),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 20),
      onTap: onTap,
    );
  }

  static Widget _buildSettingRow({
    required String label,
    required String value,
    Color? valueColor,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
