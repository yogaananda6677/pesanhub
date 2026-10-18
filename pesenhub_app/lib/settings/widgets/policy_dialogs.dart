import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

class PolicyDialogs {
  /// Shows modal bottom sheet on mobile (sliding up from bottom, leaving top clear)
  /// and centered dialog on tablet/desktop.
  static Future<T?> _showResponsiveModal<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
  }) {
    final isTablet =
        MediaQuery.sizeOf(context).width >= AppSpacing.tabletBreakpoint;

    if (isTablet) {
      return showDialog<T>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
            child: Material(
              color: Colors.white,
              child: builder(ctx),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.82,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: builder(ctx),
      ),
    );
  }

  static void showPrivacyPolicy(BuildContext context) {
    _showResponsiveModal(
      context: context,
      builder: (ctx) => _PolicySheetContainer(
        icon: Icons.privacy_tip_outlined,
        title: 'Kebijakan Privasi',
        content: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Perlindungan Data Pelanggan & Transaksi',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            SizedBox(height: 8),
            Text(
              '1. Aplikasi PesenHub POS hanya menyimpan data transaksi penjualan, nama pelanggan, dan nomor WhatsApp untuk keperluan pencatatan struk & konfirmasi pesanan gerai.\n\n'
              '2. Integrasi WhatsApp Gateway (GOWA) hanya memiliki hak untuk sesi pengiriman pesan keluar (notifikasi & struk). Pesan pribadi atau percakapan lain tidak diakses atau disimpan.\n\n'
              '3. Data lokal pada perangkat dienkripsi dengan standar SQLite & secure keystore perangkat.\n\n'
              '4. Mitra gerai memiliki kendali penuh atas data katalog menu dan laporan keuangan usaha.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF475569),
              ),
            ),
          ],
        ),
        actionButton: ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Saya Mengerti'),
        ),
      ),
    );
  }

  static void showTermsOfService(BuildContext context) {
    _showResponsiveModal(
      context: context,
      builder: (ctx) => _PolicySheetContainer(
        icon: Icons.gavel_rounded,
        title: 'Syarat & Ketentuan Layanan',
        content: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ketentuan Penggunaan PesenHub POS',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            SizedBox(height: 8),
            Text(
              '1. Sistem ini diperuntukkan khusus bagi staf kasir dan pemilik gerai Martabak & Terang Bulan Jenggirat.\n\n'
              '2. Setiap kasir bertanggung jawab atas keakuratan input transaksi tunai maupun non-tunai pada jam operasional kerja masing-masing.\n\n'
              '3. Fitur offline mode memungkinkan kasir tetap bertransaksi saat koneksi internet terputus. Data akan otomatis disinkronkan saat koneksi kembali stabil.\n\n'
              '4. Dilarang menyalahgunakan kredensial login atau membagikan akun kasir kepada pihak yang tidak berwenang.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF475569),
              ),
            ),
          ],
        ),
        actionButton: ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Tutup'),
        ),
      ),
    );
  }

  static void showVersionInfo(BuildContext context) {
    _showResponsiveModal(
      context: context,
      builder: (ctx) => _PolicySheetContainer(
        icon: Icons.info_outline_rounded,
        title: 'Informasi Versi Aplikasi',
        content: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'PesenHub POS — Edisi Mitra Jenggirat',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            SizedBox(height: 4),
            Text(
              'Versi 1.0.0 (Build 2026.10)\nKanal: Production Stable',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            SizedBox(height: 14),
            Text(
              'Catatan Pembaruan Rilis:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            SizedBox(height: 6),
            Text(
              '• Perombakan Dashboard & Menu Operasional terstruktur.\n'
              '• Pusat Notifikasi & Alert pop-up interaktif.\n'
              '• Pengaturan Kasir POS terstandar Warung Kasir.\n'
              '• Integrasi WhatsApp Gateway & Cetak Struk Bluetooth.\n'
              '• Sinkronisasi offline outbox otomatis.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: Color(0xFF475569),
              ),
            ),
          ],
        ),
        actionButton: ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Selesai'),
        ),
      ),
    );
  }

  static void showPrinterTest(BuildContext context) {
    _showResponsiveModal(
      context: context,
      builder: (ctx) => _PolicySheetContainer(
        icon: Icons.print_rounded,
        title: 'Uji Cetak Struk (Test Print)',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pratinjau Struk Kasir Thermal (58mm):',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                '================================\n'
                '  MARTABAK & TERANG BULAN JENGGIRAT  \n'
                '          Struk Pembayaran       \n'
                '================================\n'
                '1x Terang Bulan Coklat Keju  Rp 32.000\n'
                '1x Martabak Telur Daging Sapi Rp 38.000\n'
                '--------------------------------\n'
                'Total:                     Rp 70.000\n'
                'Bayar (QRIS):              Rp 70.000\n'
                'Kembali:                        Rp 0\n'
                '================================\n'
                '     Terima kasih atas pesanan!    \n'
                '================================\n',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.3,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Perintah cetak struk berhasil dikirim ke printer thermal.',
                  ),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Kirim ke Printer'),
          ),
        ],
      ),
    );
  }
}

class _PolicySheetContainer extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget content;
  final Widget? actionButton;
  final List<Widget>? actions;

  const _PolicySheetContainer({
    required this.icon,
    required this.title,
    required this.content,
    this.actionButton,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Drag Handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 22,
                  color: Color(0xFF64748B),
                ),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 20,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        // Body (Scrollable, with room above)
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: content,
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        // Footer Actions
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: actions != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions!,
                )
              : (actionButton ??
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Tutup'),
                  )),
        ),
      ],
    );
  }
}
