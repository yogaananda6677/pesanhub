import 'package:flutter/material.dart';
import '../../cart/controllers/cart_controller.dart';
import '../../data/remote/pesenhub_api_client.dart';
import '../../theme/app_colors.dart';
import '../models/discount.dart';

/// Reusable Bottom Sheet for Selecting & Applying Promo/Discount in POS and Order Review.
class PromoSelectorSheet extends StatefulWidget {
  final PesenHubApiClient? apiClient;
  final CartController cartController;
  final ValueChanged<Discount>? onApplied;

  const PromoSelectorSheet({
    super.key,
    this.apiClient,
    required this.cartController,
    this.onApplied,
  });

  static Future<Discount?> show({
    required BuildContext context,
    required CartController cartController,
    PesenHubApiClient? apiClient,
    ValueChanged<Discount>? onApplied,
  }) {
    return showModalBottomSheet<Discount>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PromoSelectorSheet(
        cartController: cartController,
        apiClient: apiClient,
        onApplied: onApplied,
      ),
    );
  }

  @override
  State<PromoSelectorSheet> createState() => _PromoSelectorSheetState();
}

class _PromoSelectorSheetState extends State<PromoSelectorSheet> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  List<Discount> _promos = [];
  String? _errorMsg;

  static final List<Discount> _fallbackPromos = [
    const Discount(
      id: 'disc-fall-1',
      name: 'Promo GoFood Martabak 20%',
      code: 'GFMARTABAK20',
      scope: 'ITEM',
      channel: 'GOFOOD',
      type: 'PERCENTAGE',
      value: 20,
      maxDiscountAmount: 15000,
      minOrderAmount: 40000,
      isActive: true,
    ),
    const Discount(
      id: 'disc-fall-2',
      name: 'Diskon Min Belanja 50 Ribu',
      code: 'DISKON50K',
      scope: 'ORDER',
      channel: 'ALL',
      type: 'FIXED',
      value: 10000,
      minOrderAmount: 50000,
      isActive: true,
    ),
    const Discount(
      id: 'disc-fall-3',
      name: 'Promo GrabFood Spesial 15%',
      code: 'GRABSPESIAL15',
      scope: 'ORDER',
      channel: 'GRABFOOD',
      type: 'PERCENTAGE',
      value: 15,
      maxDiscountAmount: 20000,
      minOrderAmount: 60000,
      isActive: true,
    ),
    const Discount(
      id: 'disc-fall-4',
      name: 'Diskon Kasir Offline 5 Ribu',
      code: 'OFFLINE5K',
      scope: 'ORDER',
      channel: 'OFFLINE',
      type: 'FIXED',
      value: 5000,
      minOrderAmount: 30000,
      isActive: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadApplicablePromos();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String _formatChannelLabel(String channel) {
    return switch (channel.toUpperCase()) {
      'CASHIER_MANUAL' || 'OFFLINE' => 'Kasir Offline',
      'WHATSAPP' => 'WhatsApp Order',
      'GOFOOD' => 'GoFood',
      'GRABFOOD' => 'GrabFood',
      'SHOPEEFOOD' => 'ShopeeFood',
      _ => channel,
    };
  }

  Future<void> _loadApplicablePromos() async {
    setState(() => _isLoading = true);
    final orderSource = widget.cartController.orderSource;

    try {
      if (widget.apiClient != null) {
        final list = await widget.apiClient!.fetchDiscounts(activeOnly: true);
        final filtered = list
            .where((d) => d.matchesChannel(orderSource) && d.isActive)
            .toList();
        if (mounted) {
          setState(() {
            _promos = filtered;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _promos = _filterFallback(orderSource);
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _promos = widget.apiClient == null
              ? _filterFallback(orderSource)
              : [];
          _isLoading = false;
        });
      }
    }
  }

  List<Discount> _filterFallback(String orderSource) {
    return _fallbackPromos
        .where((d) => d.matchesChannel(orderSource) && d.isActive)
        .toList();
  }

  void _applyManualCode() {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    final found = _promos.where((d) => d.code?.toUpperCase() == code).toList();
    if (found.isNotEmpty) {
      final promo = found.first;
      final subtotal = widget.cartController.subtotalAmount;
      if (subtotal < promo.minOrderAmount) {
        setState(() {
          _errorMsg =
              'Minimal belanja belum terpenuhi (Kurang ${_formatRupiah(promo.minOrderAmount - subtotal)})';
        });
        return;
      }
      widget.cartController.applyDiscount(promo);
      widget.onApplied?.call(promo);
      Navigator.of(context).pop(promo);
    } else {
      setState(() {
        _errorMsg =
            'Kode promo "$code" tidak ditemukan atau tidak berlaku di saluran ini.';
      });
    }
  }

  String _formatRupiah(int amount) {
    final str = amount.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i != 0) {
        buffer.write('.');
      }
    }
    return 'Rp ${buffer.toString().split('').reversed.join('')}';
  }

  @override
  Widget build(BuildContext context) {
    final currentDiscount = widget.cartController.appliedDiscount;
    final channelName = _formatChannelLabel(widget.cartController.orderSource);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Sheet
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.local_offer_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pilih Promo / Diskon',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Berlaku untuk $channelName',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Code Input
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('promo-manual-code-input'),
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Punya kode promo? Masukkan di sini',
                      hintStyle: const TextStyle(fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  key: const Key('promo-apply-manual-code-button'),
                  onPressed: _applyManualCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                  child: const Text(
                    'Terapkan',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          if (_errorMsg != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFC62828),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMsg!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFC62828),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (currentDiscount != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF16A34A),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Promo aktif: ${currentDiscount.name}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF166534),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        widget.cartController.removeDiscount();
                        Navigator.of(context).pop();
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(50, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Hapus',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Promo list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _promos.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.discount_outlined,
                          size: 48,
                          color: Color(0xFFCBD5E1),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tidak ada promo aktif untuk $channelName',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: _promos.length,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final promo = _promos[i];
                      final isSelected = currentDiscount?.id == promo.id;
                      final subtotal = widget.cartController.subtotalAmount;
                      final isEligible = subtotal >= promo.minOrderAmount;
                      final isPercent = promo.type == 'PERCENTAGE';
                      final valueStr = isPercent
                          ? '${promo.value}%'
                          : _formatRupiah(promo.value);

                      return Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFFF7ED)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : const Color(0xFFE2E8F0),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary.withValues(alpha: 0.1)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  promo.type == 'PERCENTAGE'
                                      ? Icons.percent_rounded
                                      : Icons.attach_money_rounded,
                                  color: isSelected
                                      ? AppColors.primary
                                      : const Color(0xFF64748B),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      promo.name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isPercent
                                          ? 'Diskon $valueStr${promo.maxDiscountAmount != null ? " (Maks ${_formatRupiah(promo.maxDiscountAmount!)})" : ""}'
                                          : 'Potongan $valueStr',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isEligible
                                            ? const Color(0xFF2E7D32)
                                            : const Color(0xFF94A3B8),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (promo.code != null) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFCBD5E1),
                                          ),
                                        ),
                                        child: Text(
                                          promo.code!,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (promo.minOrderAmount > 0) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Min. belanja ${_formatRupiah(promo.minOrderAmount)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isEligible
                                              ? const Color(0xFF64748B)
                                              : const Color(0xFFDC2626),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                key: Key('promo-apply-${promo.id}'),
                                onPressed: !isEligible
                                    ? null
                                    : () {
                                        if (isSelected) {
                                          widget.cartController
                                              .removeDiscount();
                                        } else {
                                          widget.cartController.applyDiscount(
                                            promo,
                                          );
                                          widget.onApplied?.call(promo);
                                        }
                                        Navigator.of(context).pop(promo);
                                      },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isSelected
                                      ? AppColors.primary
                                      : Colors.white,
                                  foregroundColor: isSelected
                                      ? Colors.white
                                      : AppColors.primary,
                                  side: BorderSide(
                                    color: isEligible
                                        ? AppColors.primary
                                        : const Color(0xFFCBD5E1),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  isSelected
                                      ? 'Dipakai'
                                      : isEligible
                                      ? 'Gunakan'
                                      : 'Min Belanja',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : isEligible
                                        ? AppColors.primary
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
