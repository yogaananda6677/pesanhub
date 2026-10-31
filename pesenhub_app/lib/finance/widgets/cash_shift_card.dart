import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/cash_shift.dart';

class CashShiftCard extends StatelessWidget {
  final CashShift? activeShift;
  final VoidCallback onOpenShift;
  final VoidCallback onCloseShift;

  const CashShiftCard({
    super.key,
    required this.activeShift,
    required this.onOpenShift,
    required this.onCloseShift,
  });

  @override
  Widget build(BuildContext context) {
    final isOpen = activeShift != null && activeShift!.isOpen;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOpen ? AppColors.emerald : AppColors.cardBorderModern,
          width: isOpen ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isOpen
                ? AppColors.emerald.withValues(alpha: 0.08)
                : AppColors.obsidianDark.withValues(alpha: 0.025),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isOpen ? AppColors.emeraldBg : AppColors.slateBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isOpen
                              ? AppColors.emeraldBorder
                              : AppColors.cardBorderModern,
                        ),
                      ),
                      child: Icon(
                        isOpen
                            ? Icons.lock_open_rounded
                            : Icons.lock_outline_rounded,
                        size: 18,
                        color: isOpen
                            ? AppColors.emerald
                            : AppColors.neutralTextMuted,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Kas Laci Kasir (Cash Register)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: AppColors.obsidianDark,
                            ),
                          ),
                          Text(
                            isOpen
                                ? 'Bertugas: ${activeShift!.cashierName}'
                                : 'Belum ada shift kasir yang aktif',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.neutralTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isOpen ? AppColors.emeraldBg : AppColors.slateBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isOpen
                        ? AppColors.emeraldBorder
                        : AppColors.cardBorderModern,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isOpen
                            ? AppColors.emerald
                            : AppColors.neutralTextMuted,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                (isOpen
                                        ? AppColors.emerald
                                        : AppColors.neutralTextMuted)
                                    .withValues(alpha: 0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isOpen ? 'AKTIF' : 'TUTUP',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isOpen
                            ? AppColors.emerald
                            : AppColors.neutralTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (isOpen) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.slateBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorderModern),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Modal Awal',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.neutralTextMuted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            activeShift!.formattedStartingCash,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.obsidianDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tunai Masuk',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.neutralTextMuted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            activeShift!.formattedCashIn,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.emerald,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Estimasi di Laci',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.neutralTextMuted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            activeShift!.formattedExpectedCash,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: AppColors.obsidianDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                key: const Key('close-shift-button'),
                onPressed: onCloseShift,
                icon: const Icon(Icons.lock_rounded, size: 18),
                label: const Text('Tutup Kasir & Rekonsiliasi Kas'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.obsidianDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ] else ...[
            const Text(
              'Mulai shift kasir untuk mencatat uang modal awal laci dan melacak penerimaan uang fisik secara realtime.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                key: const Key('open-shift-button'),
                onPressed: onOpenShift,
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: const Text('Buka Shift Kasir Baru'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
