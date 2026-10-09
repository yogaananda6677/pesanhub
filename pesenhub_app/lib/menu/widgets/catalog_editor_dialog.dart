import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/utils/currency_formatter.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../controllers/menu_availability_controller.dart';
import '../models/menu_category.dart';
import '../models/menu_item.dart';
import '../models/menu_modifier_group.dart';
import '../models/menu_option.dart';

Future<bool?> showCategoryEditor(
  BuildContext context, {
  required MenuAvailabilityController controller,
  MenuCategory? category,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _CategoryEditor(controller: controller, category: category),
  );
}

Future<bool?> showMenuEditor(
  BuildContext context, {
  required MenuAvailabilityController controller,
  MenuItem? menu,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _MenuEditor(controller: controller, menu: menu),
  );
}

Future<bool?> showPriceEditor(
  BuildContext context, {
  required MenuAvailabilityController controller,
  required MenuItem menu,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _PriceEditor(controller: controller, menu: menu),
);

Future<bool?> showGlobalExtraEditor(
  BuildContext context, {
  required MenuAvailabilityController controller,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _GlobalExtraEditor(controller: controller),
);

Future<bool?> showChannelGeneratorDialog(BuildContext context) =>
    showDialog<bool>(
      context: context,
      builder: (_) => const _ChannelGeneratorDialog(),
    );

class _CategoryEditor extends StatefulWidget {
  final MenuAvailabilityController controller;
  final MenuCategory? category;

  const _CategoryEditor({required this.controller, this.category});

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final TextEditingController _name;
  late final TextEditingController _sort;
  late bool _active;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.name);
    _sort = TextEditingController(
      text: (widget.category?.sortOrder ?? 0).toString(),
    );
    _active = widget.category?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _sort.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final sort = int.tryParse(_sort.text.trim());
    if (name.isEmpty || sort == null || sort < 0) {
      setState(() => _error = 'Nama dan urutan kategori wajib valid.');
      return;
    }
    final current = widget.category;
    final result = await widget.controller.saveCategory(
      MenuCategory(
        id: current?.id ?? '',
        name: name,
        sortOrder: sort,
        isActive: _active,
        version: current?.version ?? 1,
      ),
    );
    if (mounted && result) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.category == null ? 'Tambah kategori' : 'Edit kategori',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                key: const Key('category-name-field'),
                label: 'Nama kategori',
                controller: _name,
                errorText: _error,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Urutan',
                controller: _sort,
                keyboardType: TextInputType.number,
              ),
              if (widget.category != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kategori aktif'),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        AppButton(
          label: 'Simpan',
          isLoading: widget.controller.isSaving,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _MenuEditor extends StatefulWidget {
  final MenuAvailabilityController controller;
  final MenuItem? menu;

  const _MenuEditor({required this.controller, this.menu});

  @override
  State<_MenuEditor> createState() => _MenuEditorState();
}

class _MenuEditorState extends State<_MenuEditor> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _description;
  late final TextEditingController _sort;
  late String? _categoryId;
  late String _productType;
  String? _imageUrl;
  bool _uploadingImage = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final menu = widget.menu;
    _name = TextEditingController(text: menu?.name);
    _sku = TextEditingController(text: menu?.sku);
    _description = TextEditingController(text: menu?.description);
    _sort = TextEditingController(text: (menu?.sortOrder ?? 0).toString());
    _productType = menu?.productType ?? 'MARTABAK_TELUR';
    _imageUrl = menu?.imageUrl;
    _categoryId =
        menu?.categoryId ??
        (widget.controller.categories.isEmpty
            ? null
            : widget.controller.categories.first.id);
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _description.dispose();
    _sort.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final sort = int.tryParse(_sort.text.trim());
    if (_categoryId == null ||
        _name.text.trim().isEmpty ||
        _sku.text.trim().isEmpty ||
        sort == null ||
        sort < 0) {
      setState(
        () => _error = 'Kategori, jenis, nama, SKU, dan urutan wajib valid.',
      );
      return;
    }
    final current = widget.menu;
    final offlinePrice =
        current?.channelPrices['OFFLINE'] ?? current?.priceAmount ?? 0;
    final channelPrices = {
      for (final channel in const [
        'OFFLINE',
        'GOFOOD',
        'GRABFOOD',
        'SHOPEEFOOD',
      ])
        channel:
            current?.channelPrices[channel] ??
            (channel == 'OFFLINE' ? offlinePrice : 0),
    };
    final groups =
        current?.modifierGroups
            .where((group) => group.code != 'extra_isian')
            .toList() ??
        <MenuModifierGroup>[];
    final sharedExtra = widget.controller.globalExtraFor(_productType);
    if (sharedExtra != null) groups.add(sharedExtra);
    final saved = await widget.controller.saveMenu(
      MenuItem(
        id: current?.id ?? '',
        categoryId: _categoryId!,
        sku: _sku.text.trim(),
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        productType: _productType,
        imageUrl: _imageUrl,
        priceAmount: offlinePrice,
        hppAmount: current?.hppAmount ?? 0,
        channelPrices: channelPrices,
        isAvailable: current?.isAvailable ?? false,
        version: current?.version ?? 1,
        sortOrder: sort,
        modifierGroups: groups,
      ),
    );
    if (mounted && saved) Navigator.pop(context, true);
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _uploadingImage = true;
      _error = null;
    });
    try {
      final url = await widget.controller.uploadMenuImage(
        picked.name,
        await picked.readAsBytes(),
      );
      if (mounted) setState(() => _imageUrl = url);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Gambar gagal diunggah. Maksimal 5 MB (JPG, PNG, atau WebP).',
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      title: Text(widget.menu == null ? 'Tambah data menu' : 'Edit data menu'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('menu-category-field'),
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: widget.controller.categories
                    .where(
                      (category) =>
                          category.isActive || category.id == _categoryId,
                    )
                    .map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                key: const Key('menu-product-type-field'),
                initialValue: _productType,
                decoration: const InputDecoration(labelText: 'Jenis martabak'),
                items: const [
                  DropdownMenuItem(
                    value: 'MARTABAK_TELUR',
                    child: Text('Martabak Telur'),
                  ),
                  DropdownMenuItem(
                    value: 'TERANG_BULAN',
                    child: Text('Terang Bulan'),
                  ),
                ],
                onChanged: (value) => setState(() => _productType = value!),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                key: const Key('menu-name-field'),
                label: 'Nama menu',
                controller: _name,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(label: 'SKU', controller: _sku),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Deskripsi',
                controller: _description,
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Urutan',
                      controller: _sort,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppButton.outlined(
                      label: _imageUrl == null
                          ? 'Upload gambar'
                          : 'Ganti gambar',
                      icon: Icons.add_photo_alternate_outlined,
                      isLoading: _uploadingImage,
                      onPressed: _uploadingImage ? null : _pickImage,
                    ),
                  ),
                ],
              ),
              if (_imageUrl case final url?) ...[
                const SizedBox(height: AppSpacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    url,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 80,
                      child: Center(
                        child: Text('Pratinjau gambar tidak tersedia'),
                      ),
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        AppButton(
          label: widget.menu == null ? 'Simpan sebagai draft' : 'Simpan data',
          isLoading: widget.controller.isSaving,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _PriceEditor extends StatefulWidget {
  final MenuAvailabilityController controller;
  final MenuItem menu;

  const _PriceEditor({required this.controller, required this.menu});

  @override
  State<_PriceEditor> createState() => _PriceEditorState();
}

class _PriceEditorState extends State<_PriceEditor> {
  late final Map<String, TextEditingController> _prices;
  late final TextEditingController _hpp;
  late final Map<String, TextEditingController> _channelMarkups;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hpp = TextEditingController(
      text: widget.menu.hppAmount != null
          ? CurrencyFormatter.formatThousands(widget.menu.hppAmount)
          : '',
    );
    _channelMarkups = {
      for (final channel in ChannelGeneratorConfig.onlineChannels)
        channel: TextEditingController(
          text: ChannelGeneratorConfig.formatRate(
            ChannelGeneratorConfig.getRate(channel),
          ),
        ),
    };
    _prices = {
      for (final channel in const [
        'OFFLINE',
        'GOFOOD',
        'GRABFOOD',
        'SHOPEEFOOD',
      ])
        channel: TextEditingController(
          text: () {
            final raw =
                widget.menu.channelPrices[channel] ??
                (channel == 'OFFLINE' ? widget.menu.priceAmount : null);
            return raw != null ? CurrencyFormatter.formatThousands(raw) : '';
          }(),
        ),
    };
  }

  @override
  void dispose() {
    _hpp.dispose();
    for (final controller in _channelMarkups.values) {
      controller.dispose();
    }
    for (final controller in _prices.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _generateOnlinePrices() {
    final offlineText = _prices['OFFLINE']?.text ?? '';
    final offlinePrice = CurrencyFormatter.parseThousands(offlineText);
    if (offlinePrice == null || offlinePrice <= 0) {
      setState(
        () => _error =
            'Harga OFFLINE wajib diisi dengan benar sebelum generate harga online.',
      );
      return;
    }

    final parsedRates = <String, double>{};
    for (final channel in ChannelGeneratorConfig.onlineChannels) {
      final text =
          _channelMarkups[channel]?.text.trim().replaceAll(',', '.') ?? '';
      final percent = double.tryParse(text);
      if (percent == null || percent < 0) {
        final label = ChannelGeneratorConfig.channelLabels[channel] ?? channel;
        setState(() => _error = 'Persentase markup untuk $label tidak valid.');
        return;
      }
      parsedRates[channel] = percent;
    }

    setState(() {
      for (final entry in parsedRates.entries) {
        final channel = entry.key;
        final percent = entry.value;
        final onlinePrice = CurrencyFormatter.calculateOnlinePrice(
          offlinePrice,
          percent,
        );
        _prices[channel]?.text = CurrencyFormatter.formatThousands(onlinePrice);
        ChannelGeneratorConfig.setRate(channel, percent);
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    final hpp = CurrencyFormatter.parseThousands(_hpp.text);
    final values = <String, int>{};
    for (final entry in _prices.entries) {
      final amount = CurrencyFormatter.parseThousands(entry.value.text);
      if (amount == null || amount < 0) {
        setState(() => _error = 'HPP dan seluruh harga channel wajib diisi.');
        return;
      }
      values[entry.key] = amount;
    }
    if (hpp == null || hpp < 0) {
      setState(() => _error = 'HPP dan seluruh harga channel wajib diisi.');
      return;
    }
    final saved = await widget.controller.saveMenu(
      widget.menu.copyWith(
        hppAmount: hpp,
        priceAmount: values['OFFLINE'],
        channelPrices: values,
      ),
    );
    if (mounted && saved) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    const labels = {
      'OFFLINE': 'Offline/Kasir',
      'GOFOOD': 'GoFood',
      'GRABFOOD': 'GrabFood',
      'SHOPEEFOOD': 'ShopeeFood',
    };
    return AlertDialog(
      title: Text('Edit harga · ${widget.menu.name}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                key: const Key('menu-hpp-field'),
                label: 'HPP (rupiah)',
                controller: _hpp,
                keyboardType: TextInputType.number,
                inputFormatters: const [ThousandsSeparatorInputFormatter()],
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                key: const Key('menu-offline-price-field'),
                label: 'Harga ${labels['OFFLINE']}',
                controller: _prices['OFFLINE'],
                keyboardType: TextInputType.number,
                inputFormatters: const [ThousandsSeparatorInputFormatter()],
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: AppSpacing.borderRadiusMd,
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Generator Harga Online',
                          style: AppTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextButton.icon(
                          key: const Key('open-master-generator-button'),
                          icon: const Icon(Icons.settings_outlined, size: 16),
                          label: const Text(
                            'Master Data',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () async {
                            final changed = await showChannelGeneratorDialog(
                              context,
                            );
                            if (mounted && changed == true) {
                              setState(() {
                                for (final ch
                                    in ChannelGeneratorConfig.onlineChannels) {
                                  _channelMarkups[ch]?.text =
                                      ChannelGeneratorConfig.formatRate(
                                        ChannelGeneratorConfig.getRate(ch),
                                      );
                                }
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Hitung harga GoFood, GrabFood, dan ShopeeFood otomatis dari acuan harga OFFLINE.',
                      style: AppTypography.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final channel
                            in ChannelGeneratorConfig.onlineChannels) ...[
                          Expanded(
                            child: AppTextField(
                              key: Key(
                                'menu-${channel.toLowerCase()}-markup-field',
                              ),
                              label:
                                  '${ChannelGeneratorConfig.channelLabels[channel] ?? channel} (%)',
                              controller: _channelMarkups[channel],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        AppButton(
                          key: const Key('generate-online-prices-button'),
                          label: 'Generate',
                          icon: Icons.auto_fix_high_rounded,
                          onPressed: _generateOnlinePrices,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              for (final channel in const [
                'GOFOOD',
                'GRABFOOD',
                'SHOPEEFOOD',
              ]) ...[
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  key: Key('menu-${channel.toLowerCase()}-price-field'),
                  label: 'Harga ${labels[channel]}',
                  controller: _prices[channel],
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsSeparatorInputFormatter()],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        AppButton(
          key: const Key('save-price-button'),
          label: 'Simpan harga',
          isLoading: widget.controller.isSaving,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _GlobalExtraEditor extends StatefulWidget {
  final MenuAvailabilityController controller;

  const _GlobalExtraEditor({required this.controller});

  @override
  State<_GlobalExtraEditor> createState() => _GlobalExtraEditorState();
}

class _GlobalExtraEditorState extends State<_GlobalExtraEditor> {
  String _productType = 'MARTABAK_TELUR';
  late _GroupDraft _draft;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = _draftFor(_productType);
  }

  _GroupDraft _draftFor(String type) {
    final current = widget.controller.globalExtraFor(type);
    return current == null
        ? _GroupDraft(
            code: TextEditingController(text: 'extra_isian'),
            name: TextEditingController(text: 'Extra Isian'),
            min: TextEditingController(text: '0'),
            max: TextEditingController(text: '20'),
            options: [],
          )
        : _GroupDraft.fromModel(current);
  }

  void _changeType(String value) {
    _draft.dispose();
    setState(() {
      _productType = value;
      _draft = _draftFor(value);
      _error = null;
    });
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final parsed = _draft.toModel(100);
    if (parsed == null || parsed.options.isEmpty) {
      setState(() => _error = 'Tambahkan minimal satu extra beserta harganya.');
      return;
    }
    final template = MenuModifierGroup(
      id: '',
      code: 'extra_isian',
      name: 'Extra Isian',
      minSelect: 0,
      maxSelect: parsed.maxSelect,
      sortOrder: 100,
      options: parsed.options,
    );
    final saved = await widget.controller.saveGlobalExtras(
      _productType,
      template,
    );
    if (mounted && saved) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      title: const Text('Kelola topping & extra global'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Perubahan otomatis diterapkan ke seluruh menu dengan jenis yang sama.',
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _productType,
                decoration: const InputDecoration(labelText: 'Jenis martabak'),
                items: const [
                  DropdownMenuItem(
                    value: 'MARTABAK_TELUR',
                    child: Text('Martabak Telur'),
                  ),
                  DropdownMenuItem(
                    value: 'TERANG_BULAN',
                    child: Text('Terang Bulan'),
                  ),
                ],
                onChanged: (value) => _changeType(value!),
              ),
              const SizedBox(height: AppSpacing.md),
              _GroupEditor(
                key: ObjectKey(_draft),
                index: 0,
                draft: _draft,
                onChanged: () => setState(() {}),
                onDelete: () {},
                fixedIdentity: true,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        AppButton(
          label: 'Terapkan ke semua menu',
          isLoading: widget.controller.isSaving,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _GroupEditor extends StatelessWidget {
  final int index;
  final _GroupDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final bool fixedIdentity;

  const _GroupEditor({
    super.key,
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onDelete,
    this.fixedIdentity = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          draft.name.text.trim().isEmpty
              ? 'Grup modifier ${index + 1}'
              : draft.name.text,
        ),
        trailing: fixedIdentity
            ? null
            : IconButton(
                tooltip: 'Hapus grup',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        children: [
          if (!fixedIdentity) ...[
            AppTextField(
              label: 'Nama grup',
              controller: draft.name,
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(label: 'Kode grup', controller: draft.code),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Minimal pilih',
                  controller: draft.min,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppTextField(
                  label: 'Maksimal pilih',
                  controller: draft.max,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...draft.options.indexed.map(
            (entry) => _OptionEditor(
              key: ObjectKey(entry.$2),
              draft: entry.$2,
              onDelete: () {
                final removed = draft.options.removeAt(entry.$1);
                removed.dispose();
                onChanged();
              },
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                draft.options.add(_OptionDraft.empty());
                onChanged();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah opsi'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionEditor extends StatelessWidget {
  final _OptionDraft draft;
  final VoidCallback onDelete;

  const _OptionEditor({super.key, required this.draft, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: AppTextField(label: 'Opsi', controller: draft.name),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: AppTextField(label: 'Kode', controller: draft.code),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: AppTextField(
              label: 'Tambahan harga',
              controller: draft.price,
              keyboardType: TextInputType.number,
            ),
          ),
          IconButton(
            tooltip: 'Hapus opsi',
            onPressed: onDelete,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _GroupDraft {
  final TextEditingController code;
  final TextEditingController name;
  final TextEditingController min;
  final TextEditingController max;
  final List<_OptionDraft> options;

  _GroupDraft({
    required this.code,
    required this.name,
    required this.min,
    required this.max,
    required this.options,
  });

  factory _GroupDraft.fromModel(MenuModifierGroup group) => _GroupDraft(
    code: TextEditingController(text: group.code),
    name: TextEditingController(text: group.name),
    min: TextEditingController(text: group.minSelect.toString()),
    max: TextEditingController(text: group.maxSelect.toString()),
    options: group.options.map(_OptionDraft.fromModel).toList(),
  );

  MenuModifierGroup? toModel(int sortOrder) {
    final minValue = int.tryParse(min.text);
    final maxValue = int.tryParse(max.text);
    final parsedOptions = <MenuOption>[];
    for (var index = 0; index < options.length; index++) {
      final option = options[index].toModel(index);
      if (option == null) return null;
      parsedOptions.add(option);
    }
    if (code.text.trim().isEmpty ||
        name.text.trim().isEmpty ||
        minValue == null ||
        maxValue == null ||
        minValue < 0 ||
        maxValue < 1 ||
        maxValue < minValue ||
        parsedOptions.length < minValue) {
      return null;
    }
    return MenuModifierGroup(
      id: '',
      code: code.text.trim(),
      name: name.text.trim(),
      minSelect: minValue,
      maxSelect: maxValue,
      sortOrder: sortOrder,
      options: parsedOptions,
    );
  }

  void dispose() {
    code.dispose();
    name.dispose();
    min.dispose();
    max.dispose();
    for (final option in options) {
      option.dispose();
    }
  }
}

class _OptionDraft {
  final TextEditingController code;
  final TextEditingController name;
  final TextEditingController price;

  _OptionDraft({required this.code, required this.name, required this.price});

  factory _OptionDraft.empty() => _OptionDraft(
    code: TextEditingController(),
    name: TextEditingController(),
    price: TextEditingController(text: '0'),
  );

  factory _OptionDraft.fromModel(MenuOption option) => _OptionDraft(
    code: TextEditingController(text: option.code),
    name: TextEditingController(text: option.name),
    price: TextEditingController(text: option.priceDeltaAmount.toString()),
  );

  MenuOption? toModel(int sortOrder) {
    final priceValue = int.tryParse(price.text);
    if (code.text.trim().isEmpty ||
        name.text.trim().isEmpty ||
        priceValue == null) {
      return null;
    }
    return MenuOption(
      id: '',
      code: code.text.trim(),
      name: name.text.trim(),
      priceDeltaAmount: priceValue,
      sortOrder: sortOrder,
    );
  }

  void dispose() {
    code.dispose();
    name.dispose();
    price.dispose();
  }
}

class _ChannelGeneratorDialog extends StatefulWidget {
  const _ChannelGeneratorDialog();

  @override
  State<_ChannelGeneratorDialog> createState() =>
      _ChannelGeneratorDialogState();
}

class _ChannelGeneratorDialogState extends State<_ChannelGeneratorDialog> {
  late final Map<String, TextEditingController> _controllers;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final channel in ChannelGeneratorConfig.onlineChannels)
        channel: TextEditingController(
          text: ChannelGeneratorConfig.formatRate(
            ChannelGeneratorConfig.getRate(channel),
          ),
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _reset() {
    setState(() {
      for (final channel in ChannelGeneratorConfig.onlineChannels) {
        final def = ChannelGeneratorConfig.defaultPercentages[channel] ?? 20.0;
        _controllers[channel]?.text = ChannelGeneratorConfig.formatRate(def);
      }
      _error = null;
    });
  }

  void _save() {
    for (final entry in _controllers.entries) {
      final text = entry.value.text.trim().replaceAll(',', '.');
      final val = double.tryParse(text);
      if (val == null || val < 0) {
        setState(
          () => _error = 'Persentase untuk seluruh kanal wajib valid (>= 0).',
        );
        return;
      }
    }

    for (final entry in _controllers.entries) {
      final text = entry.value.text.trim().replaceAll(',', '.');
      final val = double.parse(text);
      ChannelGeneratorConfig.setRate(entry.key, val);
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Master Data Generator Harga Kanal'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Atur persentase markup acuan untuk masing-masing kanal online (GoFood, GrabFood, ShopeeFood). Harga acuan adalah harga OFFLINE.',
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              for (final channel in ChannelGeneratorConfig.onlineChannels) ...[
                AppTextField(
                  key: Key('master-markup-${channel.toLowerCase()}-field'),
                  label:
                      'Markup ${ChannelGeneratorConfig.channelLabels[channel] ?? channel} (%)',
                  controller: _controllers[channel],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('reset-master-generator-button'),
          onPressed: _reset,
          child: const Text('Reset default (20%)'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        AppButton(
          key: const Key('save-master-generator-button'),
          label: 'Simpan',
          onPressed: _save,
        ),
      ],
    );
  }
}
