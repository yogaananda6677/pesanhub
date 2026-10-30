import '../../core/utils/currency_formatter.dart';

class TopProduct {
  final String name;
  final int quantity;
  final int totalRevenue;

  const TopProduct({
    required this.name,
    int? quantity,
    int? quantitySold,
    int? totalRevenue,
    int? totalSales,
  }) : quantity = quantity ?? quantitySold ?? 0,
       totalRevenue = totalRevenue ?? totalSales ?? 0;

  int get quantitySold => quantity;
  int get totalSales => totalRevenue;

  factory TopProduct.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic val) {
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    return TopProduct(
      name: (json['name'] ?? 'Item').toString(),
      quantity: toInt(json['quantity'] ?? json['quantity_sold']),
      totalRevenue: toInt(json['total_revenue'] ?? json['total_sales']),
    );
  }

  String get formattedRevenue => CurrencyFormatter.formatRupiah(totalRevenue);
}

class TopProductsResponse {
  final List<TopProduct> topProducts;
  final List<TopProduct> topToppings;

  const TopProductsResponse({
    List<TopProduct>? topProducts,
    List<TopProduct>? topMenus,
    required this.topToppings,
  }) : topProducts = topProducts ?? topMenus ?? const [];

  List<TopProduct> get topMenus => topProducts;

  factory TopProductsResponse.fromJson(Map<String, dynamic> json) {
    final products = <TopProduct>[];
    if (json['top_products'] is List) {
      for (final item in json['top_products'] as List) {
        if (item is Map) {
          products.add(TopProduct.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final toppings = <TopProduct>[];
    if (json['top_toppings'] is List) {
      for (final item in json['top_toppings'] as List) {
        if (item is Map) {
          toppings.add(TopProduct.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return TopProductsResponse(topProducts: products, topToppings: toppings);
  }

  factory TopProductsResponse.empty() {
    return const TopProductsResponse(topProducts: [], topToppings: []);
  }
}
