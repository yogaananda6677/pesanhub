import 'queue_order_item.dart';

/// QueueOrder represents an order in the PesenHub unified order queue.
/// Fulfills Issue #26 Acceptance Criteria #1, #2, #3, and #4.
class QueueOrder {
  final String id;
  final String orderNumber;
  final String customerName;
  final String customerPhone;
  final String source; // WHATSAPP, CUSTOMER_WEB, CASHIER_MANUAL
  final String
  orderStatus; // PENDING, ACCEPTED, PREPARING, READY_FOR_PICKUP, COMPLETED, REJECTED, CANCELLED
  final String paymentStatus; // UNPAID, PAID, FAILED, EXPIRED, REFUNDED
  final bool isTakeaway;
  final String? takeawayNotes;
  final List<QueueOrderItem> items;
  final DateTime createdAt;
  final int version;

  const QueueOrder({
    required this.id,
    required this.orderNumber,
    required this.customerName,
    required this.customerPhone,
    required this.source,
    required this.orderStatus,
    required this.paymentStatus,
    this.isTakeaway = false,
    this.takeawayNotes,
    this.items = const [],
    required this.createdAt,
    this.version = 1,
  });

  /// Total sum of items in the order.
  int get totalAmount => items.fold(0, (sum, item) => sum + item.subtotal);

  /// True if the order is still active in the kitchen/queue lifecycle.
  bool get isActive =>
      orderStatus != 'COMPLETED' &&
      orderStatus != 'REJECTED' &&
      orderStatus != 'CANCELLED';

  /// True if the active order has exceeded the 15-minute preparation threshold.
  bool isOverdueAt(DateTime now) {
    if (!isActive) return false;
    return now.difference(createdAt).inMinutes >= 15;
  }

  /// Default overdue check against current local time.
  bool get isOverdue => isOverdueAt(DateTime.now());

  /// Items categorized as drinks/beverages for fast barista preparation.
  List<QueueOrderItem> get drinkItems =>
      items.where((item) => item.isDrink).toList();

  /// Items categorized as food.
  List<QueueOrderItem> get foodItems =>
      items.where((item) => !item.isDrink).toList();

  /// Formatted time string (HH:mm) of order creation.
  String get formattedTime {
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  QueueOrder copyWith({
    String? id,
    String? orderNumber,
    String? customerName,
    String? customerPhone,
    String? source,
    String? orderStatus,
    String? paymentStatus,
    bool? isTakeaway,
    String? takeawayNotes,
    List<QueueOrderItem>? items,
    DateTime? createdAt,
    int? version,
  }) {
    return QueueOrder(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      source: source ?? this.source,
      orderStatus: orderStatus ?? this.orderStatus,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      isTakeaway: isTakeaway ?? this.isTakeaway,
      takeawayNotes: takeawayNotes ?? this.takeawayNotes,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      version: version ?? this.version,
    );
  }
}
