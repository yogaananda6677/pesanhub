import '../../queue/models/queue_order.dart';
import '../../queue/models/queue_order_item.dart';

class QueueOrderDto {
  static const _sources = {'CASHIER_MANUAL', 'CUSTOMER_WEB', 'WHATSAPP'};
  static const _statuses = {
    'PENDING',
    'ACCEPTED',
    'PREPARING',
    'READY_FOR_PICKUP',
    'COMPLETED',
    'REJECTED',
    'CANCELLED',
  };

  final QueueOrder order;

  const QueueOrderDto(this.order);

  factory QueueOrderDto.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final orderNumber = _requiredString(json, 'order_number');
    final source = _requiredString(json, 'source');
    final status = _requiredString(json, 'status');
    final customerName = _requiredString(json, 'customer_name');
    final createdAt = DateTime.tryParse(_requiredString(json, 'created_at'));
    final version = json['version'];
    final rawItems = json['items'];
    if (!_sources.contains(source) ||
        !_statuses.contains(status) ||
        createdAt == null ||
        version is! num ||
        version.toInt() < 1 ||
        rawItems is! List) {
      throw const FormatException('invalid order contract');
    }

    final items = rawItems
        .map((raw) {
          if (raw is! Map) throw const FormatException('invalid order item');
          final item = Map<String, dynamic>.from(raw);
          final quantity = item['quantity'];
          final unitPrice = item['unit_price_amount'];
          if (quantity is! num || unitPrice is! num || quantity.toInt() < 1) {
            throw const FormatException('invalid order item values');
          }
          return QueueOrderItem(
            name: _requiredString(item, 'name'),
            quantity: quantity.toInt(),
            unitPrice: unitPrice.toInt(),
            notes:
                item['notes'] is String && (item['notes'] as String).isNotEmpty
                ? item['notes'] as String
                : null,
            isDrink:
                (item['category_name'] as String?)?.toLowerCase().contains(
                  'minum',
                ) ??
                false,
          );
        })
        .toList(growable: false);

    final phone = json['customer_phone'];
    return QueueOrderDto(
      QueueOrder(
        id: id,
        orderNumber: orderNumber,
        customerName: customerName,
        customerPhone: phone is String ? phone : '',
        source: source,
        orderStatus: status,
        paymentStatus: json['payment_status'] is String
            ? json['payment_status'] as String
            : 'UNPAID',
        isTakeaway: true,
        takeawayNotes:
            json['notes'] is String && (json['notes'] as String).isNotEmpty
            ? json['notes'] as String
            : null,
        items: items,
        createdAt: createdAt.toUtc(),
        version: version.toInt(),
      ),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('missing $key');
    }
    return value;
  }
}

class OrderEventDto {
  static const _types = {'ORDER_CREATED', 'ORDER_STATUS_CHANGED'};

  final String eventId;
  final String eventType;
  final String orderId;
  final int version;
  final String status;

  const OrderEventDto({
    required this.eventId,
    required this.eventType,
    required this.orderId,
    required this.version,
    required this.status,
  });

  factory OrderEventDto.fromJson(Map<String, dynamic> json) {
    final eventId = QueueOrderDto._requiredString(json, 'event_id');
    final eventType = QueueOrderDto._requiredString(json, 'event_type');
    final orderId = QueueOrderDto._requiredString(json, 'order_id');
    final status = QueueOrderDto._requiredString(json, 'status');
    final version = json['version'];
    if (!_types.contains(eventType) ||
        !QueueOrderDto._statuses.contains(status) ||
        version is! num ||
        version.toInt() < 1) {
      throw const FormatException('invalid event contract');
    }
    return OrderEventDto(
      eventId: eventId,
      eventType: eventType,
      orderId: orderId,
      version: version.toInt(),
      status: status,
    );
  }
}
