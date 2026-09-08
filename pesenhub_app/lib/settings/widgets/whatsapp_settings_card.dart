import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../controllers/whatsapp_settings_controller.dart';
import 'whatsapp_qr_dialog.dart';

class WhatsAppSettingsCard extends StatelessWidget {
  final WhatsAppSettingsController controller;

  const WhatsAppSettingsCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final data = controller.data;
        final isConnected = data.isConnected;
        final isGatewayDown = data.status == 'GATEWAY_DOWN';

        Color badgeBg;
        Color badgeFg;
        String badgeText;

        if (isConnected) {
          badgeBg = AppColors.successBg;
          badgeFg = AppColors.success;
          badgeText = 'Terhubung';
        } else if (isGatewayDown) {
          badgeBg = AppColors.errorBg;
          badgeFg = AppColors.error;
          badgeText = 'Gateway Offline';
        } else {
          badgeBg = AppColors.warningBg;
          badgeFg = AppColors.warning;
          badgeText = 'Belum Terhubung';
        }

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Status Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isConnected
                          ? AppColors.primaryContainer
                          : AppColors.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: isConnected
                          ? AppColors.primary
                          : AppColors.secondary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Integrasi WhatsApp (GOWA)',
                          style: AppTypography.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Penerimaan Pesanan Otomatis Outlet',
                          style: AppTypography.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm + 2,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: badgeFg,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Flexible(
                                child: Text(
                                  badgeText,
                                  style: AppTypography.labelSmall.copyWith(
                                    color: badgeFg,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Details Grid / Table
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Nomor WhatsApp Outlet',
                      value: isConnected
                          ? data.phoneMasked
                          : 'Belum ada akun tertaut',
                      isBold: isConnected,
                    ),
                    const Divider(
                      height: AppSpacing.md,
                      color: AppColors.border,
                    ),
                    _DetailRow(
                      label: 'Perangkat (Device ID)',
                      value: data.deviceId.isNotEmpty
                          ? data.deviceId
                          : 'pesenhub-dev',
                    ),
                    const Divider(
                      height: AppSpacing.md,
                      color: AppColors.border,
                    ),
                    _DetailRow(
                      label: 'Status Gateway Server',
                      value: data.gatewayState == 'UP'
                          ? 'Online'
                          : 'Tidak Aktif',
                      valueColor: data.gatewayState == 'UP'
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Privacy Notice Box
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.privacy_tip_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Privasi & Perlindungan Data',
                            style: AppTypography.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            data.privacyNotice.isNotEmpty
                                ? data.privacyNotice
                                : 'Nomor WhatsApp dan data pelanggan disanitasi otomatis dengan PII masking sebelum disimpan ke database.',
                            style: AppTypography.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Action Buttons
              if (isConnected) ...[
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    AppButton.outlined(
                      label: 'Perbarui Status',
                      icon: Icons.refresh_rounded,
                      onPressed: controller.isLoading
                          ? null
                          : () => controller.loadSettings(),
                    ),
                    AppButton.outlined(
                      label: 'Putuskan',
                      icon: Icons.link_off_rounded,
                      onPressed: controller.isLoading
                          ? null
                          : () => _showDisconnectConfirm(context),
                    ),
                  ],
                ),
              ] else ...[
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    AppButton(
                      label: 'Hubungkan WhatsApp',
                      icon: Icons.qr_code_scanner_rounded,
                      onPressed: () => WhatsAppQrDialog.show(
                        context,
                        controller: controller,
                      ),
                    ),
                    AppButton.outlined(
                      label: 'Cek Status',
                      icon: Icons.refresh_rounded,
                      onPressed: controller.isLoading
                          ? null
                          : () => controller.loadSettings(),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showDisconnectConfirm(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Putuskan Sambungan WhatsApp?'),
        content: const Text(
          'Bot pemesanan otomatis tidak akan dapat menerima atau membalas pesan pelanggan setelah sambungan diputus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.disconnect();
            },
            child: const Text(
              'Putuskan',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 5,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
