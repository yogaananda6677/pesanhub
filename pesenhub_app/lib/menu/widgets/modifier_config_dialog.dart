import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../controllers/modifier_selection_state.dart';
import '../models/menu_item.dart';
import '../models/menu_modifier_group.dart';
import '../models/menu_option.dart';

/// ModifierConfigDialog enables cashiers to configure modifiers, spice level, toppings, and quantity.
/// Fulfills Issue #27 Acceptance Criteria #2, #3, and #4.
class ModifierConfigDialog extends StatefulWidget {
  final MenuItem item;
  final ModifierSelectionState? initialState;
  final bool isEditing;
  final void Function(ModifierSelectionState configuredState)? onConfirm;

  const ModifierConfigDialog({
    super.key,
    required this.item,
    this.initialState,
    this.isEditing = false,
    this.onConfirm,
  });

  /// Helper to display this dialog responsively across mobile and tablet.
  static Future<ModifierSelectionState?> show({
    required BuildContext context,
    required MenuItem item,
    ModifierSelectionState? initialState,
    bool isEditing = false,
  }) {
    final isTablet =
        MediaQuery.sizeOf(context).width >= AppSpacing.tabletBreakpoint;

    if (isTablet) {
      return showDialog<ModifierSelectionState>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderRadiusMd,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
            child: ModifierConfigDialog(
              item: item,
              initialState: initialState,
              isEditing: isEditing,
              onConfirm: (state) => Navigator.of(ctx).pop(state),
            ),
          ),
        ),
      );
    } else {
      return showModalBottomSheet<ModifierSelectionState>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
            ),
            child: ModifierConfigDialog(
              item: item,
              initialState: initialState,
              isEditing: isEditing,
              onConfirm: (state) => Navigator.of(ctx).pop(state),
            ),
          ),
        ),
      );
    }
  }

  @override
  State<ModifierConfigDialog> createState() => _ModifierConfigDialogState();
}

