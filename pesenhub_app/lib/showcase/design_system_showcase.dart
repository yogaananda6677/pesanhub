import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_status_badge.dart';
import '../widgets/app_text_field.dart';
import '../widgets/responsive_layout.dart';

/// DesignSystemShowcase displays an interactive catalog of all tokens and components.
class DesignSystemShowcase extends StatefulWidget {
  const DesignSystemShowcase({super.key});

  @override
  State<DesignSystemShowcase> createState() => _DesignSystemShowcaseState();
}

class _DesignSystemShowcaseState extends State<DesignSystemShowcase> {
  bool _isLoading = false;

  void _toggleLoading() {
    setState(() {
      _isLoading = !_isLoading;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PesenHub Design System'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Center(
              child: Text(
                ResponsiveLayout.isTablet(context)
                    ? 'Tablet View'
                    : 'Mobile View',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ResponsiveLayout(
            mobile: _buildMobileLayout(),
            tablet: _buildTabletLayout(),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('Typography & Brand'),
        _buildTypographySection(),
        const SizedBox(height: AppSpacing.xxl),
        _buildSectionHeader('Interactive Buttons (Min 48px Target)'),
        _buildButtonsSection(),
        const SizedBox(height: AppSpacing.xxl),
        _buildSectionHeader('Order Status Semantics (Label + Icon)'),
        _buildOrderStatusSection(),
        const SizedBox(height: AppSpacing.xxl),
        _buildSectionHeader('Payment & Source Semantics'),
        _buildPaymentAndSourceSection(),
        const SizedBox(height: AppSpacing.xxl),
        _buildSectionHeader('Input Fields'),
        _buildTextFieldsSection(),
        const SizedBox(height: AppSpacing.xxl),
        _buildSectionHeader('Feedback States'),
        _buildFeedbackSection(),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionHeader('Typography & Brand'),
              _buildTypographySection(),
              const SizedBox(height: AppSpacing.xxl),
              _buildSectionHeader('Interactive Buttons (Min 48px Target)'),
              _buildButtonsSection(),
              const SizedBox(height: AppSpacing.xxl),
              _buildSectionHeader('Input Fields'),
              _buildTextFieldsSection(),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xxl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionHeader('Order Status Semantics (Label + Icon)'),
              _buildOrderStatusSection(),
              const SizedBox(height: AppSpacing.xxl),
              _buildSectionHeader('Payment & Source Semantics'),
              _buildPaymentAndSourceSection(),
              const SizedBox(height: AppSpacing.xxl),
              _buildSectionHeader('Feedback States'),
              _buildFeedbackSection(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        title,
        style: AppTypography.titleLarge.copyWith(color: AppColors.primary),
      ),
    );
  }

  Widget _buildTypographySection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Display: Nasi Goreng Spesial',
            style: AppTypography.display,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Headline: Antrean Pesanan Aktif',
            style: AppTypography.headline,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Title Large: Meja 04 - Budi Pratama',
            style: AppTypography.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Body Large: Pedas sedang, tanpa daun bawang, telur ceplok matang.',
            style: AppTypography.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Rp 28.000', style: AppTypography.moneyPrimary),
        ],
      ),
    );
  }

  Widget _buildButtonsSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            label: 'Simpan Pesanan (Primary)',
            icon: Icons.check_circle_outline_rounded,
            isLoading: _isLoading,
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.secondary(
            label: 'Cetak Struk (Secondary)',
            icon: Icons.print_outlined,
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.outlined(
            label: 'Ubah Item (Outlined)',
            icon: Icons.edit_outlined,
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.danger(
            label: 'Batalkan Pesanan (Danger)',
            icon: Icons.delete_outline_rounded,
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(label: 'Tombol Nonaktif (Disabled)', onPressed: null),
          const SizedBox(height: AppSpacing.md),
          AppButton.outlined(
            label: _isLoading ? 'Selesai Loading' : 'Simulasi Loading State',
            onPressed: _toggleLoading,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderStatusSection() {
    const statuses = [
      'PENDING',
      'ACCEPTED',
      'PREPARING',
      'READY_FOR_PICKUP',
      'COMPLETED',
      'REJECTED',
      'CANCELLED',
    ];

    return AppCard(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: statuses.map((s) => AppStatusBadge.order(s)).toList(),
      ),
    );
  }

  Widget _buildPaymentAndSourceSection() {
    const payments = ['UNPAID', 'PAID', 'FAILED', 'EXPIRED', 'REFUNDED'];
    const sources = ['CASHIER_MANUAL', 'CUSTOMER_WEB', 'WHATSAPP'];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Status Pembayaran:', style: AppTypography.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: payments.map((p) => AppStatusBadge.payment(p)).toList(),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Kanal / Sumber Pesanan:',
            style: AppTypography.labelMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: sources.map((src) => AppStatusBadge.source(src)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextFieldsSection() {
    return const AppCard(
      child: Column(
        children: [
          AppTextField(
            label: 'Nama Pelanggan',
            hintText: 'Contoh: Ahmad Fauzi',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          SizedBox(height: AppSpacing.md),
          AppTextField(
            label: 'Nomor WhatsApp',
            hintText: 'Contoh: 081234567890',
            keyboardType: TextInputType.phone,
            prefixIcon: Icon(Icons.phone_outlined),
            helperText: 'Digunakan untuk notifikasi status pesanan',
          ),
          SizedBox(height: AppSpacing.md),
          AppTextField(
            label: 'Catatan Khusus',
            hintText: 'Misal: Pisahkan sambal',
            errorText: 'Catatan tidak boleh lebih dari 100 karakter',
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackSection() {
    return Column(
      children: [
        const AppBanner(
          message: 'Koneksi internet tidak stabil. Menggunakan cache lokal.',
          type: AppBannerType.warning,
        ),
        const SizedBox(height: AppSpacing.md),
        const AppBanner(
          message: 'Pesanan #ORD-001 berhasil dikonfirmasi dan disinkronkan.',
          type: AppBannerType.success,
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: AppEmptyState(
            title: 'Antrean Dapur Kosong',
            description: 'Saat ini belum ada pesanan yang perlu dimasak.',
            actionLabel: 'Refresh Antrean',
            onAction: () {},
          ),
        ),
      ],
    );
  }
}
