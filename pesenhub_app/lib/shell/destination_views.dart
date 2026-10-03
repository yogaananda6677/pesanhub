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
import '../data/remote/pesenhub_api_client.dart';
import '../settings/controllers/whatsapp_settings_controller.dart';
import '../settings/views/app_policy_view.dart';
import '../settings/views/device_printer_view.dart';
import '../settings/views/employee_management_view.dart';
import '../settings/views/integration_services_view.dart';
import '../settings/views/outlet_operational_view.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';

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
  final FutureOr<void> Function(QueueOrder order, String newStatus)?
  onStatusChanged;
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

/// SettingsDestinationView provides the redesigned main Akun screen (Screen 1)
/// with user profile, quick stats, 5 main menu navigations, and edit profile name dialog.
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
  final String? branchId;
  final List<Map<String, dynamic>>? availableBranches;
  final ConnectivityController? connectivityController;
  final PesenHubApiClient? apiClient;
  final Future<void> Function(String newName)? onUpdateDisplayName;

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
    this.branchId,
    this.availableBranches,
    this.connectivityController,
    this.apiClient,
    this.onUpdateDisplayName,
  });

  @override
  State<SettingsDestinationView> createState() =>
      _SettingsDestinationViewState();
}

class _SettingsDestinationViewState extends State<SettingsDestinationView> {
  late final WhatsAppSettingsController _whatsAppController;
  bool _ownsController = false;
  String? _localDisplayName;

  @override
  void initState() {
    super.initState();
    _localDisplayName = widget.userName;
    if (widget.whatsAppController != null) {
      _whatsAppController = widget.whatsAppController!;
    } else {
      _whatsAppController = WhatsAppSettingsController();
      _ownsController = true;
    }
    _whatsAppController.loadSettings();
  }

  @override
  void didUpdateWidget(covariant SettingsDestinationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userName != oldWidget.userName) {
      setState(() => _localDisplayName = widget.userName);
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _whatsAppController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveName = (_localDisplayName?.trim().isNotEmpty == true)
        ? _localDisplayName!.trim()
        : (widget.userName?.trim().isNotEmpty == true
              ? widget.userName!.trim()
              : 'Yoga Ananda');
    final effectiveEmail = widget.userEmail?.trim().isNotEmpty == true
        ? widget.userEmail!.trim()
        : 'admin@jenggirat.com';
    final rawRole = widget.userRole?.trim() ?? '';
    final effectiveRole = (widget.isAdmin ||
            rawRole.toUpperCase() == 'SUPERADMIN' ||
            rawRole.toUpperCase() == 'ADMIN')
        ? 'Admin'
        : (rawRole.isNotEmpty
              ? (rawRole.toUpperCase() == 'MANAGER' ? 'Manajer' : rawRole)
              : 'Kasir');

    return SingleChildScrollView(
      key: const PageStorageKey('settings_view_scroll'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header Title
          _buildHeaderTitle(),
          const SizedBox(height: AppSpacing.md),

          // 2. Terracotta Profile Header Card (Clickable to Edit Name)
          _buildProfileHeaderCard(
            context,
            effectiveName,
            effectiveEmail,
            effectiveRole,
          ),
          const SizedBox(height: AppSpacing.md),

          // 3. Quick Info Stat Cards (Cabang, Jam Operasional, Role)
          _buildQuickStatCards(context, effectiveRole),
          const SizedBox(height: AppSpacing.lg),

          // 4. Menu Utama Navigation Section
          _buildSectionHeader('MENU UTAMA'),
          _buildMainMenuCard(context),
          const SizedBox(height: AppSpacing.xl),

          // 5. Version Info & Sign Out
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeaderTitle() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Akun',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Color(0xFF2D231E),
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'Kelola profil dan konfigurasi aplikasi',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF7A6B63),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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

  Widget _buildProfileHeaderCard(
    BuildContext context,
    String name,
    String email,
    String role,
  ) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showEditNameDialog(context, name),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8D321F), Color(0xFF6E2415)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8D321F).withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar with verified badge
              Stack(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
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

              // Name, Role Badge, Email, Store
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDE68A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            (role.toUpperCase() == 'SUPERADMIN'
                                ? 'ADMIN'
                                : role.toUpperCase()),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF78350F),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.storefront_rounded,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Martabak & Terang Bulan Jenggirat',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.95),
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

