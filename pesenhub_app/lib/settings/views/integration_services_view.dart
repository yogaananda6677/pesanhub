import 'package:flutter/material.dart';
import '../../theme/app_spacing.dart';
import '../controllers/whatsapp_settings_controller.dart';
import '../widgets/whatsapp_settings_card.dart';

/// Screen 6: Integrasi & Layanan
class IntegrationServicesView extends StatefulWidget {
  final WhatsAppSettingsController? whatsAppController;

  const IntegrationServicesView({super.key, this.whatsAppController});

  @override
  State<IntegrationServicesView> createState() =>
      _IntegrationServicesViewState();
}

class _IntegrationServicesViewState extends State<IntegrationServicesView> {
  late final WhatsAppSettingsController _controller;
  bool _ownsController = false;
  bool _gdriveBackup = true;
  bool _soundAlert = true;
  bool _webhookActive = true;

  @override
  void initState() {
    super.initState();
    if (widget.whatsAppController != null) {
      _controller = widget.whatsAppController!;
    } else {
      _controller = WhatsAppSettingsController();
      _ownsController = true;
    }
    _controller.loadSettings();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

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
          'Integrasi & Layanan',
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

            // 2. Integrasi Utama WhatsApp
            _buildSectionHeader('INTEGRASI UTAMA: WHATSAPP GATEWAY (GOWA)'),
            WhatsAppSettingsCard(controller: _controller),
            const SizedBox(height: AppSpacing.lg),

            // 3. Layanan Cloud & Backup
            _buildSectionHeader('LAYANAN BACKUP & CLOUD'),
            _buildCloudServicesCard(),
            const SizedBox(height: AppSpacing.lg),

            // 4. API & Webhook
            _buildSectionHeader('API & WEBHOOK EKSTERNAL'),
            _buildWebhookCard(),
            const SizedBox(height: AppSpacing.lg),

            // 5. Suara & Alert Kasir
            _buildSectionHeader('NOTIFIKASI SUARA KASIR'),
            _buildAudioAlertCard(),
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
              color: const Color(0xFF128C7E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.hub_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Integrasi Layanan & Saluran',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2D231E),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Sinkronisasi notifikasi pelanggan otomatis dan integrasi gateway pihak ketiga.',
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

  Widget _buildCloudServicesCard() {
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
              value: _gdriveBackup,
              activeThumbColor: const Color(0xFF8D321F),
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.add_to_drive_rounded,
                  color: Color(0xFF1976D2),
                  size: 20,
                ),
              ),
              title: const Text(
                'Backup Google Drive Harian',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D231E),
                ),
              ),
              subtitle: const Text(
                'Mencadangkan database transaksi lokal ke Drive saat tutup buku kasir.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
              ),
              onChanged: (val) => setState(() => _gdriveBackup = val),
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
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.cloud_done_rounded,
                  color: Color(0xFF2E7D32),
                  size: 20,
                ),
              ),
              title: const Text(
                'Sinkronisasi Real-Time PesenHub Cloud',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D231E),
                ),
              ),
              subtitle: const Text(
                'Status: Aktif & Terhubung ke Server Utama',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF2E7D32),
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: const Icon(
                Icons.check_circle,
                color: Color(0xFF2E7D32),
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebhookCard() {
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.webhook_rounded,
                  color: Color(0xFF7B1FA2),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Webhook Transaksi Masuk',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D231E),
                      ),
                    ),
                    Text(
                      'POST https://api.jenggirat.com/webhook/orders',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Color(0xFF7A6B63),
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _webhookActive,
                activeThumbColor: const Color(0xFF8D321F),
                onChanged: (val) => setState(() => _webhookActive = val),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF9F9FB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Color(0xFF64748B)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Webhook akan mengirim payload JSON otomatis saat status pesanan berubah menjadi SEDANG_PROSES atau SELESAI.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioAlertCard() {
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
        child: SwitchListTile.adaptive(
          value: _soundAlert,
          activeThumbColor: const Color(0xFF8D321F),
          secondary: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.volume_up_rounded,
              color: Color(0xFFE65100),
              size: 20,
            ),
          ),
          title: const Text(
            'Suara Notifikasi Pesanan Baru',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D231E),
            ),
          ),
          subtitle: const Text(
            'Membunyikan lonceng POS saat pesanan WhatsApp baru masuk ke antrean.',
            style: TextStyle(fontSize: 12, color: Color(0xFF7A6B63)),
          ),
          onChanged: (val) => setState(() => _soundAlert = val),
        ),
      ),
    );
  }
}
