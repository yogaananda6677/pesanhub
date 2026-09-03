import 'package:flutter/material.dart';
import '../showcase/design_system_showcase.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_status_badge.dart';
import '../widgets/app_text_field.dart';

/// PosDestinationView provides the cashier order creation UI.
/// Designed with scrolling to maintain full keyboard accessibility.
class PosDestinationView extends StatefulWidget {
  const PosDestinationView({super.key});

  @override
  State<PosDestinationView> createState() => _PosDestinationViewState();
}

class _PosDestinationViewState extends State<PosDestinationView> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const PageStorageKey('pos_view_scroll'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Identitas Pelanggan',
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Nama Pelanggan',
                  hintText: 'Contoh: Budi Santoso',
                  controller: _nameController,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Nomor WhatsApp',
                  hintText: '081234567890',
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  prefixIcon: const Icon(Icons.phone_outlined),
                  helperText: 'Wajib untuk notifikasi status pesanan',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pilih Menu', style: AppTypography.titleMedium),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  hintText: 'Cari nasi goreng, mie, minuman...',
                  controller: _searchController,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
                const SizedBox(height: AppSpacing.md),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Nasi Goreng Spesial (x1)',
                        style: AppTypography.bodyLarge,
                      ),
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Text('Rp 28.000', style: AppTypography.moneyPrimary),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Pedas Sedang, Telur Ceplok Matang',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                const SizedBox(height: AppSpacing.md),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Total Pembayaran',
                        style: AppTypography.titleLarge,
                      ),
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Text('Rp 28.000', style: AppTypography.moneyPrimary),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'Simpan dan Proses Pesanan',
                  icon: Icons.check_circle_outline_rounded,
                  isFullWidth: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// QueueDestinationView provides the unified order queue monitoring UI.
class QueueDestinationView extends StatelessWidget {
  const QueueDestinationView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const PageStorageKey('queue_view_scroll'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppStatusBadge.order('PENDING'),
              AppStatusBadge.order('PREPARING'),
              AppStatusBadge.order('READY_FOR_PICKUP'),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    const Text(
                      'Order #ORD-101',
                      style: AppTypography.titleMedium,
                    ),
                    AppStatusBadge.order('PENDING'),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Pelanggan: Siti Rahma',
                  style: AppTypography.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    AppStatusBadge.source('CUSTOMER_WEB'),
                    AppStatusBadge.payment('UNPAID'),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  '1x Nasi Goreng Gila (Rp 25.000)',
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: AppButton.outlined(
                        label: 'Tolak',
                        onPressed: () {},
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: AppButton(
                        label: 'Terima Pesanan',
                        onPressed: () {},
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
}

/// KdsDestinationView provides the Kitchen Display Screen ticket monitor.
class KdsDestinationView extends StatelessWidget {
  const KdsDestinationView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const PageStorageKey('kds_view_scroll'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppBanner(
            message:
                'Mode KDS Aktif: Menampilkan tiket pesanan yang perlu dimasak.',
            type: AppBannerType.info,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    const Text(
                      'Tiket Dapur #101',
                      style: AppTypography.titleLarge,
                    ),
                    AppStatusBadge.order('PREPARING'),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  '2x Nasi Goreng Spesial',
                  style: AppTypography.headline,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Catatan: 1 Pedas Banget, 1 Tidak Pedas',
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'Tandai Siap Diambil',
                  icon: Icons.check_rounded,
                  isFullWidth: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// MenuDestinationView provides the menu catalog availability management UI.
class MenuDestinationView extends StatelessWidget {
  const MenuDestinationView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const PageStorageKey('menu_view_scroll'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Ketersediaan Menu Hari Ini',
            style: AppTypography.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Nasi Goreng Spesial',
                style: AppTypography.titleMedium,
              ),
              subtitle: const Text(
                'Tersedia • Rp 28.000',
                style: AppTypography.bodyMedium,
              ),
              trailing: Switch(
                value: true,
                activeTrackColor: AppColors.success,
                onChanged: (val) {},
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Nasi Goreng Seafood',
                style: AppTypography.titleMedium,
              ),
              subtitle: const Text(
                'Habis / Out of Stock • Rp 32.000',
                style: AppTypography.bodyMedium,
              ),
              trailing: Switch(
                value: false,
                activeTrackColor: AppColors.success,
                onChanged: (val) {},
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// SettingsDestinationView provides outlet settings and access to the Design System Catalog.
class SettingsDestinationView extends StatelessWidget {
  const SettingsDestinationView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const PageStorageKey('settings_view_scroll'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Informasi Outlet',
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'PesenHub Outlet #01 — Nasi Goreng Pusat',
                  style: AppTypography.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Versi Aplikasi: 1.0.0 (Phase 1B)',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppButton.outlined(
                  label: 'Buka Katalog Design System',
                  icon: Icons.palette_outlined,
                  isFullWidth: true,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DesignSystemShowcase(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