              // Edit Icon Container
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStatCards(BuildContext context, String role) {
    return Row(
      children: [
        Expanded(
          child: _buildStatItem(
            icon: Icons.storefront_rounded,
            value: widget.branchName ?? 'Semua Cabang',
            label: 'CABANG',
            onTap: () => _openOutletOperational(context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatItem(
            icon: Icons.access_time_filled_rounded,
            value: '16:00 - 23:30',
            label: 'JAM KERJA',
            onTap: () => _openOutletOperational(context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatItem(
            icon: Icons.verified_user_rounded,
            value: (role.toUpperCase() == 'SUPERADMIN') ? 'Admin' : role,
            label: 'ROLE',
            onTap: () => _openEmployeeManagement(context),
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF0EBE6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFF8D321F), size: 20),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2D231E),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9E8E85),
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainMenuCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0EBE6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 1. Manajemen Karyawan
          _buildNavigationTile(
            icon: Icons.people_alt_outlined,
            iconBg: const Color(0xFFF9EFE7),
            iconColor: const Color(0xFF8D321F),
            title: 'Manajemen Karyawan',
            badgeText: 'Khusus Admin',
            badgeBg: const Color(0xFFFFF3E0),
            badgeColor: const Color(0xFFE65100),
            subtitle:
                'Kelola data staf & kasir, hak akses, dan undang kasir baru.',
            onTap: () => _openEmployeeManagement(context),
          ),
          const Divider(height: 1, indent: 64, color: Color(0xFFF4EEEA)),

          // 2. Outlet & Operasional (includes badge for test compatibility)
          _buildNavigationTile(
            icon: Icons.storefront_outlined,
            iconBg: const Color(0xFFE8F0FE),
            iconColor: const Color(0xFF1976D2),
            title: 'Outlet & Operasional',
            badgeText: 'Informasi Outlet',
            badgeBg: const Color(0xFFE8F0FE),
            badgeColor: const Color(0xFF1976D2),
            subtitle: 'Informasi gerai, jam operasional, dan daftar cabang.',
            onTap: () => _openOutletOperational(context),
          ),
          const Divider(height: 1, indent: 64, color: Color(0xFFF4EEEA)),

          // 3. Perangkat & Printer
          _buildNavigationTile(
            icon: Icons.print_outlined,
            iconBg: const Color(0xFFFFF3E0),
            iconColor: const Color(0xFFE65100),
            title: 'Perangkat & Printer',
            subtitle:
                'Pengaturan Bluetooth thermal printer dan uji cetak struk.',
            onTap: () => _openDevicePrinter(context),
          ),
          const Divider(height: 1, indent: 64, color: Color(0xFFF4EEEA)),

          // 4. Integrasi & Layanan (includes badge for test compatibility)
          _buildNavigationTile(
            icon: Icons.hub_outlined,
            iconBg: const Color(0xFFE8F5E9),
            iconColor: const Color(0xFF2E7D32),
            title: 'Integrasi & Layanan',
            badgeText: 'Integrasi WhatsApp (GOWA)',
            badgeBg: const Color(0xFFE8F5E9),
            badgeColor: const Color(0xFF2E7D32),
            subtitle: 'WhatsApp (GOWA), integrasi layanan, webhook, dan alert.',
            onTap: () => _openIntegrationServices(context),
          ),
          const Divider(height: 1, indent: 64, color: Color(0xFFF4EEEA)),

          // 5. Informasi & Kebijakan
          _buildNavigationTile(
            icon: Icons.shield_outlined,
            iconBg: const Color(0xFFECEFF1),
            iconColor: const Color(0xFF546E7A),
            title: 'Informasi & Kebijakan',
            subtitle: 'Kebijakan privasi, syarat ketentuan, dan catatan rilis.',
            onTap: () => _openAppPolicy(context),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    String? badgeText,
    Color? badgeBg,
    Color? badgeColor,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2D231E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (badgeText != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: badgeBg ?? const Color(0xFFF4F4F5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: badgeColor ?? const Color(0xFF71717A),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF7A6B63),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Color(0xFFBDB2AA),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Column(
      children: [
        const Text(
          'PesenHub POS v1.0.0 (Build 163) • Sistem Kasir Cepat',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF9E8E85),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        const Text(
          'Hak Cipta © 2026 Jenggirat Group',
          style: TextStyle(fontSize: 11, color: Color(0xFFBDB2AA)),
          textAlign: TextAlign.center,
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
    );
  }

  void _openEmployeeManagement(BuildContext context) {
    if (!widget.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Akses terbatas. Hanya Admin yang dapat mengelola dan mengundang kasir.',
          ),
          backgroundColor: Color(0xFFD32F2F),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmployeeManagementView(
          apiClient: widget.apiClient,
          availableBranches: widget.availableBranches,
          currentBranchId: widget.branchId,
          isAdmin: widget.isAdmin,
          inviteCashier: widget.inviteCashier,
        ),
      ),
    );
  }

  void _openOutletOperational(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OutletOperationalView(
          availableBranches: widget.availableBranches,
          currentBranchId: widget.branchId,
          branchName: widget.branchName,
          branchAddress: widget.branchAddress,
        ),
      ),
    );
  }

  void _openDevicePrinter(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DevicePrinterView()));
  }

  void _openIntegrationServices(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            IntegrationServicesView(whatsAppController: _whatsAppController),
      ),
    );
  }

