import 'package:flutter/material.dart';
import '../cart/controllers/cart_controller.dart';
import '../cart/widgets/cart_item_tile.dart';
import '../cart/widgets/order_review_dialog.dart';
import '../cart/widgets/order_success_dialog.dart';
import '../menu/controllers/menu_controller.dart' as mc;
import '../menu/controllers/modifier_selection_state.dart';
import '../menu/menu_catalog_view.dart';
import '../menu/models/sample_menu_data.dart';
import '../queue/models/queue_order.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_text_field.dart';

/// PosView integrates menu catalog, cart management, takeaway preferences,
/// and order submission adaptively across mobile and tablet viewports.
/// Fulfills Issue #28 Criteria #1, #4, and #5.
class PosView extends StatefulWidget {
  final mc.MenuController? menuController;
  final CartController? cartController;
  final VoidCallback? onNavigateToQueue;

  const PosView({
    super.key,
    this.menuController,
    this.cartController,
    this.onNavigateToQueue,
  });

  @override
  State<PosView> createState() => _PosViewState();
}

class _PosViewState extends State<PosView> {
  late final mc.MenuController _menuController;
  late final CartController _cartController;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _takeawayNotesController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _menuController =
        widget.menuController ??
        mc.MenuController(
          initialCategories: SampleMenuData.sampleCategories,
          initialMenus: SampleMenuData.sampleMenus,
        );
    _cartController = widget.cartController ?? CartController();

    _nameController.text = _cartController.customerName;
    _phoneController.text = _cartController.customerPhone;
    _takeawayNotesController.text = _cartController.takeawayNotes;

    _cartController.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    _cartController.removeListener(_onCartChanged);
    _nameController.dispose();
    _phoneController.dispose();
    _takeawayNotesController.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  void _handleItemConfigured(ModifierSelectionState modifierState) {
    _cartController.addItemFromModifierState(
      modifierState.menuItem,
      modifierState,
    );
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${modifierState.menuItem.name} ditambahkan ke keranjang.',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _openReview() async {
    if (_cartController.customerName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Silakan masukkan nama pelanggan terlebih dahulu.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_cartController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keranjang masih kosong. Pilih menu terlebih dahulu.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final createdOrder = await OrderReviewDialog.show(
      context: context,
      controller: _cartController,
    );

    if (createdOrder != null && mounted) {
      _showSuccess(createdOrder);
    }
  }

  void _showSuccess(QueueOrder order) {
    OrderSuccessDialog.show(
      context: context,
      order: order,
      onViewQueue: widget.onNavigateToQueue,
      onNewOrder: () {
        _nameController.clear();
        _phoneController.clear();
        _takeawayNotesController.clear();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTablet =
            constraints.maxWidth >= AppSpacing.tabletBreakpoint;

        if (isTablet) {
          return _buildTabletLayout();
        } else {
          return _buildMobileLayout();
        }
      },
    );
  }

  // TABLET: Side-by-side split screen (Left: 60% Catalog, Right: 40% Cart)
  Widget _buildTabletLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Panel: Menu Catalog
        Expanded(
          flex: 6,
          child: MenuCatalogView(
            controller: _menuController,
            onItemConfigured: _handleItemConfigured,
          ),
        ),
        const VerticalDivider(width: 1),

        // Right Panel: Live Cart & Order Details
        Expanded(flex: 4, child: _buildCartPanel(isTablet: true)),
      ],
    );
  }

  // MOBILE: Catalog with Sticky Bottom Cart Summary
  Widget _buildMobileLayout() {
    final itemCount = _cartController.totalItemCount;
    final total = _cartController.totalAmount;

    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: itemCount > 0 ? 90.0 : AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Collapsible Customer Details Card
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    0,
                  ),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Identitas Pelanggan',
                          style: AppTypography.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        AppTextField(
                          label: 'Nama Pelanggan *',
                          hintText: 'Contoh: Budi Santoso',
                          controller: _nameController,
                          onChanged: _cartController.setCustomerName,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        AppTextField(
                          label: 'Nomor WhatsApp (Opsional)',
                          hintText: '081234567890',
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          onChanged: _cartController.setCustomerPhone,
                        ),
                      ],
                    ),
                  ),
                ),

                // Menu Catalog View
                MenuCatalogView(
                  controller: _menuController,
                  onItemConfigured: _handleItemConfigured,
                ),
              ],
            ),
          ),
        ),

        // Sticky Bottom Cart Bar
        if (itemCount > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildMobileBottomBar(itemCount, total),
          ),
      ],
    );
  }

  Widget _buildMobileBottomBar(int itemCount, int total) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _showMobileCartSheet,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$itemCount Item di Keranjang',
                      style: AppTypography.bodySmall,
                    ),
                    Text(
                      'Rp $total',
                      style: AppTypography.titleLarge.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            AppButton(
              label: 'Review Pesanan',
              icon: Icons.receipt_long_rounded,
              onPressed: _openReview,
            ),
          ],
        ),
      ),
    );
  }

  void _showMobileCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: _buildCartPanel(isTablet: false),
        ),
      ),
    );
  }

  Widget _buildCartPanel({required bool isTablet}) {
    final items = _cartController.items;
    final bool isTakeaway = _cartController.isTakeaway;
    final total = _cartController.totalAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Panel Header
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Keranjang (${_cartController.totalItemCount})',
                  style: AppTypography.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (items.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded),
                  color: AppColors.error,
                  tooltip: 'Kosongkan Keranjang',
                  onPressed: _cartController.clearCart,
                ),
            ],
          ),
        ),
        // Customer Form for Tablet
        if (isTablet) ...[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  label: 'Nama Pelanggan *',
                  hintText: 'Contoh: Budi Santoso',
                  controller: _nameController,
                  onChanged: _cartController.setCustomerName,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  label: 'Nomor WhatsApp (Opsional)',
                  hintText: '081234567890',
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  onChanged: _cartController.setCustomerPhone,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],

        // Scrollable Content
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: AppEmptyState(
                      icon: Icons.shopping_cart_outlined,
                      title: 'Keranjang Masih Kosong',
                      description:
                          'Pilih menu di katalog untuk menambahkan pesanan kasir.',
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Takeaway Switch & Notes
                      AppCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Bungkus / Takeaway',
                                style: AppTypography.titleMedium,
                              ),
                              subtitle: const Text(
                                'Pesanan dibawa pulang',
                                style: AppTypography.bodySmall,
                              ),
                              value: isTakeaway,
                              activeTrackColor: AppColors.warning,
                              onChanged: _cartController.setTakeaway,
                            ),
                            if (isTakeaway) ...[
                              const SizedBox(height: AppSpacing.xs),
                              AppTextField(
                                label: 'Catatan Kemasan Bungkus',
                                hintText:
                                    'Misal: Pisah kuah, sambal dipisah...',
                                controller: _takeawayNotesController,
                                onChanged: _cartController.setTakeawayNotes,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // List of Cart Items
                      ...items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: CartItemTile(
                            item: item,
                            onUpdateQuantity: (newQty) =>
                                _cartController.updateQuantity(item.id, newQty),
                            onRemove: () => _cartController.removeItem(item.id),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
        ),
        const Divider(height: 1),

        // Panel Footer: Total & Review Button
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Total Pembayaran',
                      style: AppTypography.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Rp $total',
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Review & Proses Pesanan',
                icon: Icons.check_circle_outline_rounded,
                isFullWidth: true,
                onPressed: items.isNotEmpty ? _openReview : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
