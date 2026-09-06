/// MenuCategory represents a category group (e.g. Makanan, Minuman, Tambahan).
class MenuCategory {
  final String id;
  final String name;
  final int sortOrder;
  final bool isActive;
  final int version;

  const MenuCategory({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.isActive = true,
    this.version = 1,
  });

  MenuCategory copyWith({
    String? id,
    String? name,
    int? sortOrder,
    bool? isActive,
    int? version,
  }) => MenuCategory(
    id: id ?? this.id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    isActive: isActive ?? this.isActive,
    version: version ?? this.version,
  );
}
