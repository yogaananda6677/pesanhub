class Discount {
  final String id;
  final String name;
  final String? code;
  final String scope; // 'ORDER' | 'ITEM'
  final String
  channel; // 'ALL' | 'OFFLINE' | 'GOFOOD' | 'GRABFOOD' | 'SHOPEEFOOD' | 'WHATSAPP' | 'CUSTOMER_WEB'
  final String type; // 'PERCENTAGE' | 'FIXED'
  final int value;
  final int? maxDiscountAmount;
  final int minOrderAmount;
  final String? branchId;
  final String? branchName;
  final bool isActive;
  final List<String> menuIds;
  final int version;

  const Discount({
    required this.id,
    required this.name,
    this.code,
    required this.scope,
    required this.channel,
    required this.type,
    required this.value,
    this.maxDiscountAmount,
    this.minOrderAmount = 0,
    this.branchId,
    this.branchName,
    this.isActive = true,
    this.menuIds = const [],
    this.version = 1,
  });

  bool get isPercentage => type == 'PERCENTAGE';
  bool get isFixed => type == 'FIXED';
  bool get isItemScope => scope == 'ITEM';
  bool get isOrderScope => scope == 'ORDER';

  String get scopeLabel => isItemScope ? 'Diskon Menu' : 'Diskon Total';

  String get channelLabel {
    switch (channel.toUpperCase()) {
      case 'ALL':
        return 'Semua Kanal';
      case 'OFFLINE':
      case 'CASHIER_MANUAL':
        return 'Kasir Offline';
      case 'GOFOOD':
        return 'GoFood';
      case 'GRABFOOD':
        return 'GrabFood';
      case 'SHOPEEFOOD':
        return 'ShopeeFood';
      case 'WHATSAPP':
      case 'WHATSAPP_BOT':
        return 'WhatsApp';
      case 'CUSTOMER_WEB':
        return 'Web Order';
      default:
        return channel;
    }
  }

  String get formattedValue {
    if (isPercentage) {
      if (maxDiscountAmount != null && maxDiscountAmount! > 0) {
        return '$value% (Maks Rp ${_formatRupiah(maxDiscountAmount!)})';
      }
      return '$value%';
    }
    return 'Rp ${_formatRupiah(value)}';
  }

  /// Calculates discount amount given current order subtotal, items (id -> lineTotal), and order source.
  int calculateDiscountAmount({
    required int subtotal,
    required Map<String, int> itemLineTotals, // menuId -> lineTotal
    String? orderSource,
  }) {
    if (!isActive) return 0;
    if (subtotal < minOrderAmount) return 0;

    // Channel check
    if (orderSource != null && !matchesChannel(orderSource)) {
      return 0;
    }

    int computed = 0;
    if (isItemScope) {
      final menuSet = menuIds.toSet();
      int eligibleSubtotal = 0;
      itemLineTotals.forEach((menuId, lineTotal) {
        if (menuSet.contains(menuId)) {
          eligibleSubtotal += lineTotal;
        }
      });

      if (eligibleSubtotal <= 0) return 0;

      if (isPercentage) {
        computed = (eligibleSubtotal * value) ~/ 100;
        if (maxDiscountAmount != null &&
            maxDiscountAmount! > 0 &&
            computed > maxDiscountAmount!) {
          computed = maxDiscountAmount!;
        }
      } else {
        computed = value > eligibleSubtotal ? eligibleSubtotal : value;
      }
    } else {
      // Order scope
      if (isPercentage) {
        computed = (subtotal * value) ~/ 100;
        if (maxDiscountAmount != null &&
            maxDiscountAmount! > 0 &&
            computed > maxDiscountAmount!) {
          computed = maxDiscountAmount!;
        }
      } else {
        computed = value;
      }
    }

    if (computed > subtotal) {
      computed = subtotal;
    }
    return computed < 0 ? 0 : computed;
  }

  bool matchesChannel(String source) {
    final c = channel.toUpperCase();
    if (c == 'ALL' || c.isEmpty) return true;
    final s = source.toUpperCase();
    if (s == 'CASHIER_MANUAL' || s == 'OFFLINE') return c == 'OFFLINE';
    if (s == 'WHATSAPP' || s == 'WHATSAPP_BOT') return c == 'WHATSAPP';
    if (s == 'CUSTOMER_WEB') return c == 'CUSTOMER_WEB';
    return c == s;
  }

  factory Discount.fromJson(Map<String, dynamic> json) {
    return Discount(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String?,
      scope: (json['scope'] as String? ?? 'ORDER').toUpperCase(),
      channel: (json['channel'] as String? ?? 'ALL').toUpperCase(),
      type: (json['type'] as String? ?? 'PERCENTAGE').toUpperCase(),
      value: (json['value'] as num?)?.toInt() ?? 0,
      maxDiscountAmount: (json['max_discount_amount'] as num?)?.toInt(),
      minOrderAmount: (json['min_order_amount'] as num?)?.toInt() ?? 0,
      branchId: json['branch_id'] as String?,
      branchName: json['branch_name'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      menuIds:
          (json['menu_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  Discount copyWith({
    String? id,
    String? name,
    String? code,
    String? scope,
    String? channel,
    String? type,
    int? value,
    int? maxDiscountAmount,
    int? minOrderAmount,
    String? branchId,
    String? branchName,
    bool? isActive,
    List<String>? menuIds,
    int? version,
  }) {
    return Discount(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      scope: scope ?? this.scope,
      channel: channel ?? this.channel,
      type: type ?? this.type,
      value: value ?? this.value,
      maxDiscountAmount: maxDiscountAmount ?? this.maxDiscountAmount,
      minOrderAmount: minOrderAmount ?? this.minOrderAmount,
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      isActive: isActive ?? this.isActive,
      menuIds: menuIds ?? this.menuIds,
      version: version ?? this.version,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (code != null && code!.isNotEmpty) 'code': code,
      'scope': scope,
      'channel': channel,
      'type': type,
      'value': value,
      if (maxDiscountAmount != null && maxDiscountAmount! > 0)
        'max_discount_amount': maxDiscountAmount,
      'min_order_amount': minOrderAmount,
      if (branchId != null && branchId!.isNotEmpty) 'branch_id': branchId,
      'is_active': isActive,
      if (isItemScope) 'menu_ids': menuIds,
      if (version > 0) 'expected_version': version,
    };
  }

  static String _formatRupiah(int amount) {
    final str = amount.toString();
    final chars = str.split('').reversed.toList();
    final formatted = <String>[];
    for (int i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) {
        formatted.add('.');
      }
      formatted.add(chars[i]);
    }
    return formatted.reversed.join();
  }
}
