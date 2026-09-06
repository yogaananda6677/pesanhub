import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
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
  late final TextEditingController _price;
  late final TextEditingController _sort;
  late String? _categoryId;
  late final List<_GroupDraft> _groups;
  String? _error;

  @override
  void initState() {
    super.initState();
    final menu = widget.menu;
    _name = TextEditingController(text: menu?.name);
    _sku = TextEditingController(text: menu?.sku);
    _description = TextEditingController(text: menu?.description);
    _price = TextEditingController(text: (menu?.priceAmount ?? 0).toString());
    _sort = TextEditingController(text: (menu?.sortOrder ?? 0).toString());
    _categoryId =
        menu?.categoryId ??
        (widget.controller.categories.isEmpty
            ? null
            : widget.controller.categories.first.id);
    _groups = menu?.modifierGroups.map(_GroupDraft.fromModel).toList() ?? [];
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _description.dispose();
    _price.dispose();
    _sort.dispose();
    for (final group in _groups) {
      group.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final price = int.tryParse(_price.text.trim());
    final sort = int.tryParse(_sort.text.trim());
    if (_categoryId == null ||
        _name.text.trim().isEmpty ||
        _sku.text.trim().isEmpty ||
        price == null ||
        price < 0 ||
        sort == null ||
        sort < 0) {
      setState(
        () => _error = 'Kategori, nama, SKU, harga, dan urutan wajib valid.',
      );
      return;
    }
    final groups = <MenuModifierGroup>[];
    for (var index = 0; index < _groups.length; index++) {
      final parsed = _groups[index].toModel(index);
      if (parsed == null) {
        setState(() => _error = 'Lengkapi setiap grup dan opsi modifier.');
        return;
      }
      groups.add(parsed);
    }
    final current = widget.menu;
    final saved = await widget.controller.saveMenu(
      MenuItem(
        id: current?.id ?? '',
        categoryId: _categoryId!,
        sku: _sku.text.trim(),
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        priceAmount: price,
        isAvailable: current?.isAvailable ?? true,
        version: current?.version ?? 1,
        sortOrder: sort,
        modifierGroups: groups,
      ),
    );
    if (mounted && saved) Navigator.pop(context, true);
  }

  void _addGroup() => setState(() => _groups.add(_GroupDraft.empty()));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      title: Text(widget.menu == null ? 'Tambah menu' : 'Edit menu'),
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
                      label: 'Harga (rupiah)',
                      controller: _price,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppTextField(
                      label: 'Urutan',
                      controller: _sort,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Modifier',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('add-modifier-group'),
                    onPressed: _addGroup,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Tambah grup'),
                  ),
                ],
              ),
              ..._groups.indexed.map(
                (entry) => _GroupEditor(
                  key: ObjectKey(entry.$2),
                  index: entry.$1,
                  draft: entry.$2,
                  onChanged: () => setState(() {}),
                  onDelete: () => setState(() {
                    final removed = _groups.removeAt(entry.$1);
                    removed.dispose();
                  }),
                ),
              ),
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
          label: 'Simpan menu',
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

  const _GroupEditor({
    super.key,
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onDelete,
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
        trailing: IconButton(
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
          AppTextField(
            label: 'Nama grup',
            controller: draft.name,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'Kode grup', controller: draft.code),
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

  factory _GroupDraft.empty() => _GroupDraft(
    code: TextEditingController(),
    name: TextEditingController(),
    min: TextEditingController(text: '0'),
    max: TextEditingController(text: '1'),
    options: [],
  );

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
