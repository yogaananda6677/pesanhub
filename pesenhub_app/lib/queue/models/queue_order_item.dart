/// QueueOrderItem represents a single line item in an order.
class QueueOrderItem {
  final String name;
  final int quantity;
  final int unitPrice;
  final String? notes;
  final bool isDrink;

  const QueueOrderItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.notes,
    this.isDrink = false,
  });

  int get subtotal => quantity * unitPrice;
}
