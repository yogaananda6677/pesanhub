import 'package:flutter/material.dart';
import '../menu/controllers/menu_controller.dart' as mc;
import '../menu/menu_catalog_view.dart';
import '../menu/models/sample_menu_data.dart';
import '../queue/controllers/queue_controller.dart';
import '../queue/models/queue_order.dart';
import '../queue/models/queue_order_item.dart';
import '../queue/queue_view.dart';
import '../showcase/design_system_showcase.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_status_badge.dart';
import '../widgets/app_text_field.dart';

/// PosDestinationView provides the cashier order creation UI.
/// Designed with scrolling to maintain full keyboard accessibility.
class PosDestinationView extends StatefulWidget {
  const PosDestinationView({super.key});

  @override
  State<PosDestinationView> createState() => _PosDestinationViewState();
}

class _PosDestinationViewState extends State<PosDestinationView> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const PageStorageKey('pos_view_scroll'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Identitas Pelanggan',
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Nama Pelanggan',
                  hintText: 'Contoh: Budi Santoso',
                  controller: _nameController,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Nomor WhatsApp',
                  hintText: '081234567890',
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  prefixIcon: const Icon(Icons.phone_outlined),
                  helperText: 'Wajib untuk notifikasi status pesanan',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pilih Menu', style: AppTypography.titleMedium),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  hintText: 'Cari nasi goreng, mie, minuman...',
                  controller: _searchController,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
                const SizedBox(height: AppSpacing.md),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Nasi Goreng Spesial (x1)',
                        style: AppTypography.bodyLarge,
                      ),
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Text('Rp 28.000', style: AppTypography.moneyPrimary),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Pedas Sedang, Telur Ceplok Matang',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                const SizedBox(height: AppSpacing.md),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Total Pembayaran',
                        style: AppTypography.titleLarge,
                      ),
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Text('Rp 28.000', style: AppTypography.moneyPrimary),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'Simpan dan Proses Pesanan',
                  icon: Icons.check_circle_outline_rounded,
                  isFullWidth: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// QueueDestinationView provides the unified order queue monitoring UI.
class QueueDestinationView extends StatefulWidget {
  final QueueController? controller;

  const QueueDestinationView({super.key, this.controller});

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
class KdsDestinationView extends StatelessWidget {
  const KdsDestinationView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const PageStorageKey('kds_view_scroll'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppBanner(
            message:
                'Mode KDS Aktif: Menampilkan tiket pesanan yang perlu dimasak.',
            type: AppBannerType.info,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    const Text(
                      'Tiket Dapur #101',
                      style: AppTypography.titleLarge,
                    ),
                    AppStatusBadge.order('PREPARING'),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  '2x Nasi Goreng Spesial',
                  style: AppTypography.headline,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Catatan: 1 Pedas Banget, 1 Tidak Pedas',
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'Tandai Siap Diambil',
                  icon: Icons.check_rounded,
                  isFullWidth: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// MenuDestinationView provides the menu catalog view.
class MenuDestinationView extends StatefulWidget {
  final mc.MenuController? controller;

  const MenuDestinationView({super.key, this.controller});

  @override
  State<MenuDestinationView> createState() => _MenuDestinationViewState();
}

class _MenuDestinationViewState extends State<MenuDestinationView> {
  late final mc.MenuController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        mc.MenuController(
          initialCategories: SampleMenuData.sampleCategories,
          initialMenus: SampleMenuData.sampleMenus,
        );
  }

  @override
  Widget build(BuildContext context) {
    return MenuCatalogView(controller: _controller);
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
