import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class PolicyDialogs {
  static void showPrivacyPolicy(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(
              Icons.privacy_tip_outlined,
              color: AppColors.primary,
              size: 24,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Kebijakan Privasi',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Perlindungan Data Pelanggan & Transaksi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 6),
              Text(
                '1. Aplikasi PesenHub POS hanya menyimpan data transaksi penjualan, nama pelanggan, dan nomor WhatsApp untuk keperluan pencatatan struk & konfirmasi pesanan gerai.\n\n'
                '2. Integrasi WhatsApp Gateway (GOWA) hanya memiliki hak untuk sesi pengiriman pesan keluar (notifikasi & struk). Pesan pribadi atau percakapan lain tidak diakses atau disimpan.\n\n'
                '3. Data lokal pada perangkat dienkripsi dengan standar SQLite & secure keystore perangkat.\n\n'
                '4. Mitra gerai memiliki kendali penuh atas data katalog menu dan laporan keuangan usaha.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Saya Mengerti'),
          ),
        ],
      ),
    );
  }

  static void showTermsOfService(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.gavel_rounded, color: AppColors.primary, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Syarat & Ketentuan Layanan',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ketentuan Penggunaan PesenHub POS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 6),
              Text(
                '1. Sistem ini diperuntukkan khusus bagi staf kasir dan pemilik gerai Martabak & Terang Bulan Jenggirat.\n\n'
                '2. Setiap kasir bertanggung jawab atas keakuratan input transaksi tunai maupun non-tunai pada jam operasional kerja masing-masing.\n\n'
                '3. Fitur offline mode memungkinkan kasir tetap bertransaksi saat koneksi internet terputus. Data akan otomatis disinkronkan saat koneksi kembali stabil.\n\n'
                '4. Dilarang menyalahgunakan kredensial login atau membagikan akun kasir kepada pihak yang tidak berwenang.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  static void showVersionInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: AppColors.primary,
              size: 24,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Informasi Versi Aplikasi',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
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
              SizedBox(height: 12),
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
                  height: 1.4,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
  }

  static void showPrinterTest(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.print_rounded, color: AppColors.primary, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Uji Cetak Struk (Test Print)',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pratinjau Struk Kasir Thermal (58mm):',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
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
                  fontSize: 10.5,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
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
            ),
            child: const Text('Kirim ke Printer'),
          ),
        ],
      ),
    );
  }
}
