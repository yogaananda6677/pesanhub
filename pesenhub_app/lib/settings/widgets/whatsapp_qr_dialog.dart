import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  int _selectedTab = 0; // 0: QR, 1: Pairing Code
  final TextEditingController _phoneCtrl = TextEditingController();
  bool _isRequestingCode = false;
  String? _codeErrorMessage;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    _initiatePairingQR();
    _startPolling();
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    if (widget.controller.data.isConnected && !_isSuccess) {
      setState(() {
        _isSuccess = true;
      });
      _pollingTimer?.cancel();
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
      return;
    }
    setState(() {});
  }

  void _initiatePairingQR() {
    widget.controller.requestPairing(method: 'qr');
  }

  Future<void> _requestCodePairing() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() {
        _codeErrorMessage = 'Nomor telepon WhatsApp outlet wajib diisi.';
      });
      return;
    }

    setState(() {
      _isRequestingCode = true;
      _codeErrorMessage = null;
    });

    final res = await widget.controller.requestPairing(
      method: 'code',
      phone: phone,
    );

    if (!mounted) return;
    setState(() {
      _isRequestingCode = false;
      if (res == null || res.pairCode == null || res.pairCode!.isEmpty) {
        _codeErrorMessage = widget.controller.errorMessage ??
            'Gagal mendapatkan kode pairing. Pastikan format nomor benar (contoh: 08123456789).';
      }
    });
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
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pairResult = widget.controller.currentPairResult;
    final isPairing = widget.controller.isPairing;
    final remainingSeconds = widget.controller.remainingSeconds;
    final isExpired = remainingSeconds <= 0 && pairResult != null && pairResult.method == 'qr';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9EFE7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.hub_rounded,
                      color: Color(0xFF8D321F),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Hubungkan WhatsApp (GOWA)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Pilih metode pairing resmi WhatsApp',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

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
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Nomor: ${widget.controller.data.phoneMasked}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Menutup jendela pairing...',
                        style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Dual Method Switcher Tabs
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            if (_selectedTab != 0) {
                              setState(() => _selectedTab = 0);
                              _initiatePairingQR();
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedTab == 0 ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _selectedTab == 0
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.qr_code_scanner_rounded,
                                  size: 16,
                                  color: _selectedTab == 0
                                      ? const Color(0xFF8D321F)
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Pindai QR',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _selectedTab == 0
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: _selectedTab == 0
                                        ? const Color(0xFF8D321F)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            if (_selectedTab != 1) {
                              setState(() {
                                _selectedTab = 1;
                                _codeErrorMessage = null;
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedTab == 1 ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _selectedTab == 1
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.pin_outlined,
                                  size: 16,
                                  color: _selectedTab == 1
                                      ? const Color(0xFF8D321F)
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Kode Tautan',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _selectedTab == 1
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: _selectedTab == 1
                                        ? const Color(0xFF8D321F)
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

                // TAB 0: QR CODE VIEW
                if (_selectedTab == 0) ...[
                  Center(
                    child: Container(
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (isPairing) ...[
                            const CircularProgressIndicator(
                              color: Color(0xFF8D321F),
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
                              pairResult.qrProxyUrl.isNotEmpty &&
                              pairResult.method == 'qr') ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                '${widget.controller.baseUrl}${pairResult.qrProxyUrl}',
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return const Center(
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF8D321F),
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
                                          color: Color(0xFF94A3B8),
                                        ),
                                        SizedBox(height: AppSpacing.xs),
                                        Text(
                                          'Gagal memuat QR',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64748B),
                                          ),
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
                                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Countdown timer chip
                  if (!isExpired &&
                      pairResult != null &&
                      pairResult.method == 'qr' &&
                      remainingSeconds > 0)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9EFE7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color: Color(0xFF8D321F),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Berlaku: $remainingSeconds detik',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF8D321F),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),

                  // QR Instructions
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Cara Pindai QR:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '1. Buka aplikasi WhatsApp di HP outlet\n'
                          '2. Buka Menu (⋮) atau Pengaturan > Perangkat Tertaut\n'
                          '3. Ketuk "Tautkan Perangkat", arahkan kamera ke QR di atas',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  if (isExpired) ...[
                    AppButton(
                      label: 'Perbarui Kode QR',
                      icon: Icons.refresh_rounded,
                      onPressed: _initiatePairingQR,
                    ),
                  ] else ...[
                    AppButton.outlined(
                      label: 'Tutup',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ],

                // TAB 1: PAIRING CODE VIEW
                if (_selectedTab == 1) ...[
                  // Phone Number Input
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Nomor WhatsApp Outlet',
                      hintText: 'Contoh: 08123456789 atau 62812...',
                      prefixIcon: Icon(Icons.phone_iphone_rounded, size: 20),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (_codeErrorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _codeErrorMessage!,
                              style: const TextStyle(fontSize: 11, color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Action to generate code
                  ElevatedButton.icon(
                    onPressed: _isRequestingCode ? null : _requestCodePairing,
                    icon: _isRequestingCode
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.key_rounded, size: 18),
                    label: Text(_isRequestingCode ? 'Memproses...' : 'Dapatkan Kode Tautan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8D321F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Render Pairing Code Display if generated
                  if (pairResult != null &&
                      pairResult.method == 'code' &&
                      pairResult.pairCode != null &&
                      pairResult.pairCode!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9EFE7),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF8D321F), width: 1.5),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'KODE TAUTAN WHATSAPP ANDA',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF8D321F),
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            pairResult.pairCode!,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 6,
                              color: Color(0xFF0F172A),
                              fontFamily: 'monospace',
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: pairResult.pairCode!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Kode pairing disalin ke clipboard!'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded, size: 14),
                                label: const Text('Salin Kode', style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF8D321F),
                                  side: const BorderSide(color: Color(0xFF8D321F)),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Pairing Code Instructions
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Cara Menautkan dengan Kode:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '1. Buka aplikasi WhatsApp di HP outlet\n'
                          '2. Masuk ke Menu (⋮) atau Pengaturan > Perangkat Tertaut\n'
                          '3. Ketuk "Tautkan Perangkat"\n'
                          '4. Pilih tautan di bawah: "Tautkan dengan nomor telepon saja"\n'
                          '5. Masukkan 8 karakter kode pairing yang tertera di atas',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

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
