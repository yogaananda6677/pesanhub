import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/status_semantics.dart';

/// AppStatusBadge displays a status indicator featuring both a text label
/// and a distinctive icon, ensuring colorblind-safe comprehension.
/// Fulfills Acceptance Criteria #2.
class AppStatusBadge extends StatelessWidget {
  final StatusSemantics semantics;
  final bool isPill;

  const AppStatusBadge({
    super.key,
    required this.semantics,
    this.isPill = true,
  });

  factory AppStatusBadge.order(String status, {Key? key, bool isPill = true}) {
    return AppStatusBadge(
      key: key,
      semantics: StatusSemantics.forOrder(status),
      isPill: isPill,
    );
  }

  factory AppStatusBadge.payment(
    String status, {
    Key? key,
    bool isPill = true,
  }) {
    return AppStatusBadge(
      key: key,
      semantics: StatusSemantics.forPayment(status),
      isPill: isPill,
    );
  }

  factory AppStatusBadge.source(String source, {Key? key, bool isPill = true}) {
    return AppStatusBadge(
      key: key,
      semantics: StatusSemantics.forSource(source),
      isPill: isPill,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: semantics.backgroundColor,
        borderRadius: isPill
            ? AppSpacing.borderRadiusFull
            : AppSpacing.borderRadiusSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(semantics.icon, size: 14, color: semantics.foregroundColor),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              semantics.label,
              style: AppTypography.labelSmall.copyWith(
                color: semantics.foregroundColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
