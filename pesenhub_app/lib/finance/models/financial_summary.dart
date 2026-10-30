import '../../core/utils/currency_formatter.dart';

/// FinancialSummary represents the real financial aggregates returned by the backend.
class FinancialSummary {
  final int totalRevenue;
  final int grossRevenue;
  final int totalDiscount;
  final int netRevenue;
  final int cashRevenue;
  final int digitalRevenue;
  final int totalOrders;
  final int averageOrderValue;
  final Map<String, int> ordersByStatus;
  final Map<String, int> revenueByPaymentMethod;
  final Map<String, int> ordersByPaymentStatus;
  final Map<String, int> revenueByChannel;
  final Map<String, int> ordersByChannel;
  final DateTime? from;
  final DateTime? to;

  const FinancialSummary({
    int? totalRevenue,
    this.grossRevenue = 0,
    this.totalDiscount = 0,
    int? netRevenue,
    this.cashRevenue = 0,
    this.digitalRevenue = 0,
    int? totalOrders,
    int? totalCompletedOrders,
    this.averageOrderValue = 0,
    this.ordersByStatus = const {},
    this.revenueByPaymentMethod = const {},
    this.ordersByPaymentStatus = const {},
    this.revenueByChannel = const {},
    this.ordersByChannel = const {},
    this.from,
    this.to,
  }) : totalRevenue = totalRevenue ?? netRevenue ?? grossRevenue,
       netRevenue = netRevenue ?? totalRevenue ?? grossRevenue,
       totalOrders = totalOrders ?? totalCompletedOrders ?? 0;

  int get totalCompletedOrders => totalOrders;

  factory FinancialSummary.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic val) {
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    Map<String, int> toIntMap(dynamic val) {
      if (val is! Map) return {};
      return val.map((k, v) => MapEntry(k.toString(), toInt(v)));
    }

    final totalRev = toInt(json['total_revenue']);
    final grossRev = json['gross_revenue'] != null
        ? toInt(json['gross_revenue'])
        : totalRev;
    final discount = toInt(json['total_discount']);
    final netRev = json['net_revenue'] != null
        ? toInt(json['net_revenue'])
        : totalRev;

    final payMethodMap = toIntMap(json['revenue_by_payment_method']);
    final cashRev = json['cash_revenue'] != null
        ? toInt(json['cash_revenue'])
        : (payMethodMap['CASH'] ?? 0);
    final digitalRev = json['digital_revenue'] != null
        ? toInt(json['digital_revenue'])
        : (payMethodMap['QRIS'] ?? payMethodMap['MIDTRANS_QRIS'] ?? 0);

    return FinancialSummary(
      totalRevenue: totalRev,
      grossRevenue: grossRev,
      totalDiscount: discount,
      netRevenue: netRev,
      cashRevenue: cashRev,
      digitalRevenue: digitalRev,
      totalOrders: toInt(json['total_orders']),
      averageOrderValue: toInt(json['average_order_value']),
      ordersByStatus: toIntMap(json['orders_by_status']),
      revenueByPaymentMethod: payMethodMap,
      ordersByPaymentStatus: toIntMap(json['orders_by_payment_status']),
      revenueByChannel: toIntMap(json['revenue_by_channel']),
      ordersByChannel: toIntMap(json['orders_by_channel']),
      from: json['from'] != null
          ? DateTime.tryParse(json['from'].toString())
          : null,
      to: json['to'] != null ? DateTime.tryParse(json['to'].toString()) : null,
    );
  }

  factory FinancialSummary.empty() {
    return const FinancialSummary(
      totalRevenue: 0,
      grossRevenue: 0,
      totalDiscount: 0,
      netRevenue: 0,
      cashRevenue: 0,
      digitalRevenue: 0,
      totalOrders: 0,
      averageOrderValue: 0,
      ordersByStatus: {},
      revenueByPaymentMethod: {},
      ordersByPaymentStatus: {},
      revenueByChannel: {},
      ordersByChannel: {},
    );
  }

  double get cashRatio {
    final total = cashRevenue + digitalRevenue;
    if (total <= 0) return 0.0;
    return cashRevenue / total;
  }

  double get digitalRatio {
    final total = cashRevenue + digitalRevenue;
    if (total <= 0) return 0.0;
    return digitalRevenue / total;
  }

  String get formattedNetRevenue => CurrencyFormatter.formatRupiah(netRevenue);
  String get formattedGrossRevenue =>
      CurrencyFormatter.formatRupiah(grossRevenue);
  String get formattedTotalDiscount =>
      CurrencyFormatter.formatRupiah(totalDiscount);
  String get formattedCashRevenue =>
      CurrencyFormatter.formatRupiah(cashRevenue);
  String get formattedDigitalRevenue =>
      CurrencyFormatter.formatRupiah(digitalRevenue);
  String get formattedAverageOrderValue =>
      CurrencyFormatter.formatRupiah(averageOrderValue);
}
