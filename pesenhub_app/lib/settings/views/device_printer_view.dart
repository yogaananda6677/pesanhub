import 'package:flutter/material.dart';
import '../../theme/app_spacing.dart';

/// Screen 5: Perangkat & Printer
class DevicePrinterView extends StatefulWidget {
  const DevicePrinterView({super.key});

  @override
  State<DevicePrinterView> createState() => _DevicePrinterViewState();
}

class _DevicePrinterViewState extends State<DevicePrinterView> {
  bool _autoPrint = true;
  bool _kitchenCopy = false;
  bool _autoCutter = true;
  String _paperSize = '58mm';
  bool _isTestingPrint = false;
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF8F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF2D231E),
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Perangkat & Printer',
          style: TextStyle(
            color: Color(0xFF2D231E),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFF0EBE6)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Hero banner
            _buildHeroBanner(),
            const SizedBox(height: AppSpacing.lg),

            // 2. Printer Utama
            _buildSectionHeader('PRINTER STRUK UTAMA'),
            _buildMainPrinterCard(),
            const SizedBox(height: AppSpacing.lg),

            // 3. Pengaturan Struk & Hardware
            _buildSectionHeader('PENGATURAN STRUK & CETAK'),
            _buildPrintingConfigCard(),
            const SizedBox(height: AppSpacing.lg),

            // 4. Daftar Perangkat Bluetooth
            _buildSectionHeader('DAFTAR PERANGKAT BLUETOOTH'),
            _buildBluetoothDevicesCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF64748B),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9EFE7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0DCD3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF8D321F),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.print_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Konfigurasi Printer Thermal',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2D231E),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Hubungkan printer struk Bluetooth dan lakukan pengujian cetak nota.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7A6B63),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainPrinterCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0EBE6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Color(0xFF2E7D32),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Xprinter XP-58II',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2D231E),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bluetooth_connected,
                                size: 12,
                                color: Color(0xFF2E7D32),
                              ),
                              SizedBox(width: 3),
                              Text(
                                'TERHUBUNG',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Bluetooth Thermal POS • 58mm Paper',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFF4EEEA)),
          ),
          _buildInfoRow('Alamat MAC', '66:32:B1:8A:2C:90'),
          const SizedBox(height: 6),
          _buildInfoRow('Kecepatan Cetak', '90 mm/detik'),
          const SizedBox(height: 6),
          _buildInfoRow('Ukuran Kertas', '$_paperSize Thermal Roll'),
          const SizedBox(height: 14),

          // UJI CETAK STRUK BUTTON
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isTestingPrint ? null : _runTestPrint,
              icon: _isTestingPrint
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.print_outlined, size: 18),
              label: Text(
                _isTestingPrint
                    ? 'Sedang Mencetak...'
                    : 'Uji Cetak Struk (Test Print)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8D321F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrintingConfigCard() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF0EBE6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            SwitchListTile.adaptive(
              value: _autoPrint,
              activeThumbColor: const Color(0xFF8D321F),
              title: const Text(
                'Cetak Otomatis Pesanan Selesai',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D231E),
                ),
              ),
              subtitle: const Text(
                'Cetak struk secara otomatis begitu pesanan berhasil disimpan.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
              ),
              onChanged: (val) => setState(() => _autoPrint = val),
            ),
            const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: Color(0xFFF4EEEA),
            ),
            SwitchListTile.adaptive(
              value: _kitchenCopy,
              activeThumbColor: const Color(0xFF8D321F),
              title: const Text(
                'Cetak Salinan Dapur (Kitchen Copy)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D231E),
                ),
              ),
              subtitle: const Text(
                'Mencetak 2 struk (1 struk pelanggan + 1 tiket untuk dapur).',
                style: TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
              ),
              onChanged: (val) => setState(() => _kitchenCopy = val),
            ),
            const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: Color(0xFFF4EEEA),
            ),
            SwitchListTile.adaptive(
              value: _autoCutter,
              activeThumbColor: const Color(0xFF8D321F),
              title: const Text(
                'Potong Kertas Otomatis',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D231E),
                ),
              ),
              subtitle: const Text(
                'Kirim sinyal pemotong kertas setelah selesai mencetak.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
              ),
              onChanged: (val) => setState(() => _autoCutter = val),
            ),
            const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: Color(0xFFF4EEEA),
            ),
            ListTile(
              title: const Text(
                'Ukuran Kertas Thermal',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D231E),
                ),
              ),
              subtitle: Text(
                'Format saat ini: $_paperSize',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
              ),
              trailing: DropdownButton<String>(
                value: _paperSize,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(
                    value: '58mm',
                    child: Text('58mm (Standar POS)'),
                  ),
                  DropdownMenuItem(value: '80mm', child: Text('80mm (Lebar)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _paperSize = val);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBluetoothDevicesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0EBE6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildDeviceItem(
            name: 'Xprinter XP-58II',
            mac: '66:32:B1:8A:2C:90',
            isConnected: true,
          ),
          const Divider(height: 16, color: Color(0xFFF4EEEA)),
          _buildDeviceItem(
            name: 'RPP02N Mobile POS',
            mac: '88:44:A2:11:5F:C1',
            isConnected: false,
          ),
          const Divider(height: 16, color: Color(0xFFF4EEEA)),
          _buildDeviceItem(
            name: 'MP-58 Thermal Printer',
            mac: '00:1B:35:89:FE:44',
            isConnected: false,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _isScanning ? null : _scanBluetooth,
            icon: _isScanning
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 16),
            label: Text(
              _isScanning
                  ? 'Sedang Memindai...'
                  : 'Pindai Perangkat Bluetooth Baru',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8D321F),
              side: const BorderSide(color: Color(0xFFE2D3CC)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem({
    required String name,
    required String mac,
    required bool isConnected,
  }) {
    return Row(
      children: [
        Icon(
          Icons.print_outlined,
          color: isConnected
              ? const Color(0xFF2E7D32)
              : const Color(0xFF71717A),
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D231E),
                ),
              ),
              Text(
                mac,
                style: const TextStyle(fontSize: 11, color: Color(0xFF9E8E85)),
              ),
            ],
          ),
        ),
        if (isConnected)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'TERHUBUNG',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2E7D32),
              ),
            ),
          )
        else
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Menghubungkan ke $name...'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: const Text(
              'Hubungkan',
              style: TextStyle(fontSize: 12, color: Color(0xFF8D321F)),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2D231E),
          ),
        ),
      ],
    );
  }

  Future<void> _runTestPrint() async {
    setState(() => _isTestingPrint = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _isTestingPrint = false);

    // Show simulated receipt dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF2E7D32),
              size: 24,
            ),
            SizedBox(width: 8),
            Text(
              'Uji Cetak Berhasil',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9FB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '================================\n'
                '   MARTABAK & TERANG BULAN\n'
                '          JENGGIRAT\n'
                '================================\n'
                'Waktu : 03/10/2026 18:45 WIB\n'
                'Kasir : Yoga Ananda (Superadmin)\n'
                '--------------------------------\n'
                'UJI CETAK THERMAL 58mm\n'
                'STATUS PRINTER : OK / ONLINE\n'
                'KONEKSI BLUETOOTH : STABIL\n'
                '--------------------------------\n'
                'Terima Kasih!\n'
                '================================',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF1E293B),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8D321F),
              foregroundColor: Colors.white,
            ),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanBluetooth() async {
    setState(() => _isScanning = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _isScanning = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pemindaian selesai. Semua perangkat telah diperbarui.'),
        backgroundColor: Color(0xFF2E7D32),
      ),
    );
  }
}
