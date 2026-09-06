import 'package:flutter/material.dart';
import '../cart/controllers/cart_controller.dart';
import '../cart/models/cart_order_draft.dart';
import '../cart/widgets/cart_item_tile.dart';
import '../cart/widgets/order_review_dialog.dart';
import '../cart/widgets/order_success_dialog.dart';
import '../connectivity/connectivity_controller.dart';
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
/// Fulfills Issue #133 Criteria.
class PosView extends StatefulWidget {
  final mc.MenuController? menuController;
  final CartController? cartController;
  final VoidCallback? onNavigateToQueue;
  final Future<QueueOrder> Function(CartOrderDraft draft)? submitOrder;
  final ConnectivityController? connectivityController;

  const PosView({
    super.key,
    this.menuController,
    this.cartController,
    this.onNavigateToQueue,
    this.submitOrder,
    this.connectivityController,
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
  final GlobalKey _catalogKey = GlobalKey();

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
    AppFeedback.show(
      context,
      message: '${modifierState.menuItem.name} ditambahkan ke keranjang.',
      type: AppBannerType.success,
      duration: const Duration(seconds: 2),
    );
  }

  void _openReview({BuildContext? sheetContext}) async {
    if (_cartController.customerName.trim().isEmpty) {
      AppFeedback.show(
        context,
        message: 'Masukkan nama pelanggan sebelum melanjutkan pembayaran.',
        type: AppBannerType.warning,
      );
      return;
    }

    if (_cartController.isEmpty) {
      AppFeedback.show(
        context,
        message: 'Keranjang masih kosong. Pilih menu terlebih dahulu.',
        type: AppBannerType.warning,
      );
      return;
    }

    if (sheetContext != null && Navigator.canPop(sheetContext)) {
      Navigator.of(sheetContext).pop();
    }

    final createdOrder = await OrderReviewDialog.show(
      context: context,
      controller: _cartController,
      submitFn: widget.submitOrder,
    );

    if (createdOrder != null && mounted) {
      _showSuccess(createdOrder);
    }
  }

  void _handleClearCart() {
    _nameController.clear();
    _phoneController.clear();
    _takeawayNotesController.clear();
    _cartController.clearCart();
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
            key: _catalogKey,
            controller: _menuController,
            onItemConfigured: _handleItemConfigured,
            connectivityController: widget.connectivityController,
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
          child: MenuCatalogView(
            key: _catalogKey,
            controller: _menuController,
            onItemConfigured: _handleItemConfigured,
            connectivityController: widget.connectivityController,
            contentPadding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              itemCount > 0 ? 96.0 : AppSpacing.lg,
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final isNarrowStacked =
                constraints.maxWidth < 360 || textScale > 1.3;

            final summaryWidget = InkWell(
              key: const Key('sticky-cart-summary'),
              onTap: _showMobileCartSheet,
              borderRadius: AppSpacing.borderRadiusSm,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$itemCount Item di Keranjang',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Rp $total',
                            style: AppTypography.titleLarge.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );

            final actionButton = AppButton(
              key: const Key('sticky-cart-review-button'),
              label: 'Review Pesanan',
              icon: Icons.receipt_long_rounded,
              isFullWidth: isNarrowStacked,
              onPressed: _showMobileCartSheet,
            );

            if (isNarrowStacked) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  summaryWidget,
                  const SizedBox(height: AppSpacing.xs),
                  actionButton,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: summaryWidget),
                const SizedBox(width: AppSpacing.sm),
                actionButton,
              ],
            );
          },
        ),
      ),
    );
  }

  void _showMobileCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
          ),
          child: ListenableBuilder(
            listenable: _cartController,
            builder: (context, _) =>
                _buildCartPanel(isTablet: false, sheetContext: ctx),
          ),
        ),
      ),
    );
  }

  Widget _buildCartPanel({required bool isTablet, BuildContext? sheetContext}) {
    final items = _cartController.items;
    final bool isTakeaway = _cartController.isTakeaway;
    final total = _cartController.totalAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Panel Header
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
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
                  key: const Key('cart-clear-button'),
                  icon: const Icon(Icons.delete_sweep_rounded),
                  color: AppColors.error,
                  tooltip: 'Kosongkan Keranjang',
                  onPressed: _handleClearCart,
                ),
              if (!isTablet && sheetContext != null)
                IconButton(
                  key: const Key('cart-close-sheet-button'),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Scrollable Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Customer Identity Form
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
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
                const SizedBox(height: AppSpacing.md),

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
                        subtitle: const Text('Pesanan dibawa pulang'),
                        value: isTakeaway,
                        activeTrackColor: AppColors.warning,
                        onChanged: _cartController.setTakeaway,
                      ),
                      if (isTakeaway) ...[
                        const SizedBox(height: AppSpacing.xs),
                        AppTextField(
                          label: 'Catatan Kemasan Bungkus',
                          hintText: 'Misal: Pisah kuah, sambal dipisah...',
                          controller: _takeawayNotesController,
                          onChanged: _cartController.setTakeawayNotes,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Cart Items List or Empty State
                const Text(
                  'Daftar Menu Pesanan',
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: AppEmptyState(
                      icon: Icons.shopping_cart_outlined,
                      title: 'Keranjang Masih Kosong',
                      description:
                          'Pilih menu di katalog untuk menambahkan pesanan kasir.',
                    ),
                  )
                else
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
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: AppSpacing.xs,
                children: [
                  const Text(
                    'Total Pembayaran',
                    style: AppTypography.titleMedium,
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
                onPressed: items.isNotEmpty
                    ? () => _openReview(sheetContext: sheetContext)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