class _ModifierConfigDialogState extends State<ModifierConfigDialog> {
  late final ModifierSelectionState _state;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _state =
        widget.initialState ?? ModifierSelectionState(menuItem: widget.item);
    _notesController = TextEditingController(text: _state.notes);
    _state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final validationErrors = _state.validationErrors;
    final bool isValid = _state.isValid;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top sheet drag handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // 1. Dialog Header
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isEditing) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3ED),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFDBA74)),
                        ),
                        child: const Text(
                          'Ubah Pilihan Menu',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFC2410C),
                          ),
                        ),
                      ),
                    ],
                    Text(
                      widget.item.name,
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Harga Dasar: Rp ${widget.item.priceAmount}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),

        // 2. Scrollable Body with Modifiers & Notes
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...widget.item.activeModifierGroups.map((group) {
                  final groupError = validationErrors[group.id];
                  return _buildModifierGroupSection(group, groupError);
                }),

                const SizedBox(height: AppSpacing.sm),
                const Text('Catatan Pesanan:', style: AppTypography.labelSmall),
                const SizedBox(height: AppSpacing.xs),
                AppTextField(
                  controller: _notesController,
                  hintText: 'Misal: Pisah acar, sambal sedikit, dll...',
                  onChanged: _state.setNotes,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),

        // 3. Footer: Quantity, Total Price & Confirm Button
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Quantity Stepper
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                          color: _state.quantity > 1
                              ? AppColors.primary
                              : AppColors.textMuted,
                          onPressed: _state.quantity > 1
                              ? _state.decrementQuantity
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '${_state.quantity}',
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          color: AppColors.primary,
                          onPressed: _state.incrementQuantity,
                        ),
                      ],
                    ),
                  ),

                  // Total Price
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Total:',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Rp ${_state.totalPrice}',
                        style: AppTypography.titleLarge.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Confirm Button
              AppButton(
                label: widget.isEditing
                    ? 'Simpan Perubahan'
                    : (isValid
                          ? 'Tambah ke Pesanan'
                          : 'Lengkapi Pilihan Wajib'),
                icon: widget.isEditing
                    ? Icons.save_rounded
                    : Icons.check_circle_outline_rounded,
                isFullWidth: true,
                onPressed: isValid
                    ? () {
                        if (widget.onConfirm != null) {
                          widget.onConfirm!(_state);
                        } else {
                          Navigator.of(context).pop(_state);
                        }
                      }
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModifierGroupSection(
    MenuModifierGroup group,
    String? errorMessage,
  ) {
    final isQuantityGroup = group.code == 'extra_isian' ||
        group.options.any((o) => o.priceDeltaAmount > 0 && !group.isSingleSelect);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: group.isRequired
                      ? const Color(0xFFFEF2F2)
                      : const Color(0xFFF1F5F9),
                  borderRadius: AppSpacing.borderRadiusSm,
                  border: Border.all(
                    color: group.isRequired
                        ? const Color(0xFFFECACA)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  group.isRequired
                      ? 'Wajib (Pilih 1)'
                      : (group.maxSelect > 1
                            ? 'Maksimal ${group.maxSelect}'
                            : 'Opsional'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: group.isRequired
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              errorMessage,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),

          // Options List: vertical cards for quantity groups, chips for choice groups
          if (isQuantityGroup)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: group.options.map((option) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _buildQuantityOption(group, option),
                );
              }).toList(),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: group.options.map((option) {
                return _buildOptionChip(group, option);
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildQuantityOption(MenuModifierGroup group, MenuOption option) {
    final quantity = _state.optionQuantity(group.id, option.id);
    final isSelected = quantity > 0;
    final isAvailable = option.isAvailable;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFFEF3ED) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 14,
                    color: isAvailable
                        ? (isSelected
                              ? AppColors.primary
                              : AppColors.textPrimary)
                        : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  !isAvailable
                      ? 'Stok Habis'
                      : (option.priceDeltaAmount > 0
                            ? '+Rp ${option.priceDeltaAmount}'
                            : 'Termasuk'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isAvailable
                        ? (isSelected
                              ? AppColors.primary
                              : const Color(0xFFE5573F))
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // Stepper
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Kurangi ${option.name}',
                onPressed: quantity > 0
                    ? () => _state.decrementOption(group, option)
                    : null,
                icon: Icon(
                  Icons.remove_circle_outline_rounded,
                  color: quantity > 0 ? AppColors.primary : AppColors.textMuted,
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 24),
                alignment: Alignment.center,
                child: Text(
                  '$quantity',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Tambah ${option.name}',
                onPressed: isAvailable
                    ? () => _state.incrementOption(group, option)
                    : null,
                icon: Icon(
                  Icons.add_circle_outline_rounded,
                  color: isAvailable ? AppColors.primary : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOptionChip(MenuModifierGroup group, MenuOption option) {
    final isSelected = _state.isOptionSelected(group.id, option.id);
    final isAvailable = option.isAvailable;

    String labelText = option.name;
    if (!isAvailable) {
      labelText += ' (Habis)';
    } else if (option.priceDeltaAmount > 0) {
      labelText += ' (+Rp ${option.priceDeltaAmount})';
    }

    return FilterChip(
      selected: isSelected,
      label: Text(labelText),
      selectedColor: AppColors.primary,
      checkmarkColor: Colors.white,
      backgroundColor: isAvailable ? Colors.white : const Color(0xFFF1F5F9),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: !isAvailable
            ? AppColors.textMuted
            : (isSelected ? Colors.white : AppColors.textPrimary),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: !isAvailable
              ? const Color(0xFFE2E8F0)
              : (isSelected ? AppColors.primary : const Color(0xFFCBD5E1)),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      onSelected: isAvailable ? (_) => _state.toggleOption(group, option) : null,
    );
  }
}
