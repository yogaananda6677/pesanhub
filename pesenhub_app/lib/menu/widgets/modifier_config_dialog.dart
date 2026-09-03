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
  final void Function(ModifierSelectionState configuredState)? onConfirm;

  const ModifierConfigDialog({
    super.key,
    required this.item,
    this.initialState,
    this.onConfirm,
  });

  /// Helper to display this dialog responsively across mobile and tablet.
  static Future<ModifierSelectionState?> show({
    required BuildContext context,
    required MenuItem item,
    ModifierSelectionState? initialState,
  }) {
    final isTablet =
        MediaQuery.sizeOf(context).width >= AppSpacing.tabletBreakpoint;

    if (isTablet) {
      return showDialog<ModifierSelectionState>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderRadiusMd,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
            child: ModifierConfigDialog(
              item: item,
              initialState: initialState,
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
            ),
            child: ModifierConfigDialog(
              item: item,
              initialState: initialState,
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

  @override
  void initState() {
    super.initState();
    _state =
        widget.initialState ?? ModifierSelectionState(menuItem: widget.item);
    _state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
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
        // 1. Dialog Header
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      style: AppTypography.bodySmall,
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
        const Divider(height: 1),

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

                const SizedBox(height: AppSpacing.md),
                const Text('Catatan Pesanan:', style: AppTypography.labelSmall),
                const SizedBox(height: AppSpacing.xs),
                AppTextField(
                  hintText: 'Misal: Pisah acar, sambal sedikit, dll...',
                  onChanged: _state.setNotes,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),

        // 3. Footer: Quantity, Total Price & Add Button
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Quantity Stepper
                  Row(
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
                      Text(
                        '${_state.quantity}',
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        color: AppColors.primary,
                        onPressed: _state.incrementQuantity,
                      ),
                    ],
                  ),

                  // Total Price
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Total:', style: AppTypography.bodySmall),
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

              // Add to Cart Button (Criteria #3: Disabled if required modifiers invalid)
              AppButton(
                label: isValid ? 'Tambah ke Pesanan' : 'Lengkapi Pilihan Wajib',
                icon: Icons.check_circle_outline_rounded,
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
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: group.isRequired
                      ? AppColors.errorBg
                      : AppColors.surfaceVariant,
                  borderRadius: AppSpacing.borderRadiusSm,
                  border: Border.all(
                    color: group.isRequired
                        ? AppColors.error.withValues(alpha: 0.3)
                        : AppColors.border,
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
                        ? AppColors.error
                        : AppColors.textSecondary,
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

          // Options List
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
      selectedColor: AppColors.primaryContainer,
      checkmarkColor: AppColors.primary,
      backgroundColor: isAvailable
          ? AppColors.surface
          : AppColors.surfaceVariant,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: !isAvailable
            ? AppColors.textMuted
            : (isSelected ? AppColors.primary : AppColors.textPrimary),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusFull,
        side: BorderSide(
          color: !isAvailable
              ? AppColors.border
              : (isSelected ? AppColors.primary : AppColors.border),
        ),
      ),
      // Criteria #2: Item/option unavailable cannot be selected
      onSelected: isAvailable
          ? (_) => _state.toggleOption(group, option)
          : null,
    );
  }
}
