import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../menu/controllers/modifier_selection_state.dart';
import '../../menu/models/menu_item.dart';
import '../../queue/models/queue_order.dart';
import '../../queue/models/queue_order_item.dart';
import '../models/cart_item.dart';
import '../models/cart_order_draft.dart';

/// CartController manages the active order draft, line items, takeaway preferences,
/// idempotency keys, and explicit order submission.
/// Fulfills Issue #28 Criteria #1, #2, #3, and #4.
class CartController extends ChangeNotifier {
  final List<CartItem> _items = [];
  String _customerName = '';
  String _customerPhone = '';
  bool _isTakeaway = false;
  String _takeawayNotes = '';

  late String _idempotencyKey;
  late String _clientOrderId;

  bool _isSubmitting = false;
  String? _errorMessage;
  String? _discrepancyMessage;
  QueueOrder? _lastCreatedOrder;

  CartController() {
    _generateFreshKeys();
  }

  void _generateFreshKeys() {
    _idempotencyKey = _generateId();
    _clientOrderId = _generateId();
  }

  static String _generateId() {
    final random = Random();
    final hexDigits = '0123456789abcdef';
    return List.generate(32, (_) => hexDigits[random.nextInt(16)]).join();
  }

  // Getters
  List<CartItem> get items => List.unmodifiable(_items);
  String get customerName => _customerName;
  String get customerPhone => _customerPhone;
  bool get isTakeaway => _isTakeaway;
  String get takeawayNotes => _takeawayNotes;
  String get idempotencyKey => _idempotencyKey;
  String get clientOrderId => _clientOrderId;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;
  String? get discrepancyMessage => _discrepancyMessage;
  QueueOrder? get lastCreatedOrder => _lastCreatedOrder;

  int get totalItemCount => _items.fold(0, (sum, i) => sum + i.quantity);
  int get subtotalAmount => _items.fold(0, (sum, i) => sum + i.lineTotal);
  int get totalAmount => subtotalAmount;
  bool get isEmpty => _items.isEmpty;

  CartOrderDraft get currentDraft => CartOrderDraft(
    idempotencyKey: _idempotencyKey,
    clientOrderId: _clientOrderId,
    customerName: _customerName,
    customerPhone: _customerPhone.isEmpty ? null : _customerPhone,
    isTakeaway: _isTakeaway,
    takeawayNotes: _takeawayNotes.isEmpty ? null : _takeawayNotes,
    items: List.unmodifiable(_items),
  );

  // Mutations
  void setCustomerName(String name) {
    _customerName = name;
    notifyListeners();
  }

  void setCustomerPhone(String phone) {
    _customerPhone = phone;
    notifyListeners();
  }

  void setTakeaway(bool val) {
    _isTakeaway = val;
    notifyListeners();
  }

  void setTakeawayNotes(String notes) {
    _takeawayNotes = notes;
    notifyListeners();
  }

  void clearErrorMessage() {
    _errorMessage = null;
    notifyListeners();
  }

  void clearDiscrepancy() {
    _discrepancyMessage = null;
    notifyListeners();
  }

  /// Adds an item configured from ModifierSelectionState.
  void addItemFromModifierState(
    MenuItem menuItem,
    ModifierSelectionState state,
  ) {
    final lineItem = CartItem(
      id: _generateId(),
      menuItem: menuItem,
      modifierSummary: state.formattedModifierSummary,
      selectedOptionIds: state.selectedOptionIds,
      quantity: state.quantity,
      unitPrice: state.unitPrice,
      notes: state.notes,
    );
    _items.add(lineItem);
    notifyListeners();
  }

  /// Updates quantity of an item in the cart. Removes if newQty <= 0.
  void updateQuantity(String cartItemId, int newQty) {
    final index = _items.indexWhere((i) => i.id == cartItemId);
    if (index != -1) {
      if (newQty <= 0) {
        _items.removeAt(index);
      } else {
        _items[index] = _items[index].copyWith(quantity: newQty);
      }
      notifyListeners();
    }
  }

  /// Removes an item from the cart.
  void removeItem(String cartItemId) {
    _items.removeWhere((i) => i.id == cartItemId);
    notifyListeners();
  }

  /// Clears the cart and generates fresh idempotency keys.
  void clearCart() {
    _items.clear();
    _customerName = '';
    _customerPhone = '';
    _isTakeaway = false;
    _takeawayNotes = '';
    _errorMessage = null;
    _discrepancyMessage = null;
    _generateFreshKeys();
    notifyListeners();
  }

  /// Submits the order manually.
  /// Fulfills Criteria #2 (idempotency & double-tap lock) and Criteria #3 (discrepancy confirmation).
  Future<QueueOrder?> submitOrder({
    Future<QueueOrder> Function(CartOrderDraft draft)? submitFn,
  }) async {
    // Double tap protection: reject if already submitting
    if (_isSubmitting) return null;

    final draft = currentDraft;
    if (draft.customerName.trim().isEmpty) {
      _errorMessage = 'Nama pelanggan wajib diisi.';
      notifyListeners();
      return null;
    }
    if (draft.items.isEmpty) {
      _errorMessage = 'Keranjang pesanan masih kosong.';
      notifyListeners();
      return null;
    }

    _isSubmitting = true;
    _errorMessage = null;
    _discrepancyMessage = null;
    notifyListeners();

    try {
      QueueOrder result;
      if (submitFn != null) {
        result = await submitFn(draft);
      } else {
        // Default deterministic submission
        final orderNumber =
            'ORD-${draft.idempotencyKey.substring(0, 8).toUpperCase()}';
        result = QueueOrder(
          id: 'ord-${draft.clientOrderId}',
          orderNumber: orderNumber,
          customerName: draft.customerName,
          customerPhone: draft.customerPhone ?? '',
          source: 'CASHIER_MANUAL',
          orderStatus: 'PENDING',
          paymentStatus: 'UNPAID',
          isTakeaway: draft.isTakeaway,
          takeawayNotes: draft.takeawayNotes,
          items: draft.items.map((i) {
            return QueueOrderItem(
              name: i.menuItem.name,
              quantity: i.quantity,
              unitPrice: i.unitPrice,
              notes: i.modifierSummary,
              isDrink: i.isDrink,
            );
          }).toList(),
          createdAt: DateTime.now(),
          version: 1,
        );
      }

      _lastCreatedOrder = result;
      // Reset cart and generate new keys for the NEXT transaction
      _items.clear();
      _customerName = '';
      _customerPhone = '';
      _isTakeaway = false;
      _takeawayNotes = '';
      _generateFreshKeys();
      _isSubmitting = false;
      notifyListeners();
      return result;
    } catch (e) {
      _isSubmitting = false;
      final errorStr = e.toString();

      // Criteria #3: Detect price or availability discrepancy from backend
      if (errorStr.contains('unavailable') ||
          errorStr.contains('habis') ||
          errorStr.contains('discrepancy')) {
        _discrepancyMessage =
            'Perubahan ketersediaan atau harga dari server: $errorStr. Silakan periksa kembali keranjang Anda.';
      } else {
        _errorMessage = 'Gagal mengirim pesanan: $errorStr. Silakan coba lagi.';
      }
      // Note: _idempotencyKey and _clientOrderId remain UNCHANGED for retry!
      notifyListeners();
      return null;
    }
  }
}
