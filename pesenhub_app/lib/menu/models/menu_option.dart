/// MenuOption represents a single modifier choice (e.g. "Level 3", "Telur Ceplok").
/// Conforms to pesenhub_be/internal/catalog Option schema.
class MenuOption {
  final String id;
  final String code;
  final String name;
  final int priceDeltaAmount;
  final bool isAvailable;
  final int sortOrder;

  const MenuOption({
    required this.id,
    required this.code,
    required this.name,
    this.priceDeltaAmount = 0,
    this.isAvailable = true,
    this.sortOrder = 0,
  });
}
