import '../../menu/models/menu_category.dart';
import '../../menu/models/menu_item.dart';

class RemoteCatalog {
  final List<MenuCategory> categories;
  final List<MenuItem> menus;

  const RemoteCatalog({required this.categories, required this.menus});
}

abstract class CatalogRemoteGateway {
  Future<RemoteCatalog> fetchAdminCatalog();
  Future<MenuCategory> createCategory(MenuCategory category);
  Future<MenuCategory> updateCategory(MenuCategory category);
  Future<MenuItem> createMenu(MenuItem menu);
  Future<MenuItem> updateMenu(MenuItem menu);
  Future<MenuItem> updateMenuAvailability(
    String id,
    bool available,
    int expectedVersion,
  );
}
