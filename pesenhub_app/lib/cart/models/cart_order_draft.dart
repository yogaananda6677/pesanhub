import 'cart_item.dart';

/// CartOrderDraft encapsulates all order data before explicit review and submission.
/// Fulfills Issue #28 Criteria #1 & #2 (idempotency key & client order id).
class CartOrderDraft {
  final String idempotencyKey;
  final String clientOrderId;
  final String customerName;
  final String? customerPhone;
  final bool isTakeaway;
  final String? takeawayNotes;
  final List<CartItem> items;

  const CartOrderDraft({
    required this.idempotencyKey,
    required this.clientOrderId,
    required this.customerName,
    this.customerPhone,
    this.isTakeaway = false,
    this.takeawayNotes,
    this.items = const [],
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
    bool? isTakeaway,
    String? takeawayNotes,
    List<CartItem>? items,
  }) {
    return CartOrderDraft(
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      clientOrderId: clientOrderId ?? this.clientOrderId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      isTakeaway: isTakeaway ?? this.isTakeaway,
      takeawayNotes: takeawayNotes ?? this.takeawayNotes,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idempotency_key': idempotencyKey,
      'client_order_id': clientOrderId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'is_takeaway': isTakeaway,
      'takeaway_notes': takeawayNotes,
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
                      'option_ids': entry.value.toList(growable: false)..sort(),
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(),
    };
  }
}
