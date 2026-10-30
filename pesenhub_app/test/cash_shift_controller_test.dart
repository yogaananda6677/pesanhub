import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/data/remote/pesenhub_api_client.dart';
import 'package:pesenhub_app/finance/controllers/cash_shift_controller.dart';
import 'package:pesenhub_app/finance/models/cash_shift.dart';

class MockShiftRemoteGateway implements ShiftRemoteGateway {
  CashShift? mockCurrentShift;
  List<CashShift> mockHistory = [];
  bool shouldThrow = false;
  String? throwMessage;

  int? lastStartingCash;
  int? lastActualCash;
  String? lastNotes;
  String? lastBranchId;

  @override
  Future<CashShift?> fetchCurrentShift({String? branchId}) async {
    lastBranchId = branchId;
    if (shouldThrow) {
      throw Exception(throwMessage ?? 'Failed to load shift');
    }
    return mockCurrentShift;
  }

  @override
  Future<CashShift> openShift({
    required int startingCash,
    String? notes,
    String? branchId,
  }) async {
    lastStartingCash = startingCash;
    lastNotes = notes;
    lastBranchId = branchId;
    if (shouldThrow) {
      throw Exception(throwMessage ?? 'Failed to open shift');
    }
    final shift = CashShift(
      id: 'shift-100',
      branchId: branchId ?? 'b1',
      cashierId: 'user-1',
      cashierName: 'Kasir Utama',
      shiftStart: DateTime.now(),
      startingCash: startingCash,
      status: 'OPEN',
      notes: notes,
    );
    mockCurrentShift = shift;
    return shift;
  }

  @override
  Future<CashShift> closeShift({
    String? shiftId,
    required int actualCash,
    String? notes,
  }) async {
    lastActualCash = actualCash;
    lastNotes = notes;
    if (shouldThrow) {
      throw Exception(throwMessage ?? 'Failed to close shift');
    }
    final current =
        mockCurrentShift ??
        CashShift(
          id: shiftId ?? 'shift-100',
          branchId: 'b1',
          cashierId: 'user-1',
          cashierName: 'Kasir Utama',
          shiftStart: DateTime.now().subtract(const Duration(hours: 8)),
          startingCash: 200000,
          expectedCash: 700000,
          cashIn: 500000,
          status: 'OPEN',
        );

    final closedShift = current.copyWith(
      shiftEnd: DateTime.now(),
      actualCash: actualCash,
      discrepancy: actualCash - current.expectedCash,
      status: 'CLOSED',
      notes: notes,
    );
    mockCurrentShift = null;
    mockHistory.insert(0, closedShift);
    return closedShift;
  }

  @override
  Future<List<CashShift>> fetchShiftHistory({
    String? branchId,
    int limit = 20,
  }) async {
    lastBranchId = branchId;
    if (shouldThrow) {
      throw Exception(throwMessage ?? 'Failed to load history');
    }
    return mockHistory;
  }
}

void main() {
  group('CashShiftController Unit Tests', () {
    late MockShiftRemoteGateway mockGateway;
    late CashShiftController controller;

    setUp(() {
      mockGateway = MockShiftRemoteGateway();
      controller = CashShiftController(
        gateway: mockGateway,
        branchId: 'branch-101',
      );
    });

    test('initial state has no active shift', () {
      expect(controller.currentShift, isNull);
      expect(controller.hasActiveShift, isFalse);
      expect(controller.isLoading, isFalse);
      expect(controller.isSubmitting, isFalse);
      expect(controller.errorMessage, isNull);
      expect(controller.history, isEmpty);
    });

    test('loadCurrentShift retrieves open shift successfully', () async {
      mockGateway.mockCurrentShift = CashShift(
        id: 'shift-1',
        branchId: 'branch-101',
        cashierId: 'user-1',
        cashierName: 'Kasir Budi',
        shiftStart: DateTime.now(),
        startingCash: 250000,
        expectedCash: 500000,
        cashIn: 250000,
        status: 'OPEN',
      );

      await controller.loadCurrentShift();

      expect(controller.hasActiveShift, isTrue);
      expect(controller.currentShift, isNotNull);
      expect(controller.currentShift!.startingCash, equals(250000));
      expect(controller.currentShift!.cashIn, equals(250000));
      expect(controller.currentShift!.expectedCash, equals(500000));
    });

    test(
      'openShift initializes new session and updates currentShift',
      () async {
        final success = await controller.openShift(
          startingCash: 300000,
          notes: 'Modal awal laci pagi',
        );

        expect(success, isTrue);
        expect(controller.hasActiveShift, isTrue);
        expect(controller.currentShift!.startingCash, equals(300000));
        expect(controller.currentShift!.notes, equals('Modal awal laci pagi'));
        expect(controller.successMessage, contains('dibuka'));
        expect(mockGateway.lastStartingCash, equals(300000));
        expect(mockGateway.lastBranchId, equals('branch-101'));
      },
    );

    test('openShift captures failure message when gateway throws', () async {
      mockGateway.shouldThrow = true;
      mockGateway.throwMessage = 'Shift sudah aktif untuk kasir ini';

      final success = await controller.openShift(startingCash: 200000);

      expect(success, isFalse);
      expect(controller.hasActiveShift, isFalse);
      expect(controller.errorMessage, contains('Shift sudah aktif'));
    });

    test(
      'closeShift performs reconciliation and shifts to closed state',
      () async {
        // First open a shift
        mockGateway.mockCurrentShift = CashShift(
          id: 'shift-abc',
          branchId: 'branch-101',
          cashierId: 'user-1',
          cashierName: 'Kasir Budi',
          shiftStart: DateTime.now(),
          startingCash: 200000,
          cashIn: 400000,
          expectedCash: 600000,
          status: 'OPEN',
        );
        await controller.loadCurrentShift();
        expect(controller.hasActiveShift, isTrue);

        // Close with actual cash 590000 (discrepancy: -10000)
        final closed = await controller.closeShift(
          actualCash: 590000,
          notes: 'Selisih kurang 10rb uang kembalian',
        );

        expect(closed, isNotNull);
        expect(closed!.actualCash, equals(590000));
        expect(closed.discrepancy, equals(-10000));
        expect(closed.hasDiscrepancy, isTrue);
        expect(controller.hasActiveShift, isFalse);
        expect(controller.currentShift, isNull);
        expect(controller.history.length, equals(1));
        expect(controller.successMessage, contains('ditutup'));
      },
    );

    test('loadHistory updates shift history list', () async {
      mockGateway.mockHistory = [
        CashShift(
          id: 'shift-1',
          branchId: 'branch-101',
          cashierId: 'user-1',
          cashierName: 'Kasir Budi',
          shiftStart: DateTime(2026, 10, 29, 8, 0),
          shiftEnd: DateTime(2026, 10, 29, 16, 0),
          startingCash: 200000,
          expectedCash: 500000,
          actualCash: 500000,
          discrepancy: 0,
          status: 'CLOSED',
        ),
      ];

      await controller.loadHistory();

      expect(controller.history.length, equals(1));
      expect(controller.history.first.isBalanced, isTrue);
    });
  });
}
