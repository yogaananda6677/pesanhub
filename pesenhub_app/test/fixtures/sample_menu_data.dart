import 'package:pesenhub_app/menu/models/menu_category.dart';
import 'package:pesenhub_app/menu/models/menu_item.dart';
import 'package:pesenhub_app/menu/models/menu_modifier_group.dart';
import 'package:pesenhub_app/menu/models/menu_option.dart';

/// Test-only menu fixture. It is never loaded by the application runtime.
abstract final class SampleMenuData {
  static const List<MenuCategory> sampleCategories = [
    MenuCategory(id: 'cat-makanan', name: 'Makanan', sortOrder: 0),
    MenuCategory(id: 'cat-minuman', name: 'Minuman', sortOrder: 1),
    MenuCategory(id: 'cat-tambahan', name: 'Tambahan', sortOrder: 2),
  ];

  static const MenuModifierGroup spiceLevelGroup = MenuModifierGroup(
    id: 'grp-spice',
    code: 'spice_level',
    name: 'Level Kepedasan',
    minSelect: 1,
    maxSelect: 1,
    sortOrder: 0,
    options: [
      MenuOption(
        id: 'opt-lvl-0',
        code: 'lvl_0',
        name: 'Level 0 (Tidak Pedas)',
        priceDeltaAmount: 0,
      ),
      MenuOption(
        id: 'opt-lvl-1',
        code: 'lvl_1',
        name: 'Level 1 (Sedang)',
        priceDeltaAmount: 0,
      ),
      MenuOption(
        id: 'opt-lvl-2',
        code: 'lvl_2',
        name: 'Level 2 (Pedas)',
        priceDeltaAmount: 0,
      ),
      MenuOption(
        id: 'opt-lvl-3',
        code: 'lvl_3',
        name: 'Level 3 (Ekstra Pedas)',
        priceDeltaAmount: 0,
      ),
      MenuOption(
        id: 'opt-lvl-4',
        code: 'lvl_4',
        name: 'Level 4 (Super Pedas)',
        priceDeltaAmount: 0,
      ),
      MenuOption(
        id: 'opt-lvl-5',
        code: 'lvl_5',
        name: 'Level 5 (Pedas Mampus)',
        priceDeltaAmount: 0,
      ),
    ],
  );

  static const MenuModifierGroup toppingGroup = MenuModifierGroup(
    id: 'grp-topping',
    code: 'toppings',
    name: 'Topping Tambahan',
    minSelect: 0,
    maxSelect: 3,
    sortOrder: 1,
    options: [
      MenuOption(
        id: 'opt-telur-bebek',
        code: 'ceplok',
        name: 'Telur Bebek Ekstra',
        priceDeltaAmount: 4000,
      ),
      MenuOption(
        id: 'opt-daging-sapi',
        code: 'dadar',
        name: 'Daging Sapi Ekstra',
        priceDeltaAmount: 4000,
      ),
      MenuOption(
        id: 'opt-sosis',
        code: 'sosis',
        name: 'Sosis Sapi',
        priceDeltaAmount: 3000,
      ),
      MenuOption(
        id: 'opt-keju',
        code: 'bakso',
        name: 'Keju Mozzarella',
        priceDeltaAmount: 3000,
      ),
      MenuOption(
        id: 'opt-acar-ekstra',
        code: 'teri',
        name: 'Acar Ekstra (Habis)',
        priceDeltaAmount: 4000,
        isAvailable: false,
      ),
    ],
  );

  static const MenuModifierGroup sugarGroup = MenuModifierGroup(
    id: 'grp-sugar',
    code: 'sugar_level',
    name: 'Pilihan Manis',
    minSelect: 1,
    maxSelect: 1,
    sortOrder: 0,
    options: [
      MenuOption(
        id: 'opt-sug-normal',
        code: 'sug_normal',
        name: 'Normal',
        priceDeltaAmount: 0,
      ),
      MenuOption(
        id: 'opt-sug-less',
        code: 'sug_less',
        name: 'Less Sugar',
        priceDeltaAmount: 0,
      ),
      MenuOption(
        id: 'opt-sug-zero',
        code: 'sug_zero',
        name: 'Tanpa Gula',
        priceDeltaAmount: 0,
      ),
    ],
  );

  static List<MenuItem> get sampleMenus => [
    const MenuItem(
      id: 'm-nasgor-spesial',
      categoryId: 'cat-makanan',
      sku: 'MAR-SPESIAL',
      name: 'Martabak Telur Spesial',
      description:
          'Martabak telur gurih renyah dengan isian daging sapi cincang, daun bawang segar, dan kuah cuka mantap.',
      priceAmount: 25000,
      isAvailable: true,
      modifierGroups: [spiceLevelGroup, toppingGroup],
    ),
    const MenuItem(
      id: 'm-nasgor-gila',
      categoryId: 'cat-makanan',
      sku: 'MAR-BEBEK',
      name: 'Martabak Telur Bebek',
      description:
          'Martabak gurih spesial menggunakan telur bebek premium dengan kulit ekstra renyah.',
      priceAmount: 28000,
      isAvailable: true,
      modifierGroups: [spiceLevelGroup, toppingGroup],
    ),
    const MenuItem(
      id: 'm-nasgor-seafood',
      categoryId: 'cat-makanan',
      sku: 'TER-TOBLERONE',
      name: 'Terang Bulan Toblerone Keju',
      description:
          'Terang bulan lembut bersarang dengan cokelat Toblerone premium dan taburan keju melimpah.',
      priceAmount: 32000,
      isAvailable: false, // Criteria #2: unavailable item
      modifierGroups: [spiceLevelGroup],
    ),
    const MenuItem(
      id: 'm-es-teh',
      categoryId: 'cat-minuman',
      sku: 'MIN-ESTEH',
      name: 'Es Teh Manis',
      description: 'Teh melati wangi segar disajikan dingin.',
      priceAmount: 5000,
      isAvailable: true,
      isDrink: true,
      modifierGroups: [sugarGroup],
    ),
    const MenuItem(
      id: 'm-es-jeruk',
      categoryId: 'cat-minuman',
      sku: 'MIN-ESJERUK',
      name: 'Es Jeruk Peras',
      description: 'Jeruk peras murni segar kaya vitamin C.',
      priceAmount: 8000,
      isAvailable: true,
      isDrink: true,
    ),
    const MenuItem(
      id: 'm-kerupuk',
      categoryId: 'cat-tambahan',
      sku: 'TAMB-ACAR',
      name: 'Acar & Kuah Cuka Ekstra',
      description: 'Acar mentimun segar dan kuah cuka asam manis gurih.',
      priceAmount: 2000,
      isAvailable: true,
    ),
  ];
}
