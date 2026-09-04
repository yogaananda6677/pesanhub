import 'package:flutter/material.dart';
import '../alerts/order_alert_controller.dart';
import '../cart/controllers/cart_controller.dart';
import '../kds/controllers/kds_controller.dart';
import '../kds/kds_view.dart';
import '../menu/controllers/menu_availability_controller.dart';
import '../menu/controllers/menu_controller.dart' as mc;
import '../menu/menu_availability_view.dart';
import '../menu/models/sample_menu_data.dart';
import '../pos/pos_view.dart';
import '../queue/controllers/queue_controller.dart';
import '../queue/models/queue_order.dart';
import '../queue/models/queue_order_item.dart';
import '../queue/queue_view.dart';
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

  const PosDestinationView({
    super.key,
    this.menuController,
    this.cartController,
    this.onNavigateToQueue,
  });

  @override
  Widget build(BuildContext context) {
    return PosView(
      menuController: menuController,
      cartController: cartController,
      onNavigateToQueue: onNavigateToQueue,
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
      final now = DateTime.now();
      _controller = QueueController(
        alertController: widget.alertController,
        initialOrders: [
          QueueOrder(
            id: 'ord-104',
            orderNumber: '#ORD-104',
            customerName: 'Pak Ahmad',
            customerPhone: '0813****1122',
            source: 'CUSTOMER_WEB',
            orderStatus: 'PENDING',
            paymentStatus: 'PAID',
            isTakeaway: true,
            takeawayNotes: 'Bungkus cepat, buru-buru',
            createdAt: now.subtract(const Duration(minutes: 20)),
            items: const [
              QueueOrderItem(
                name: 'Nasi Goreng Petai',
                quantity: 1,
                unitPrice: 28000,
                notes: 'Pedas sedang',
              ),
              QueueOrderItem(
                name: 'Teh Tarik Hangat',
                quantity: 1,
                unitPrice: 10000,
                isDrink: true,
              ),
            ],
          ),
          QueueOrder(
            id: 'ord-101',
            orderNumber: '#ORD-101',
            customerName: 'Siti Rahma',
            customerPhone: '0812****7890',
            source: 'CUSTOMER_WEB',
            orderStatus: 'PENDING',
            paymentStatus: 'UNPAID',
            isTakeaway: true,
            takeawayNotes: 'Pisah sambal & jangan pakai sendok plastik',
            createdAt: now.subtract(const Duration(minutes: 5)),
            items: const [
              QueueOrderItem(
                name: 'Nasi Goreng Gila',
                quantity: 1,
                unitPrice: 25000,
                notes: 'Pedas Level 3, Telur Matang',
              ),
              QueueOrderItem(
                name: 'Es Teh Manis',
                quantity: 1,
                unitPrice: 5000,
                notes: 'Less sugar',
                isDrink: true,
              ),
            ],
          ),
          QueueOrder(
            id: 'ord-102',
            orderNumber: '#ORD-102',
            customerName: 'Budi Santoso',
            customerPhone: '0857****3344',
            source: 'WHATSAPP',
            orderStatus: 'PREPARING',
            paymentStatus: 'PAID',
            createdAt: now.subtract(const Duration(minutes: 10)),
            items: const [
              QueueOrderItem(
                name: 'Nasi Goreng Spesial',
                quantity: 2,
                unitPrice: 30000,
                notes: 'Tidak pakai acar',
              ),
              QueueOrderItem(
                name: 'Es Jeruk Nipis',
                quantity: 2,
                unitPrice: 8000,
                isDrink: true,
              ),
            ],
          ),
          QueueOrder(
            id: 'ord-103',
            orderNumber: '#ORD-103',
            customerName: 'Meja 4 (Dine-in)',
            customerPhone: 'Kasir',
            source: 'CASHIER_MANUAL',
            orderStatus: 'READY_FOR_PICKUP',
            paymentStatus: 'PAID',
            createdAt: now.subtract(const Duration(minutes: 12)),
            items: const [
              QueueOrderItem(
                name: 'Nasi Goreng Babat',
                quantity: 1,
                unitPrice: 32000,
              ),
            ],
          ),
        ],
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
      final now = DateTime.now();
      _controller = KdsController(
        initialOrders: [
          QueueOrder(
            id: 'kds-001',
            orderNumber: 'ORD-101',
            customerName: 'Budi Santoso',
            customerPhone: '0812****7890',
            source: 'WHATSAPP',
            orderStatus: 'ACCEPTED',
            paymentStatus: 'PAID',
            isTakeaway: false,
            createdAt: now.subtract(const Duration(minutes: 6)),
            items: const [
              QueueOrderItem(
                name: 'Nasi Goreng Spesial',
                quantity: 2,
                unitPrice: 28000,
                notes: 'Pedas Level 2, Telur Ceplok',
              ),
              QueueOrderItem(
                name: 'Es Teh Manis',
                quantity: 2,
                unitPrice: 5000,
                notes: 'Gula Normal',
                isDrink: true,
              ),
            ],
          ),
          QueueOrder(
            id: 'kds-002',
            orderNumber: 'ORD-102',
            customerName: 'Siti Rahma',
            customerPhone: '0819****4321',
            source: 'CUSTOMER_WEB',
            orderStatus: 'PREPARING',
            paymentStatus: 'PAID',
            isTakeaway: true,
            takeawayNotes: 'Pisah bumbu & kuah',
            createdAt: now.subtract(const Duration(minutes: 18)),
            items: const [
              QueueOrderItem(
                name: 'Mie Goreng Seafood',
                quantity: 1,
                unitPrice: 32000,
                notes: 'Pedas Sedang',
              ),
            ],
          ),
        ],
      );
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

/// SettingsDestinationView provides outlet settings and access to the Design System Catalog.
class SettingsDestinationView extends StatelessWidget {
  const SettingsDestinationView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const PageStorageKey('settings_view_scroll'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
