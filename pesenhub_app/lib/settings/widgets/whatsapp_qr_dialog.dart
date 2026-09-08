import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../controllers/whatsapp_settings_controller.dart';

class WhatsAppQrDialog extends StatefulWidget {
  final WhatsAppSettingsController controller;

  const WhatsAppQrDialog({super.key, required this.controller});

  static Future<void> show(
    BuildContext context, {
    required WhatsAppSettingsController controller,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WhatsAppQrDialog(controller: controller),
    );
  }

  @override
  State<WhatsAppQrDialog> createState() => _WhatsAppQrDialogState();
}

class _WhatsAppQrDialogState extends State<WhatsAppQrDialog> {
  Timer? _pollingTimer;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    _initiatePairing();
    _startPolling();
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    if (widget.controller.data.isConnected && !_isSuccess) {
      setState(() {
        _isSuccess = true;
      });
      _pollingTimer?.cancel();
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
      return;
    }
    setState(() {});
  }

  void _initiatePairing() {
    widget.controller.requestPairing();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _isSuccess) return;
      await widget.controller.checkConnectionStatus();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pairResult = widget.controller.currentPairResult;
    final isPairing = widget.controller.isPairing;
    final remainingSeconds = widget.controller.remainingSeconds;
    final isExpired = remainingSeconds <= 0 && pairResult != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Hubungkan WhatsApp',
                          style: AppTypography.titleMedium,
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Pindai QR dari aplikasi WhatsApp',
                          style: AppTypography.bodySmall,
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
              const SizedBox(height: AppSpacing.lg),

              // Success State
              if (_isSuccess) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: AppColors.successBg,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.success,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Text(
                        'WhatsApp Berhasil Terhubung!',
                        style: AppTypography.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Nomor: ${widget.controller.data.phoneMasked}',
                        style: AppTypography.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // QR Display Container
                Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (isPairing) ...[
                          const CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ] else if (isExpired) ...[
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.timer_off_outlined,
                                size: 40,
                                color: AppColors.warning,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              const Text(
                                'QR Kedaluwarsa',
                                style: AppTypography.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              const Text(
                                'Ketuk tombol di bawah untuk perbarui',
                                style: AppTypography.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ] else if (pairResult != null &&
                            pairResult.qrProxyUrl.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              '${widget.controller.baseUrl}${pairResult.qrProxyUrl}',
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.broken_image_outlined,
                                        color: AppColors.textMuted,
                                      ),
                                      SizedBox(height: AppSpacing.xs),
                                      Text(
                                        'Gagal memuat QR',
                                        style: AppTypography.bodySmall,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ] else ...[
                          const Center(
                            child: Text(
                              'Meminta kode QR...',
                              style: AppTypography.bodySmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Countdown timer chip
                if (!isExpired && pairResult != null && remainingSeconds > 0)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            size: 14,
                            color: AppColors.secondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Berlaku: $remainingSeconds detik',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),

                // Instructions
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Petunjuk Pairing:',
                        style: AppTypography.titleMedium,
                      ),
                      SizedBox(height: AppSpacing.xs),
                      Text(
                        '1. Buka aplikasi WhatsApp di HP outlet\n'
                        '2. Buka Menu (⋮) atau Pengaturan > Perangkat Tertaut\n'
                        '3. Ketuk "Tautkan Perangkat", arahkan kamera ke QR ini',
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Actions
                if (isExpired) ...[
                  AppButton(
                    label: 'Perbarui Kode QR',
                    icon: Icons.refresh_rounded,
                    onPressed: _initiatePairing,
                  ),
                ] else ...[
                  AppButton.outlined(
                    label: 'Tutup',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
