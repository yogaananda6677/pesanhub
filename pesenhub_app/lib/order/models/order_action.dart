import 'package:flutter/material.dart';

/// OrderAction encapsulates a contextual state transition action for an order.
/// Fulfills Issue #29 Criteria #1 and #4.
class OrderAction {
  final String targetStatus;
  final String label;
  final IconData icon;
  final bool isDestructive;
  final String? helperText;

  const OrderAction({
    required this.targetStatus,
    required this.label,
    required this.icon,
    this.isDestructive = false,
    this.helperText,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderAction &&
          runtimeType == other.runtimeType &&
          targetStatus == other.targetStatus &&
          label == other.label;

  @override
  int get hashCode => Object.hash(targetStatus, label);
}
