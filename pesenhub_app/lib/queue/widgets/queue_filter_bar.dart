import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_text_field.dart';

/// QueueFilterBar provides scannable status chips, source dropdown, and order search.
class QueueFilterBar extends StatelessWidget {
  final String selectedStatus;
  final String selectedSource;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<String> onSearchChanged;
  final int Function(String status) countForStatus;

  const QueueFilterBar({
    super.key,
    required this.selectedStatus,
    required this.selectedSource,
    required this.onStatusChanged,
    required this.onSourceChanged,
    required this.onSearchChanged,
    required this.countForStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Search Bar
        AppTextField(
          hintText: 'Cari order (#ORD-101, nama pelanggan)...',
          prefixIcon: const Icon(Icons.search_rounded),
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: AppSpacing.sm),

        // 2. Status Chips with Counts
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildStatusChip('ALL', 'Semua'),
              const SizedBox(width: AppSpacing.sm),
              _buildStatusChip('PENDING', 'Menunggu'),
              const SizedBox(width: AppSpacing.sm),
              _buildStatusChip('PREPARING', 'Dimasak'),
              const SizedBox(width: AppSpacing.sm),
              _buildStatusChip('READY_FOR_PICKUP', 'Siap'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // 3. Source Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildSourceChip('ALL', 'Semua Sumber'),
              const SizedBox(width: AppSpacing.sm),
              _buildSourceChip('WHATSAPP', 'WhatsApp'),
              const SizedBox(width: AppSpacing.sm),
              _buildSourceChip('CUSTOMER_WEB', 'Web Customer'),
              const SizedBox(width: AppSpacing.sm),
              _buildSourceChip('CASHIER_MANUAL', 'Kasir Manual'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String statusKey, String label) {
    final isSelected = selectedStatus == statusKey;
    final count = countForStatus(statusKey);

    return FilterChip(
      selected: isSelected,
      label: Text('$label ($count)'),
      selectedColor: AppColors.primaryContainer,
      checkmarkColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? AppColors.primary : AppColors.textPrimary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusFull,
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
        ),
      ),
      onSelected: (_) => onStatusChanged(statusKey),
    );
  }

  Widget _buildSourceChip(String sourceKey, String label) {
    final isSelected = selectedSource == sourceKey;

    return ChoiceChip(
      selected: isSelected,
      label: Text(label),
      selectedColor: AppColors.primary.withValues(alpha: 0.1),
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? AppColors.primary : AppColors.textSecondary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusFull,
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
        ),
      ),
      onSelected: (_) => onSourceChanged(sourceKey),
    );
  }
}
