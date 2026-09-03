import 'package:flutter/material.dart';
import '../../queue/models/queue_order.dart';
import '../models/order_action.dart';

/// OrderDetailController manages order detail presentation, optimistic version conflict
/// resolution, and role-based contextual status transitions.
/// Fulfills Issue #29 Criteria #1, #2, #3, and #4.
class OrderDetailController extends ChangeNotifier {
  QueueOrder _order;
  String _role; // 'STAFF', 'KDS', 'CUSTOMER'

  bool _isExecutingAction = false;
  String? _conflictMessage;
  String? _errorMessage;
  String? _successMessage;

  OrderDetailController({
    required QueueOrder initialOrder,
    this._role = 'STAFF',
  }) : _order = initialOrder;

  // Getters
  QueueOrder get order => _order;
  String get role => _role;
  bool get isExecutingAction => _isExecutingAction;
  String? get conflictMessage => _conflictMessage;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

  void setRole(String newRole) {
    _role = newRole;
    notifyListeners();
  }

  void updateOrder(QueueOrder freshOrder) {
    _order = freshOrder;
    _conflictMessage = null;
    _errorMessage = null;
    notifyListeners();
  }

  void clearMessages() {
    _conflictMessage = null;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  /// Evaluates exactly ONE contextual primary action based on current state and role.
  /// Fulfills Criteria #1 and Criteria #4.
  OrderAction? get primaryAction {
    // 1. CUSTOMER: Read-only
    if (_role == 'CUSTOMER') {
      return null;
    }

    // 2. KDS (Kitchen Display): Only kitchen cooking transitions allowed
    if (_role == 'KDS') {
      if (_order.orderStatus == 'PREPARING') {
        return const OrderAction(
          targetStatus: 'READY_FOR_PICKUP',
          label: 'Tandai Siap',
          icon: Icons.check_circle_outline_rounded,
          helperText: 'Pindahkan pesanan ke meja penyerahan / kasir',
        );
      }
      return null;
    }

    // 3. STAFF (Cashier / Store Staff): Full operational flow
    switch (_order.orderStatus) {
      case 'PENDING':
        return const OrderAction(
          targetStatus: 'ACCEPTED',
          label: 'Terima Pesanan',
          icon: Icons.thumb_up_alt_outlined,
          helperText: 'Konfirmasi order dan teruskan ke dapur',
        );
      case 'ACCEPTED':
        return const OrderAction(
          targetStatus: 'PREPARING',
          label: 'Mulai Masak',
          icon: Icons.outdoor_grill_rounded,
          helperText: 'Dapur mulai memasak pesanan ini',
        );
      case 'PREPARING':
        // Criteria #1: Given PREPARING, primary action adalah Tandai siap dan target READY_FOR_PICKUP
        return const OrderAction(
          targetStatus: 'READY_FOR_PICKUP',
          label: 'Tandai Siap',
          icon: Icons.done_all_rounded,
          helperText: 'Pesanan selesai dimasak dan siap diambil',
        );
      case 'READY_FOR_PICKUP':
        return const OrderAction(
          targetStatus: 'COMPLETED',
          label: 'Selesaikan Order',
          icon: Icons.task_alt_rounded,
          helperText: 'Pesanan telah diserahkan ke pelanggan',
        );
      default:
        // Terminal states: COMPLETED, REJECTED, CANCELLED
        return null;
    }
  }

  /// Evaluates secondary action (e.g. Reject / Cancel) if role is permitted.
  OrderAction? get secondaryAction {
    if (_role != 'STAFF') return null;

    switch (_order.orderStatus) {
      case 'PENDING':
        return const OrderAction(
          targetStatus: 'REJECTED',
          label: 'Tolak Pesanan',
          icon: Icons.cancel_outlined,
          isDestructive: true,
          helperText: 'Tolak pesanan jika menu habis atau kendala operasional',
        );
      case 'ACCEPTED':
        return const OrderAction(
          targetStatus: 'CANCELLED',
          label: 'Batalkan Pesanan',
          icon: Icons.highlight_off_rounded,
          isDestructive: true,
          helperText: 'Batalkan pesanan atas permintaan pelanggan',
        );
      default:
        return null;
    }
  }

  /// Executes a status transition with optimistic concurrency and conflict detection.
  /// Fulfills Criteria #2 (stale version conflict) and Criteria #4 (role guard).
  Future<bool> executeAction(
    OrderAction action, {
    Future<QueueOrder> Function(
      String orderId,
      String targetStatus,
      int expectedVersion,
    )?
    transitionFn,
    Future<QueueOrder> Function(String orderId)? reloadFn,
  }) async {
    if (_isExecutingAction) return false;

    // Role Guard Check
    if (_role == 'CUSTOMER') {
      _errorMessage =
          'Peran Anda tidak memiliki izin untuk mengubah status pesanan.';
      notifyListeners();
      return false;
    }

    if (_role == 'KDS' && action.targetStatus != 'READY_FOR_PICKUP') {
      _errorMessage =
          'Peran KDS hanya diizinkan menandai pesanan selesai dimasak.';
      notifyListeners();
      return false;
    }

    _isExecutingAction = true;
    _conflictMessage = null;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      QueueOrder updated;
      if (transitionFn != null) {
        updated = await transitionFn(
          _order.id,
          action.targetStatus,
          _order.version,
        );
      } else {
        // Default deterministic transition
        updated = QueueOrder(
          id: _order.id,
          orderNumber: _order.orderNumber,
          customerName: _order.customerName,
          customerPhone: _order.customerPhone,
          source: _order.source,
          orderStatus: action.targetStatus,
          paymentStatus: _order.paymentStatus,
          isTakeaway: _order.isTakeaway,
          takeawayNotes: _order.takeawayNotes,
          items: _order.items,
          createdAt: _order.createdAt,
          version: _order.version + 1,
        );
      }

      _order = updated;
      _successMessage =
          'Status pesanan berhasil diubah menjadi ${action.targetStatus}.';
      _isExecutingAction = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isExecutingAction = false;
      final errorStr = e.toString();

      // Criteria #2: Stale version conflict detection
      if (errorStr.contains('VERSION_CONFLICT') ||
          errorStr.contains('conflict') ||
          errorStr.contains('stale') ||
          errorStr.contains('409')) {
        _conflictMessage =
            'Konflik Versi: Pesanan telah diperbarui oleh perangkat atau staf lain. Memuat data terbaru dari server...';
        notifyListeners();

        // Reload fresh order from server WITHOUT overwriting
        if (reloadFn != null) {
          try {
            final freshOrder = await reloadFn(_order.id);
            _order = freshOrder;
          } catch (_) {}
        }
      } else {
        _errorMessage = 'Gagal memperbarui status: $errorStr';
      }
      notifyListeners();
      return false;
    }
  }
}
