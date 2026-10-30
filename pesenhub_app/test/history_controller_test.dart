import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/history/controllers/history_controller.dart';
import 'package:pesenhub_app/queue/models/queue_order.dart';
import 'package:pesenhub_app/queue/models/queue_order_item.dart';

void main() {
  group('HistoryController Unit Tests', () {
    late List<QueueOrder> sampleOrders;

    setUp(() {
      sampleOrders = [
        QueueOrder(
          id: 'ord-1',
          orderNumber: 'ORD-20261030-001',
          customerName: 'Budi Santoso',
          customerPhone: '081234567890',
          source: 'CASHIER_MANUAL',
          orderStatus: 'COMPLETED',
          paymentStatus: 'PAID',
          createdAt: DateTime(2026, 10, 30, 10, 0),
          items: const [
            QueueOrderItem(
              name: 'Martabak Telur Spesial',
              quantity: 1,
              unitPrice: 35000,
            ),
          ],
        ),
        QueueOrder(
          id: 'ord-2',
          orderNumber: 'ORD-20261030-002',
          customerName: 'Siti Aminah',
          customerPhone: '089876543210',
          source: 'WHATSAPP',
          orderStatus: 'CANCELLED',
          paymentStatus: 'UNPAID',
          cancellationReason: 'Pelanggan membatalkan pesanan',
          cancelledBy: 'Kasir',
          createdAt: DateTime(2026, 10, 30, 11, 0),
          items: const [
            QueueOrderItem(
              name: 'Terang Bulan Coklat Keju',
              quantity: 2,
              unitPrice: 25000,
            ),
          ],
        ),
        QueueOrder(
          id: 'ord-3',
          orderNumber: 'ORD-20261029-003',
          customerName: 'Ahmad Dani',
          customerPhone: '085551234567',
          source: 'CUSTOMER_WEB',
          orderStatus: 'REJECTED',
          paymentStatus: 'UNPAID',
          cancellationReason: 'Bahan baku habis',
          cancelledBy: 'Sistem',
          createdAt: DateTime(2026, 10, 29, 20, 0),
          items: const [
            QueueOrderItem(
              name: 'Es Teh Manis Jumbo',
              quantity: 1,
              unitPrice: 6000,
              isDrink: true,
            ),
          ],
        ),
      ];
    });

    test('initial state contains all passed orders sorted newest first', () {
      final controller = HistoryController(initialOrders: sampleOrders);

      expect(controller.orders.length, equals(3));
      final filtered = controller.filteredOrders;
      expect(filtered.length, equals(3));
      // Newest (11:00) should be first
      expect(filtered.first.id, equals('ord-2'));
    });

    test(
      'search filters by order number, customer name, phone, or item name',
      () {
        final controller = HistoryController(initialOrders: sampleOrders);

        // Search by order number
        controller.setSearchQuery('001');
        expect(controller.filteredOrders.length, equals(1));
        expect(
          controller.filteredOrders.first.orderNumber,
          equals('ORD-20261030-001'),
        );

        // Search by customer name
        controller.setSearchQuery('Siti');
        expect(controller.filteredOrders.length, equals(1));
        expect(
          controller.filteredOrders.first.customerName,
          equals('Siti Aminah'),
        );

        // Search by phone
        controller.setSearchQuery('08555');
        expect(controller.filteredOrders.length, equals(1));
        expect(
          controller.filteredOrders.first.customerName,
          equals('Ahmad Dani'),
        );

        // Search by item name
        controller.setSearchQuery('Terang Bulan');
        expect(controller.filteredOrders.length, equals(1));
        expect(controller.filteredOrders.first.id, equals('ord-2'));

        // Non-matching search
        controller.setSearchQuery('Nasi Padang');
        expect(controller.filteredOrders.isEmpty, isTrue);
      },
    );

    test('status filter filters completed vs cancelled/rejected', () {
      final controller = HistoryController(initialOrders: sampleOrders);

      // Selesai
      controller.setStatusFilter(HistoryStatusFilter.completed);
      expect(controller.filteredOrders.length, equals(1));
      expect(controller.filteredOrders.first.isCompleted, isTrue);

      // Batal (includes CANCELLED and REJECTED)
      controller.setStatusFilter(HistoryStatusFilter.cancelled);
      expect(controller.filteredOrders.length, equals(2));
      for (final order in controller.filteredOrders) {
        expect(order.isCancelled, isTrue);
      }

      // Semua
      controller.setStatusFilter(HistoryStatusFilter.all);
      expect(controller.filteredOrders.length, equals(3));
    });

    test('cancellation reasons and actor details are preserved', () {
      final controller = HistoryController(initialOrders: sampleOrders);
      controller.setStatusFilter(HistoryStatusFilter.cancelled);

      final cancelled = controller.filteredOrders.firstWhere(
        (o) => o.id == 'ord-2',
      );
      expect(
        cancelled.cancellationReason,
        equals('Pelanggan membatalkan pesanan'),
      );
      expect(cancelled.cancelledBy, equals('Kasir'));

      final rejected = controller.filteredOrders.firstWhere(
        (o) => o.id == 'ord-3',
      );
      expect(rejected.cancellationReason, equals('Bahan baku habis'));
      expect(rejected.cancelledBy, equals('Sistem'));
    });

    test('custom date range filter can be set', () async {
      final controller = HistoryController(initialOrders: sampleOrders);

      final range = DateTimeRange(
        start: DateTime(2026, 10, 29),
        end: DateTime(2026, 10, 30),
      );
      await controller.setDateRangeFilter(
        HistoryDateRangeFilter.custom,
        customRange: range,
      );

      expect(controller.dateRangeFilter, equals(HistoryDateRangeFilter.custom));
      expect(controller.customDateRange, equals(range));
    });
  });
}
