/// MenuCategory represents a category group (e.g. Makanan, Minuman, Tambahan).
class MenuCategory {
  final String id;
  final String name;
  final int sortOrder;
  final bool isActive;

  const MenuCategory({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.isActive = true,
  });
}
