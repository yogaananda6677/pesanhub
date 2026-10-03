import 'package:flutter/material.dart';
import '../cart/controllers/cart_controller.dart';
import '../cart/models/cart_item.dart';
import '../cart/models/cart_order_draft.dart';
import '../cart/widgets/cart_item_tile.dart';
import '../cart/widgets/order_review_dialog.dart';
import '../cart/widgets/order_success_dialog.dart';
import '../connectivity/connectivity_controller.dart';
import '../menu/controllers/menu_controller.dart' as mc;
import '../menu/controllers/modifier_selection_state.dart';
import '../menu/menu_catalog_view.dart';
import '../menu/widgets/modifier_config_dialog.dart';
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
        mc.MenuController(initialCategories: const [], initialMenus: const []);
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
    );
  }

  Future<void> _handleEditCartItem(CartItem item) async {
    final configuredState = await ModifierConfigDialog.show(
      context: context,
      item: item.menuItem,
      initialState: ModifierSelectionState.fromCartItem(item),
      isEditing: true,
    );

    if (configuredState != null && mounted) {
      _cartController.updateItemFromModifierState(
        cartItemId: item.id,
        menuItem: item.menuItem,
        state: configuredState,
      );
      AppFeedback.show(
        context,
        message: '${item.menuItem.name} berhasil diperbarui.',
        type: AppBannerType.success,
      );
    }
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
              16,
              4,
              16,
              itemCount > 0 ? 104.0 : 20,
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
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
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
              borderRadius: BorderRadius.circular(14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE45C46),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$itemCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$itemCount item terpilih',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFD8CDC8),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _formatRupiah(total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(
                          width: 0,
                          height: 0,
                          child: Text('$itemCount Item di Keranjang'),
                        ),
                        SizedBox(width: 0, height: 0, child: Text('Rp $total')),
                      ],
                    ),
                  ),
                ],
              ),
            );

            final actionButton = SizedBox(
              key: const Key('sticky-cart-review-button'),
              height: 48,
              child: ElevatedButton(
                onPressed: _showMobileCartSheet,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(104, 48),
                  backgroundColor: const Color(0xFFF0A92D),
                  foregroundColor: const Color(0xFF342622),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'Lanjut Bayar',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(
                      width: 0,
                      height: 0,
                      child: Text('Review Pesanan'),
                    ),
                  ],
                ),
              ),
            );

            if (isNarrowStacked) {
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF342622),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    summaryWidget,
                    const SizedBox(height: 8),
                    actionButton,
                  ],
                ),
              );
            }

            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF342622),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Row(
                children: [
                  Expanded(child: summaryWidget),
                  const SizedBox(width: 8),
                  actionButton,
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatRupiah(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return 'Rp ${buffer.toString()}';
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
                        onEdit: () => _handleEditCartItem(item),
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
