import 'cart_item.dart';

/// CartOrderDraft encapsulates all order data before explicit review and submission.
/// Fulfills Issue #28 Criteria #1 & #2 (idempotency key & client order id).
class CartOrderDraft {
  final String idempotencyKey;
  final String clientOrderId;
  final String customerName;
  final String? customerPhone;
  final String source; // CASHIER_MANUAL, WHATSAPP, GRABFOOD, GOFOOD, SHOPEEFOOD
  final bool isTakeaway;
  final String? takeawayNotes;
  final String paymentStatus;
  final String? paymentMethod;
  final List<CartItem> items;
  final String? branchId;

  const CartOrderDraft({
    required this.idempotencyKey,
    required this.clientOrderId,
    required this.customerName,
    this.customerPhone,
    this.source = 'CASHIER_MANUAL',
    this.isTakeaway = false,
    this.takeawayNotes,
    this.paymentStatus = 'UNPAID',
    this.paymentMethod,
    this.items = const [],
    this.branchId,
  });

  int get totalItemCount => items.fold(0, (sum, item) => sum + item.quantity);
  int get subtotalAmount => items.fold(0, (sum, item) => sum + item.lineTotal);
  int get totalAmount => subtotalAmount;

  bool get isValid => customerName.trim().isNotEmpty && items.isNotEmpty;

  CartOrderDraft copyWith({
    String? idempotencyKey,
    String? clientOrderId,
    String? customerName,
    String? customerPhone,
    String? source,
    bool? isTakeaway,
    String? takeawayNotes,
    String? paymentStatus,
    String? paymentMethod,
    List<CartItem>? items,
    String? branchId,
  }) {
    return CartOrderDraft(
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      clientOrderId: clientOrderId ?? this.clientOrderId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      source: source ?? this.source,
      isTakeaway: isTakeaway ?? this.isTakeaway,
      takeawayNotes: takeawayNotes ?? this.takeawayNotes,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      items: items ?? this.items,
      branchId: branchId ?? this.branchId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idempotency_key': idempotencyKey,
      'client_order_id': clientOrderId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'source': source,
      'is_takeaway': isTakeaway,
      'takeaway_notes': takeawayNotes,
      if (branchId != null && branchId!.isNotEmpty) 'branch_id': branchId,
      'payment_status': paymentStatus,
      'payment_method': paymentMethod,
      'items': items
          .map(
            (i) => {
              'menu_id': i.menuItem.id,
              'name': i.menuItem.name,
              'quantity': i.quantity,
              'unit_price': i.unitPrice,
              'notes': i.modifierSummary,
              'is_drink': i.isDrink,
              'modifier_groups': i.selectedOptionIds.entries
                  .map(
                    (entry) => {
                      'group_id': entry.key,
                      'option_ids': _expandedOptionIds(i, entry.key),
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(),
    };
  }

  static List<String> _expandedOptionIds(CartItem item, String groupId) {
    final quantities = item.selectedOptionQuantities[groupId];
    if (quantities == null || quantities.isEmpty) {
      return item.selectedOptionIds[groupId]!.toList(growable: false)..sort();
    }
    final ids = <String>[];
    for (final entry in quantities.entries) {
      ids.addAll(List.filled(entry.value, entry.key));
    }
    ids.sort();
    return ids;
  }
}
