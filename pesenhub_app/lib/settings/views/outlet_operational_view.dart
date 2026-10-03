import 'package:flutter/material.dart';
import '../../theme/app_spacing.dart';

/// Screen 4: Outlet & Operasional
class OutletOperationalView extends StatefulWidget {
  final List<Map<String, dynamic>>? availableBranches;
  final String? currentBranchId;
  final String? branchName;
  final String? branchAddress;

  const OutletOperationalView({
    super.key,
    this.availableBranches,
    this.currentBranchId,
    this.branchName,
    this.branchAddress,
  });

  @override
  State<OutletOperationalView> createState() => _OutletOperationalViewState();
}

class _OutletOperationalViewState extends State<OutletOperationalView> {
  // Configurable operational state
  bool _isOpen = true;
  String _openTime = '16:00';
  String _closeTime = '23:30';

  @override
  Widget build(BuildContext context) {
    final branches =
        widget.availableBranches ??
        [
          {
            'id': 'b-1',
            'name': 'Cabang Utama Banyuwangi',
            'address': 'Jl. Ahmad Yani No. 45, Banyuwangi',
            'phone': '+62 813-9022-4134',
            'is_main': true,
            'is_active': true,
          },
          {
            'id': 'b-2',
            'name': 'Cabang Rogojampi',
            'address': 'Jl. Raya Rogojampi No. 12, Banyuwangi',
            'phone': '+62 812-3456-7890',
            'is_main': false,
            'is_active': true,
          },
          {
            'id': 'b-3',
            'name': 'Cabang Genteng',
            'address': 'Jl. Gajah Mada No. 88, Genteng, Banyuwangi',
            'phone': '+62 819-8765-4321',
            'is_main': false,
            'is_active': true,
          },
        ];

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
          'Outlet & Operasional',
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

            // 2. Brand & General Info
            _buildSectionHeader('BRAND & INFORMASI GERAI'),
            _buildBrandCard(),
            const SizedBox(height: AppSpacing.lg),

            // 3. Jam Operasional Kasir
            _buildSectionHeader('JAM OPERASIONAL KASIR'),
            _buildOperationalHoursCard(),
            const SizedBox(height: AppSpacing.lg),

            // 4. Daftar Cabang Gerai
            _buildSectionHeader('DAFTAR CABANG GERAI (${branches.length})'),
            ...branches.map((b) => _buildBranchCard(b)),
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
              Icons.storefront_rounded,
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
                  'Profil Gerai & Operasional',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2D231E),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Atur identitas brand, jam buka kasir, dan pantau cabang aktif.',
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

  Widget _buildBrandCard() {
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
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8D321F), Color(0xFFB8482A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'J',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Martabak & Terang Bulan Jenggirat',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2D231E),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Kuliner Martabak & Terang Bulan Spesial Banyuwangi',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: Color(0xFFF4EEEA)),
          ),
          _buildInfoRow(
            icon: Icons.location_on_outlined,
            label: 'Alamat Pusat',
            value: widget.branchAddress ?? 'Jl. Ahmad Yani No. 45, Banyuwangi',
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.phone_outlined,
            label: 'Kontak CS & Gerai',
            value: '+62 813-9022-4134',
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Tahun Berdiri',
            value: '2024 (Mitra Usaha Kuliner)',
          ),
        ],
      ),
    );
  }

  Widget _buildOperationalHoursCard() {
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isOpen
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFFEBEE),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.access_time_filled_rounded,
                  color: _isOpen
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFC62828),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status Layanan Kasir',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
                    ),
                    Text(
                      _isOpen ? 'Buka Sekarang' : 'Tutup Sementara',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _isOpen
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFC62828),
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _isOpen,
                activeThumbColor: const Color(0xFF8D321F),
                onChanged: (val) {
                  setState(() => _isOpen = val);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        val
                            ? 'Status kasir: BUKA SEKARANG'
                            : 'Status kasir: TUTUP SEMENTARA',
                      ),
                      backgroundColor: val
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFC62828),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFF4EEEA)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Jam Buka - Tutup:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2D231E),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9EFE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_openTime - $_closeTime WIB',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8D321F),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Hari Operasional:',
                style: TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
              ),
              Text(
                'Setiap Hari (Senin - Minggu)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D231E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _showEditHoursDialog(),
            icon: const Icon(Icons.edit_calendar_outlined, size: 16),
            label: const Text('Ubah Jam Operasional'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8D321F),
              side: const BorderSide(color: Color(0xFFE2D3CC)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchCard(Map<String, dynamic> branch) {
    final isMain = branch['is_main'] == true;
    final name = branch['name']?.toString() ?? 'Cabang';
    final address = branch['address']?.toString() ?? '-';
    final phone = branch['phone']?.toString() ?? '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMain
              ? const Color(0xFF8D321F).withValues(alpha: 0.3)
              : const Color(0xFFF0EBE6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isMain ? const Color(0xFFF9EFE7) : const Color(0xFFF4F4F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.store_outlined,
              color: isMain ? const Color(0xFF8D321F) : const Color(0xFF71717A),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2D231E),
                        ),
                      ),
                    ),
                    if (isMain)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8D321F),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'PUSAT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'AKTIF',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7A6B63),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.phone_android,
                      size: 13,
                      color: Color(0xFF9E8E85),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      phone,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9E8E85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF8D321F)),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF7A6B63),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF2D231E),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  void _showEditHoursDialog() {
    final openCtrl = TextEditingController(text: _openTime);
    final closeCtrl = TextEditingController(text: _closeTime);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.access_time_rounded, color: Color(0xFF8D321F)),
            SizedBox(width: 10),
            Text(
              'Ubah Jam Operasional',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: openCtrl,
              decoration: const InputDecoration(
                labelText: 'Jam Buka (contoh: 16:00)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wb_sunny_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: closeCtrl,
              decoration: const InputDecoration(
                labelText: 'Jam Tutup (contoh: 23:30)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.nightlight_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Batal',
              style: TextStyle(color: Color(0xFF7A6B63)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _openTime = openCtrl.text.trim();
                _closeTime = closeCtrl.text.trim();
              });
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Jam operasional berhasil diperbarui.'),
                  backgroundColor: Color(0xFF2E7D32),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8D321F),
              foregroundColor: Colors.white,
            ),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
