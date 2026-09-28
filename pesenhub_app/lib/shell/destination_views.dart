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
import '../settings/widgets/whatsapp_settings_card.dart';
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

  const QueueDestinationView({
    super.key,
    this.controller,
    this.alertController,
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
    return QueueView(controller: _controller);
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

  const MenuDestinationView({
    super.key,
    this.availabilityController,
    this.menuController,
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
    return MenuAvailabilityView(controller: _availabilityController);
  }
}

/// SettingsDestinationView provides outlet settings, WhatsApp connection status & QR pairing, and access to the Design System Catalog.
class SettingsDestinationView extends StatefulWidget {
  final Future<void> Function()? onSignOut;
  final WhatsAppSettingsController? whatsAppController;
  final bool isAdmin;
  final Future<String> Function(String email)? inviteCashier;

  const SettingsDestinationView({
    super.key,
    this.onSignOut,
    this.whatsAppController,
    this.isAdmin = false,
    this.inviteCashier,
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
    return SingleChildScrollView(
      key: const PageStorageKey('settings_view_scroll'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.isAdmin) ...[
            WhatsAppSettingsCard(controller: _whatsAppController),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
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
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          AppCard(
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
                          const Text(
                            'PesenHub Outlet #01 — Martabak & Terang Bulan Pusat',
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
                if (widget.onSignOut != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppButton.outlined(
                    label: 'Keluar dari Aplikasi',
                    icon: Icons.logout_rounded,
                    isFullWidth: true,
                    onPressed: () async => widget.onSignOut?.call(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
