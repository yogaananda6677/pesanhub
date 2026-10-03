import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

class PaymentResult {
  final bool isPaid;
  final String paymentMethod; // 'CASH' or 'QRIS'
  final int receivedAmount;
  final int changeAmount;

  const PaymentResult({
    required this.isPaid,
    required this.paymentMethod,
    required this.receivedAmount,
    required this.changeAmount,
  });
}

class PaymentDialog extends StatefulWidget {
  final int totalAmount;
  final String? orderNumber;
  final String? customerName;

  const PaymentDialog({
    super.key,
    required this.totalAmount,
    this.orderNumber,
    this.customerName,
  });

  static Future<PaymentResult?> show({
    required BuildContext context,
    required int totalAmount,
    String? orderNumber,
    String? customerName,
  }) {
    return showDialog<PaymentResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PaymentDialog(
        totalAmount: totalAmount,
        orderNumber: orderNumber,
        customerName: customerName,
      ),
    );
  }

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  // 0: Tunai, 1: Non-Tunai
  int _selectedMethodIndex = 0;
  final TextEditingController _cashInputController = TextEditingController();
  int _receivedAmount = 0;

  @override
  void initState() {
    super.initState();
    // Default to uang pas for cashier convenience
    _receivedAmount = widget.totalAmount;
    _cashInputController.text = _receivedAmount.toString();
  }

  @override
  void dispose() {
    _cashInputController.dispose();
    super.dispose();
  }

  void _selectCashPreset(int amount) {
    setState(() {
      _receivedAmount = amount;
      _cashInputController.text = amount.toString();
    });
  }

  void _onCashInputChanged(String val) {
    final clean = val.replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(clean) ?? 0;
    setState(() {
      _receivedAmount = num;
    });
  }

  String _formatRupiah(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return 'Rp ${buffer.toString()}';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.totalAmount;
    final isCash = _selectedMethodIndex == 0;
    final change = _receivedAmount - total;
    final isCashValid = _receivedAmount >= total;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pembayaran Kasir',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF2B1B16),
                          ),
                        ),
                        if (widget.orderNumber != null || widget.customerName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (widget.orderNumber != null) widget.orderNumber!,
                              if (widget.customerName != null) widget.customerName!,
                            ].join(' • '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8C7E77),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF8C7E77)),
                    tooltip: 'Batal',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Total Tagihan Banner
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFEDD5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Tagihan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9A3412),
                      ),
                    ),
                    Text(
                      _formatRupiah(total),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Method Switcher (Tunai / Non-Tunai)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedMethodIndex = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isCash ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: isCash
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.payments_rounded,
                                size: 18,
                                color: isCash
                                    ? AppColors.primary
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Tunai (Cash)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: isCash
                                      ? AppColors.primary
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedMethodIndex = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: !isCash ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: !isCash
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 18,
                                color: !isCash
                                    ? AppColors.primary
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Non-Tunai (QRIS)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: !isCash
                                      ? AppColors.primary
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Cash or Non-cash Content
              if (isCash) ...[
                // Quick Chips: Uang Pas, 20k, 50k, 100k
                const Text(
                  'Pilihan Nominal Cepat:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPresetChip('Uang Pas', total, isPas: true),
                    _buildPresetChip('Rp 20.000', 20000),
                    _buildPresetChip('Rp 50.000', 50000),
                    _buildPresetChip('Rp 100.000', 100000),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Manual Input
                TextField(
                  controller: _cashInputController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Uang Tunai Diterima',
                    prefixText: 'Rp ',
                    prefixStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2B1B16),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  onChanged: _onCashInputChanged,
                ),
                const SizedBox(height: AppSpacing.md),

                // Change / Shortage banner
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isCashValid
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCashValid
                          ? const Color(0xFFA5D6A7)
                          : const Color(0xFFFFCDD2),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isCashValid
                                ? Icons.check_circle_rounded
                                : Icons.warning_amber_rounded,
                            size: 18,
                            color: isCashValid
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFC62828),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isCashValid ? 'Uang Kembalian' : 'Uang Kurang',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isCashValid
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFC62828),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _formatRupiah(change >= 0 ? change : -change),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: isCashValid
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFC62828),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Non-Tunai / QRIS Info Box
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.qr_code_2_rounded,
                        size: 64,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Pembayaran QRIS / Transfer',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2B1B16),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Minta pelanggan scan QRIS atau transfer sejumlah ${_formatRupiah(total)} ke rekening gerai.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: (isCash && !isCashValid)
                          ? null
                          : () {
                              final result = PaymentResult(
                                isPaid: true,
                                paymentMethod: isCash ? 'CASH' : 'QRIS',
                                receivedAmount: isCash ? _receivedAmount : total,
                                changeAmount: isCash ? (change > 0 ? change : 0) : 0,
                              );
                              Navigator.of(context).pop(result);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFCBD5E1),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        isCash ? 'Konfirmasi Tunai' : 'Konfirmasi QRIS',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, int amount, {bool isPas = false}) {
    final isSelected = _receivedAmount == amount;
    return InkWell(
      onTap: () => _selectCashPreset(amount),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}