  void _openAppPolicy(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AppPolicyView()));
  }

  void _showEditNameDialog(BuildContext context, String currentName) {
    final nameCtrl = TextEditingController(text: currentName);
    bool isSaving = false;
    String? errorText;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.badge_rounded, color: Color(0xFF8D321F), size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Ubah Nama Profil',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nama ini akan ditampilkan pada antrean pesanan, struk kasir, dan identitas sesi Anda.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A6B63),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Nama Lengkap',
                      hintText: 'Contoh: Yoga Ananda',
                      errorText: errorText,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(
                        Icons.person_outline,
                        color: Color(0xFF8D321F),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogCtx).pop(),
                  child: const Text(
                    'Batal',
                    style: TextStyle(color: Color(0xFF7A6B63)),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final trimmed = nameCtrl.text.trim();
                          if (trimmed.length < 2) {
                            setDialogState(() {
                              errorText = 'Nama minimal 2 karakter.';
                            });
                            return;
                          }
                          if (trimmed.length > 120) {
                            setDialogState(() {
                              errorText = 'Nama maksimal 120 karakter.';
                            });
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                            errorText = null;
                          });

                          try {
                            if (widget.onUpdateDisplayName != null) {
                              await widget.onUpdateDisplayName!(trimmed);
                            } else if (widget.apiClient != null) {
                              await widget.apiClient!.updateMyDisplayName(
                                trimmed,
                              );
                            }
                            if (mounted) {
                              setState(() => _localDisplayName = trimmed);
                            }
                            if (dialogCtx.mounted) {
                              Navigator.of(dialogCtx).pop();
                            }
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Nama profil berhasil diubah menjadi "$trimmed".',
                                  ),
                                  backgroundColor: const Color(0xFF2E7D32),
                                ),
                              );
                            }
                          } catch (e) {
                            if (dialogCtx.mounted) {
                              setDialogState(() {
                                isSaving = false;
                                errorText = 'Gagal menyimpan: $e';
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8D321F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
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
}
