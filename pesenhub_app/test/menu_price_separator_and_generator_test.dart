import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesenhub_app/core/utils/currency_formatter.dart';
import 'package:pesenhub_app/menu/controllers/menu_availability_controller.dart';
import 'package:pesenhub_app/menu/models/menu_item.dart';
import 'package:pesenhub_app/menu/widgets/catalog_editor_dialog.dart';
import 'package:pesenhub_app/menu/widgets/menu_availability_card.dart';
import 'package:pesenhub_app/menu/widgets/menu_item_card.dart';
import 'package:pesenhub_app/theme/app_theme.dart';

void main() {
  group('CurrencyFormatter Unit Tests', () {
    test(
      'formatRupiah formats whole numbers with Indonesian thousands dots',
      () {
        expect(CurrencyFormatter.formatRupiah(20000), equals('Rp 20.000'));
        expect(CurrencyFormatter.formatRupiah(0), equals('Rp 0'));
        expect(CurrencyFormatter.formatRupiah(500), equals('Rp 500'));
        expect(CurrencyFormatter.formatRupiah(1000000), equals('Rp 1.000.000'));
        expect(CurrencyFormatter.formatRupiah(null), equals('Rp 0'));
        expect(CurrencyFormatter.formatRupiah(-20000), equals('-Rp 20.000'));
      },
    );

    test(
      'formatThousands formats numbers with dots without currency prefix',
      () {
        expect(CurrencyFormatter.formatThousands(20000), equals('20.000'));
        expect(CurrencyFormatter.formatThousands(0), equals('0'));
        expect(CurrencyFormatter.formatThousands(1500000), equals('1.500.000'));
        expect(CurrencyFormatter.formatThousands(null), equals('0'));
      },
    );

    test(
      'parseThousands parses dot-separated and raw strings to pure integers',
      () {
        expect(CurrencyFormatter.parseThousands('20.000'), equals(20000));
        expect(CurrencyFormatter.parseThousands(' 20.000 '), equals(20000));
        expect(CurrencyFormatter.parseThousands('20000'), equals(20000));
        expect(CurrencyFormatter.parseThousands('1.500.000'), equals(1500000));
        expect(CurrencyFormatter.parseThousands('0'), equals(0));
        expect(CurrencyFormatter.parseThousands(''), isNull);
        expect(CurrencyFormatter.parseThousands('   '), isNull);
        expect(CurrencyFormatter.parseThousands(null), isNull);
        expect(CurrencyFormatter.parseThousands('abc'), isNull);
      },
    );

    test(
      'calculateOnlinePrice follows Yoga formula with exact whole rupiah rounding',
      () {
        // Prompt example: OFFLINE 20.000 with 20% markup -> 24.000
        expect(
          CurrencyFormatter.calculateOnlinePrice(20000, 20),
          equals(24000),
        );

        // 10.000 with 15% markup -> 11.500
        expect(
          CurrencyFormatter.calculateOnlinePrice(10000, 15),
          equals(11500),
        );

        // Non-multiple test: 12.345 with 15% markup
        // 12345 + round(12345 * 0.15) = 12345 + round(1851.75) = 12345 + 1852 = 14197
        // Must NOT be rounded to nearest 500 or 1000!
        expect(
          CurrencyFormatter.calculateOnlinePrice(12345, 15),
          equals(14197),
        );

        // 0% markup
        expect(CurrencyFormatter.calculateOnlinePrice(20000, 0), equals(20000));

        // 0 or negative offline price
        expect(CurrencyFormatter.calculateOnlinePrice(0, 20), equals(0));
        expect(CurrencyFormatter.calculateOnlinePrice(-1000, 20), equals(0));
      },
    );
  });

  group('ThousandsSeparatorInputFormatter Tests', () {
    const formatter = ThousandsSeparatorInputFormatter();

    test('formats numbers as user types', () {
      var value = const TextEditingValue(text: '');

      // Type 2
      value = formatter.formatEditUpdate(
        value,
        const TextEditingValue(
          text: '2',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      expect(value.text, equals('2'));
      expect(value.selection.end, equals(1));

      // Type 0 -> 20
      value = formatter.formatEditUpdate(
        value,
        const TextEditingValue(
          text: '20',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(value.text, equals('20'));
      expect(value.selection.end, equals(2));

      // Type 0 -> 200
      value = formatter.formatEditUpdate(
        value,
        const TextEditingValue(
          text: '200',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(value.text, equals('200'));
      expect(value.selection.end, equals(3));

      // Type 0 -> 2.000
      value = formatter.formatEditUpdate(
        value,
        const TextEditingValue(
          text: '2000',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      expect(value.text, equals('2.000'));
      expect(value.selection.end, equals(5));

      // Type 0 -> 20.000
      value = formatter.formatEditUpdate(
        value,
        const TextEditingValue(
          text: '2.0000',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      expect(value.text, equals('20.000'));
      expect(value.selection.end, equals(6));
    });

    test('handles backspace over thousand dot smoothly', () {
      // Current text is '20.000', cursor at index 3 (right after the dot: '20.|000')
      const oldValue = TextEditingValue(
        text: '20.000',
        selection: TextSelection.collapsed(offset: 3),
      );
      // User presses backspace -> in standard textfield, dot is deleted: '20|000' (offset 2)
      const newValue = TextEditingValue(
        text: '20000',
        selection: TextSelection.collapsed(offset: 2),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);
      // Formatter should delete the digit before the dot ('0') yielding '2.000'
      expect(result.text, equals('2.000'));
    });

    test('handles pasted values with mixed separators', () {
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(
        text: '25,000',
        selection: TextSelection.collapsed(offset: 6),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, equals('25.000'));
      expect(result.selection.end, equals(6));
    });
  });

  group('MenuAvailabilityCard & MenuItemCard Price Display Tests', () {
    const testItem = MenuItem(
      id: 'menu-test-1',
      categoryId: 'cat-1',
      sku: 'SKU-001',
      name: 'Martabak Spesial',
      priceAmount: 20000,
      hppAmount: 12000,
      channelPrices: {
        'OFFLINE': 20000,
        'GOFOOD': 24000,
        'GRABFOOD': 24000,
        'SHOPEEFOOD': 24000,
      },
    );

    testWidgets(
      'MenuAvailabilityCard renders price with thousands dot and formatted chips',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MenuAvailabilityCard(
                item: testItem,
                categoryName: 'Martabak',
                isStaff: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Main price uses Indonesian Rupiah format
        expect(find.text('Rp 20.000'), findsOneWidget);

        // Price chips use Indonesian Rupiah format
        expect(find.text('HPP · Rp 12.000'), findsOneWidget);
        expect(find.text('OFFLINE · Rp 20.000'), findsOneWidget);
        expect(find.text('GOFOOD · Rp 24.000'), findsOneWidget);
        expect(find.text('GRABFOOD · Rp 24.000'), findsOneWidget);
        expect(find.text('SHOPEEFOOD · Rp 24.000'), findsOneWidget);
      },
    );

    testWidgets(
      'MenuItemCard in POS menu list renders price with thousands dot',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: MenuItemCard(item: testItem, categoryName: 'Martabak'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Rp 20.000'), findsOneWidget);
      },
    );
  });

  group('CatalogEditorDialog _PriceEditor & Online Price Generator Tests', () {
    const testMenu = MenuItem(
      id: 'menu-edit-1',
      categoryId: 'cat-1',
      sku: 'SKU-001',
      name: 'Terang Bulan Spesial',
      priceAmount: 20000,
      hppAmount: 10000,
      channelPrices: {
        'OFFLINE': 20000,
        'GOFOOD': 22000,
        'GRABFOOD': 22000,
        'SHOPEEFOOD': 22000,
      },
    );

    testWidgets('displays initial prices with thousands separator', (
      tester,
    ) async {
      final controller = MenuAvailabilityController(
        initialCategories: const [],
        initialMenus: const [testMenu],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showPriceEditor(
                  context,
                  controller: controller,
                  menu: testMenu,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit harga · Terang Bulan Spesial'), findsOneWidget);
      // HPP is 10.000
      expect(find.text('10.000'), findsOneWidget);
      // OFFLINE is 20.000
      expect(find.text('20.000'), findsOneWidget);
      // Online channels are 22.000
      expect(find.text('22.000'), findsNWidgets(3));
      // Default markup percentage is 20
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets(
      'Generate Harga Online computes 20% markup (Rp 20.000 -> Rp 24.000) and allows independent manual edits',
      (tester) async {
        MenuItem? savedMenu;
        final controller = MenuAvailabilityController(
          initialCategories: const [],
          initialMenus: const [testMenu],
          updateMenuFn: (menu) async {
            savedMenu = menu;
            return menu;
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showPriceEditor(
                    context,
                    controller: controller,
                    menu: testMenu,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Tap "Generate Harga Online" button
        final generateBtn = find.byKey(
          const Key('generate-online-prices-button'),
        );
        expect(generateBtn, findsOneWidget);
        await tester.tap(generateBtn);
        await tester.pumpAndSettle();

        // GOFOOD, GRABFOOD, and SHOPEEFOOD are now 24.000
        expect(find.text('24.000'), findsNWidgets(3));

        // Manually edit GoFood to 25.000 while GrabFood and ShopeeFood remain 24.000
        final gofoodField = find.byKey(const Key('menu-gofood-price-field'));
        await tester.enterText(gofoodField, '25000');
        await tester.pumpAndSettle();

        expect(find.text('25.000'), findsOneWidget);
        expect(
          find.text('24.000'),
          findsNWidgets(2),
        ); // GrabFood and ShopeeFood

        // Tap "Simpan harga"
        final saveBtn = find.byKey(const Key('save-price-button'));
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Verify savedMenu has pure integer values
        expect(savedMenu, isNotNull);
        expect(savedMenu!.hppAmount, equals(10000));
        expect(savedMenu!.priceAmount, equals(20000));
        expect(
          savedMenu!.channelPrices,
          equals({
            'OFFLINE': 20000,
            'GOFOOD': 25000,
            'GRABFOOD': 24000,
            'SHOPEEFOOD': 24000,
          }),
        );
      },
    );

    testWidgets(
      'validation error shown when offline price is cleared or invalid',
      (tester) async {
        final controller = MenuAvailabilityController(
          initialCategories: const [],
          initialMenus: const [testMenu],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showPriceEditor(
                    context,
                    controller: controller,
                    menu: testMenu,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Clear OFFLINE price
        final offlineField = find.byKey(const Key('menu-offline-price-field'));
        await tester.enterText(offlineField, '');
        await tester.pumpAndSettle();

        // Click generate
        await tester.tap(
          find.byKey(const Key('generate-online-prices-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Harga OFFLINE wajib diisi dengan benar sebelum generate harga online.',
          ),
          findsOneWidget,
        );

        // Click save with empty offline price
        await tester.tap(find.byKey(const Key('save-price-button')));
        await tester.pumpAndSettle();

        expect(
          find.text('HPP dan seluruh harga channel wajib diisi.'),
          findsOneWidget,
        );
      },
    );
  });
}
