import '../../menu/models/menu_category.dart';
import '../../menu/models/menu_item.dart';
import '../../menu/models/menu_modifier_group.dart';
import '../../menu/models/menu_option.dart';
import 'catalog_gateway.dart';

RemoteCatalog decodeCatalog(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is! List) throw const FormatException('invalid catalog data');
  final categories = <MenuCategory>[];
  final menus = <MenuItem>[];
  for (final raw in data) {
    if (raw is! Map) throw const FormatException('invalid category');
    final category = decodeCategory(Map<String, dynamic>.from(raw));
    categories.add(category);
    final rawMenus = raw['menus'];
    if (rawMenus is! List) throw const FormatException('invalid menus');
    for (final menu in rawMenus) {
      if (menu is! Map) throw const FormatException('invalid menu');
      menus.add(decodeMenu(Map<String, dynamic>.from(menu)));
    }
  }
  return RemoteCatalog(categories: categories, menus: menus);
}

MenuCategory decodeCategory(Map<String, dynamic> json) => MenuCategory(
  id: _string(json, 'id'),
  name: _string(json, 'name'),
  sortOrder: _integer(json, 'sort_order', minimum: 0),
  isActive: _boolean(json, 'is_active'),
  version: _integer(json, 'version', minimum: 1),
);

MenuItem decodeMenu(Map<String, dynamic> json) {
  final rawGroups = json['modifier_groups'];
  if (rawGroups != null && rawGroups is! List) {
    throw const FormatException('invalid modifier groups');
  }
  return MenuItem(
    id: _string(json, 'id'),
    categoryId: _string(json, 'category_id'),
    sku: _string(json, 'sku'),
    name: _string(json, 'name'),
    description: json['description'] as String?,
    priceAmount: _integer(json, 'price_amount', minimum: 0),
    isAvailable: _boolean(json, 'is_available'),
    version: _integer(json, 'version', minimum: 1),
    sortOrder: _integer(json, 'sort_order', minimum: 0),
    modifierGroups: (rawGroups as List? ?? const [])
        .map((raw) => _decodeGroup(Map<String, dynamic>.from(raw as Map)))
        .toList(growable: false),
  );
}

MenuModifierGroup _decodeGroup(Map<String, dynamic> json) {
  final options = json['options'];
  if (options is! List) throw const FormatException('invalid options');
  return MenuModifierGroup(
    id: _string(json, 'id'),
    code: _string(json, 'code'),
    name: _string(json, 'name'),
    minSelect: _integer(json, 'min_select', minimum: 0),
    maxSelect: _integer(json, 'max_select', minimum: 1),
    isActive: _boolean(json, 'is_active'),
    sortOrder: _integer(json, 'sort_order', minimum: 0),
    options: options
        .map((raw) => _decodeOption(Map<String, dynamic>.from(raw as Map)))
        .toList(growable: false),
  );
}

MenuOption _decodeOption(Map<String, dynamic> json) => MenuOption(
  id: _string(json, 'id'),
  code: _string(json, 'code'),
  name: _string(json, 'name'),
  priceDeltaAmount: _integer(json, 'price_delta_amount'),
  isAvailable: _boolean(json, 'is_available'),
  sortOrder: _integer(json, 'sort_order', minimum: 0),
);

Map<String, dynamic> encodeCategory(MenuCategory category) => {
  'name': category.name,
  'sort_order': category.sortOrder,
  'is_active': category.isActive,
  'version': category.version,
};

Map<String, dynamic> encodeMenu(MenuItem menu) => {
  'category_id': menu.categoryId,
  'sku': menu.sku,
  'name': menu.name,
  if (menu.description != null) 'description': menu.description,
  'price_amount': menu.priceAmount,
  'sort_order': menu.sortOrder,
  'version': menu.version,
  'modifier_groups': menu.modifierGroups
      .map(
        (group) => {
          'code': group.code,
          'name': group.name,
          'min_select': group.minSelect,
          'max_select': group.maxSelect,
          'sort_order': group.sortOrder,
          'options': group.options
              .map(
                (option) => {
                  'code': option.code,
                  'name': option.name,
                  'price_delta_amount': option.priceDeltaAmount,
                  'sort_order': option.sortOrder,
                },
              )
              .toList(),
        },
      )
      .toList(),
};

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('invalid $key');
  }
  return value;
}

int _integer(Map<String, dynamic> json, String key, {int? minimum}) {
  final value = json[key];
  if (value is! int || (minimum != null && value < minimum)) {
    throw FormatException('invalid $key');
  }
  return value;
}

bool _boolean(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('invalid $key');
  return value;
}
