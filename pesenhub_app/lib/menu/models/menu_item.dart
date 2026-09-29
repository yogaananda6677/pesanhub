import 'menu_modifier_group.dart';

/// MenuItem represents a catalog menu offering.
/// Conforms to pesenhub_be/internal/catalog Menu schema.
class MenuItem {
  final String id;
  final String categoryId;
  final String sku;
  final String name;
  final String? description;
  final String productType;
  final String? imageUrl;

  /// Device-local file populated by the catalog image synchronization worker.
  final String? localImagePath;
  final int priceAmount;
  final int? hppAmount;
  final Map<String, int> channelPrices;
  final bool isAvailable;
  final int version;
  final int sortOrder;
  final List<MenuModifierGroup> modifierGroups;
  final bool isDrink;

  const MenuItem({
    required this.id,
    required this.categoryId,
    required this.sku,
    required this.name,
    this.description,
    this.productType = 'MARTABAK_TELUR',
    this.imageUrl,
    this.localImagePath,
    required this.priceAmount,
    this.hppAmount,
    this.channelPrices = const {},
    this.isAvailable = true,
    this.version = 1,
    this.sortOrder = 0,
    this.modifierGroups = const [],
    this.isDrink = false,
  });

  /// True if item has customizable modifier groups.
  bool get hasModifiers => modifierGroups.isNotEmpty;

  int? priceForChannel(String channel) => channelPrices[channel.toUpperCase()];

  /// True if item has spice level modifier group.
  bool get hasSpiceLevel =>
      modifierGroups.any((g) => g.code == 'spice_level' && g.isActive);

  /// Returns active modifier groups.
  List<MenuModifierGroup> get activeModifierGroups =>
      modifierGroups.where((g) => g.isActive).toList();

  MenuItem copyWith({
    String? id,
    String? categoryId,
    String? sku,
    String? name,
    String? description,
    String? productType,
    String? imageUrl,
    String? localImagePath,
    int? priceAmount,
    int? hppAmount,
    Map<String, int>? channelPrices,
    bool? isAvailable,
    int? version,
    int? sortOrder,
    List<MenuModifierGroup>? modifierGroups,
    bool? isDrink,
  }) {
    return MenuItem(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      description: description ?? this.description,
      productType: productType ?? this.productType,
      imageUrl: imageUrl ?? this.imageUrl,
      localImagePath: localImagePath ?? this.localImagePath,
      priceAmount: priceAmount ?? this.priceAmount,
      hppAmount: hppAmount ?? this.hppAmount,
      channelPrices: channelPrices ?? this.channelPrices,
      isAvailable: isAvailable ?? this.isAvailable,
      version: version ?? this.version,
      sortOrder: sortOrder ?? this.sortOrder,
      modifierGroups: modifierGroups ?? this.modifierGroups,
      isDrink: isDrink ?? this.isDrink,
    );
  }
}
