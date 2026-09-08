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
import '../menu/models/sample_menu_data.dart';
import '../pos/pos_view.dart';
import '../queue/controllers/queue_controller.dart';
import '../queue/models/queue_order.dart';
import '../queue/queue_view.dart';
import '../settings/controllers/whatsapp_settings_controller.dart';
import '../settings/widgets/whatsapp_settings_card.dart';
import '../showcase/design_system_showcase.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';

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
          initialCategories: SampleMenuData.sampleCategories,
          initialMenus: SampleMenuData.sampleMenus,
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

  const SettingsDestinationView({
    super.key,
    this.onSignOut,
    this.whatsAppController,
  });

  @override
  State<SettingsDestinationView> createState() =>
      _SettingsDestinationViewState();
}

class _SettingsDestinationViewState extends State<SettingsDestinationView> {
  late final WhatsAppSettingsController _whatsAppController;
  bool _ownsController = false;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const PageStorageKey('settings_view_scroll'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WhatsAppSettingsCard(controller: _whatsAppController),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Informasi Outlet',
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'PesenHub Outlet #01 — Nasi Goreng Pusat',
                  style: AppTypography.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Versi Aplikasi: 1.0.0 (Phase 1B)',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppButton.outlined(
                  label: 'Buka Katalog Design System',
                  icon: Icons.palette_outlined,
                  isFullWidth: true,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DesignSystemShowcase(),
                      ),
                    );
                  },
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
