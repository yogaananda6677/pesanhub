import 'package:flutter/material.dart';
import '../../theme/app_spacing.dart';
import '../widgets/policy_dialogs.dart';

/// Screen 2: Informasi & Kebijakan
class AppPolicyView extends StatelessWidget {
  const AppPolicyView({super.key});

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
          'Informasi & Kebijakan',
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

            // 2. Tentang Aplikasi
            _buildSectionHeader('TENTANG APLIKASI'),
            _buildAppAboutCard(),
            const SizedBox(height: AppSpacing.lg),

            // 3. Dokumen & Kebijakan
            _buildSectionHeader('DOKUMEN HUKUM & KEBIJAKAN'),
            _buildPolicyListCard(context),
            const SizedBox(height: AppSpacing.lg),

            // 4. Bantuan & Dukungan Teknis
            _buildSectionHeader('DUKUNGAN & BANTUAN TEKNIS'),
            _buildSupportCard(context),
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
              Icons.shield_outlined,
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
                  'Informasi Resmi & Kebijakan',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2D231E),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Informasi resmi, syarat & ketentuan, serta kebijakan privasi penggunaan sistem kasir PesenHub.',
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

  Widget _buildAppAboutCard() {
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
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8D321F), Color(0xFFB8482A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PesenHub POS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2D231E),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Versi 1.0.0 (Build 163) • Produksi',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8D321F),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'TERDAFTAR',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFF4EEEA)),
          ),
          const Text(
            'Sistem kasir cerdas dan pengelolaan antrean pesanan multi-cabang terintegrasi WhatsApp Gateway untuk mitra usaha kuliner Jenggirat Group.',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Color(0xFF7A6B63),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyListCard(BuildContext context) {
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
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9EFE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.privacy_tip_outlined,
                  color: Color(0xFF8D321F),
                  size: 20,
                ),
              ),
              title: const Text(
                'Kebijakan Privasi',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D231E),
                ),
              ),
              subtitle: const Text(
                'Perlindungan data pelanggan & enkripsi transaksi.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9E8E85),
              ),
              onTap: () => PolicyDialogs.showPrivacyPolicy(context),
            ),
            const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: Color(0xFFF4EEEA),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9EFE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: Color(0xFF8D321F),
                  size: 20,
                ),
              ),
              title: const Text(
                'Syarat & Ketentuan Layanan',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D231E),
                ),
              ),
              subtitle: const Text(
                'Aturan operasional POS, printer, dan lisensi cabang.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9E8E85),
              ),
              onTap: () => PolicyDialogs.showTermsOfService(context),
            ),
            const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: Color(0xFFF4EEEA),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9EFE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.new_releases_outlined,
                  color: Color(0xFF8D321F),
                  size: 20,
                ),
              ),
              title: const Text(
                'Catatan Rilis & Pembaruan',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D231E),
                ),
              ),
              subtitle: const Text(
                'Fitur baru v1.0.0: Manajemen karyawan, reset nomor harian.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9E8E85),
              ),
              onTap: () => PolicyDialogs.showVersionInfo(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportCard(BuildContext context) {
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
                  color: const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: Color(0xFF00796B),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pusat Bantuan & Layanan CS',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D231E),
                      ),
                    ),
                    Text(
                      'Senin - Minggu: 08:00 - 22:00 WIB',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Menghubungkan ke layanan bantuan teknis PesenHub...',
                  ),
                  backgroundColor: Color(0xFF8D321F),
                ),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
            label: const Text('Chat Layanan Pelanggan (WhatsApp CS)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8D321F),
              side: const BorderSide(color: Color(0xFFE2D3CC)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }
}
