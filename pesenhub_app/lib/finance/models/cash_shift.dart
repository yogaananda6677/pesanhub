import '../../core/utils/currency_formatter.dart';

class CashShift {
  final String id;
  final String branchId;
  final String cashierId;
  final String cashierName;
  final DateTime shiftStart;
  final DateTime? shiftEnd;
  final int startingCash;
  final int expectedCash;
  final int? actualCash;
  final int cashIn;
  final int cashOut;
  final int? discrepancy;
  final String? notes;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  CashShift({
    required this.id,
    required this.branchId,
    required this.cashierId,
    required this.cashierName,
    DateTime? shiftStart,
    DateTime? openedAt,
    DateTime? shiftEnd,
    DateTime? closedAt,
    int? startingCash,
    int? openingCash,
    this.expectedCash = 0,
    this.actualCash,
    int? cashIn,
    int? cashSales,
    this.cashOut = 0,
    int? discrepancy,
    int? cashDiscrepancy,
    String? notes,
    String? note,
    this.status = 'OPEN',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : shiftStart = shiftStart ?? openedAt ?? DateTime.now(),
       shiftEnd = shiftEnd ?? closedAt,
       startingCash = startingCash ?? openingCash ?? 0,
       cashIn = cashIn ?? cashSales ?? 0,
       discrepancy = discrepancy ?? cashDiscrepancy,
       notes = notes ?? note,
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get isOpen => status == 'OPEN';
  bool get isClosed => status == 'CLOSED';

  bool get hasDiscrepancy => discrepancy != null && discrepancy != 0;
  bool get isDiscrepancy => hasDiscrepancy;
  bool get isBalanced => discrepancy == 0;

  // Convenience aliases
  DateTime get openedAt => shiftStart;
  DateTime? get closedAt => shiftEnd;
  int get openingCash => startingCash;
  int get cashSales => cashIn;
  int? get cashDiscrepancy => discrepancy;
  String? get note => notes;

  CashShift copyWith({
    String? id,
    String? branchId,
    String? cashierId,
    String? cashierName,
    DateTime? shiftStart,
    DateTime? shiftEnd,
    int? startingCash,
    int? expectedCash,
    int? actualCash,
    int? cashIn,
    int? cashOut,
    int? discrepancy,
    String? notes,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CashShift(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      cashierId: cashierId ?? this.cashierId,
      cashierName: cashierName ?? this.cashierName,
      shiftStart: shiftStart ?? this.shiftStart,
      shiftEnd: shiftEnd ?? this.shiftEnd,
      startingCash: startingCash ?? this.startingCash,
      expectedCash: expectedCash ?? this.expectedCash,
      actualCash: actualCash ?? this.actualCash,
      cashIn: cashIn ?? this.cashIn,
      cashOut: cashOut ?? this.cashOut,
      discrepancy: discrepancy ?? this.discrepancy,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get formattedStartingCash =>
      CurrencyFormatter.formatRupiah(startingCash);
  String get formattedExpectedCash =>
      CurrencyFormatter.formatRupiah(expectedCash);
  String get formattedActualCash =>
      actualCash != null ? CurrencyFormatter.formatRupiah(actualCash!) : '-';
  String get formattedCashIn => CurrencyFormatter.formatRupiah(cashIn);
  String get formattedCashOut => CurrencyFormatter.formatRupiah(cashOut);
  String get formattedDiscrepancy {
    if (discrepancy == null) return '-';
    if (discrepancy == 0) return 'Rp 0 (Pas)';
    if (discrepancy! > 0) {
      return '+${CurrencyFormatter.formatRupiah(discrepancy!)} (Lebih)';
    }
    return '-${CurrencyFormatter.formatRupiah(discrepancy!.abs())} (Kurang)';
  }

  factory CashShift.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic val) {
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    int? toNullableInt(dynamic val) {
      if (val == null) return null;
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val);
      return null;
    }

    return CashShift(
      id: (json['id'] ?? '').toString(),
      branchId: (json['branch_id'] ?? '').toString(),
      cashierId: (json['cashier_id'] ?? '').toString(),
      cashierName: (json['cashier_name'] ?? 'Kasir Utama').toString(),
      shiftStart:
          DateTime.tryParse(json['shift_start']?.toString() ?? '') ??
          DateTime.now(),
      shiftEnd: json['shift_end'] != null
          ? DateTime.tryParse(json['shift_end'].toString())
          : null,
      startingCash: toInt(json['starting_cash']),
      expectedCash: toInt(json['expected_cash']),
      actualCash: toNullableInt(json['actual_cash']),
      cashIn: toInt(json['cash_in']),
      cashOut: toInt(json['cash_out']),
      discrepancy: toNullableInt(json['discrepancy']),
      notes: json['notes']?.toString(),
      status: (json['status'] ?? 'OPEN').toString(),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
