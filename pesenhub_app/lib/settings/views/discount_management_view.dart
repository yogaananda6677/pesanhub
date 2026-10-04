import 'package:flutter/material.dart';
import '../../data/remote/pesenhub_api_client.dart';
import '../../discount/models/discount.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_feedback.dart';

/// DiscountManagementView allows admins to create, edit, toggle, and delete
/// discounts and promos scoped to channels (GoFood, GrabFood, ShopeeFood, Offline, WA)
/// and targets (Entire Order vs Specific Menu Items).
class DiscountManagementView extends StatefulWidget {
  final PesenHubApiClient? apiClient;

  const DiscountManagementView({super.key, this.apiClient});

  @override
  State<DiscountManagementView> createState() => _DiscountManagementViewState();
}

class _DiscountManagementViewState extends State<DiscountManagementView> {
  bool _isLoading = false;
  String? _errorMessage;
  List<Discount> _discounts = [];

  // Filter state
  String _selectedScope = 'ALL'; // ALL, ORDER, ITEM
  String _selectedChannel =
      'ALL'; // ALL, OFFLINE, GOFOOD, GRABFOOD, SHOPEEFOOD, WHATSAPP

  // Fallback sample data if API client is not configured
  static final List<Discount> _fallbackDiscounts = [
    const Discount(
      id: 'disc-fall-1',
      name: 'Promo GoFood Martabak 20%',
      code: 'GFMARTABAK20',
      scope: 'ITEM',
      channel: 'GOFOOD',
      type: 'PERCENTAGE',
      value: 20,
      maxDiscountAmount: 15000,
      minOrderAmount: 40000,
      isActive: true,
      menuIds: ['menu-martabak-1'],
    ),
    const Discount(
      id: 'disc-fall-2',
      name: 'Diskon Min Belanja 50 Ribu',
      code: 'DISKON50K',
      scope: 'ORDER',
      channel: 'ALL',
      type: 'FIXED',
      value: 10000,
      minOrderAmount: 50000,
      isActive: true,
    ),
    const Discount(
      id: 'disc-fall-3',
      name: 'Promo GrabFood Spesial 15%',
      code: 'GRABSPESIAL15',
      scope: 'ORDER',
      channel: 'GRABFOOD',
      type: 'PERCENTAGE',
      value: 15,
      maxDiscountAmount: 20000,
      minOrderAmount: 60000,
      isActive: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (widget.apiClient != null) {
        final list = await widget.apiClient!.fetchDiscounts();
        if (mounted) {
          setState(() {
            _discounts = list.isNotEmpty ? list : List.of(_fallbackDiscounts);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _discounts = List.of(_fallbackDiscounts);
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _discounts = List.of(_fallbackDiscounts);
          _errorMessage =
              'Gagal memuat dari server, menggunakan data lokal: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<Discount> get _filteredDiscounts {
    return _discounts.where((d) {
      if (_selectedScope != 'ALL' && d.scope != _selectedScope) {
        return false;
      }
      if (_selectedChannel != 'ALL' && d.channel != _selectedChannel) {
        return false;
      }
      return true;
    }).toList();
  }

  String _formatRupiah(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return 'Rp ${buffer.toString()}';
  }

  Future<void> _toggleDiscount(Discount discount) async {
    final originalActive = discount.isActive;
    setState(() {
      final idx = _discounts.indexWhere((d) => d.id == discount.id);
      if (idx != -1) {
        _discounts[idx] = discount.copyWith(isActive: !originalActive);
      }
    });

    if (widget.apiClient != null) {
      try {
        final updated = await widget.apiClient!.toggleDiscount(discount.id);
        setState(() {
          final idx = _discounts.indexWhere((d) => d.id == discount.id);
          if (idx != -1) {
            _discounts[idx] = updated;
          }
        });
      } catch (e) {
        // Rollback on failure
        setState(() {
          final idx = _discounts.indexWhere((d) => d.id == discount.id);
          if (idx != -1) {
            _discounts[idx] = discount.copyWith(isActive: originalActive);
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal mengubah status diskon: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteDiscount(Discount discount) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Promo / Diskon?'),
        content: Text('Apakah Anda yakin ingin menghapus "${discount.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _discounts.removeWhere((d) => d.id == discount.id);
    });

    if (widget.apiClient != null) {
      try {
        await widget.apiClient!.deleteDiscount(discount.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Diskon "${discount.name}" berhasil dihapus.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menghapus diskon: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        _loadData();
      }
    }
  }

  void _showAddEditDialog({Discount? existing}) {
    showDialog(
      context: context,
      builder: (ctx) => _DiscountFormDialog(
        existing: existing,
        apiClient: widget.apiClient,
        onSaved: (saved) {
          setState(() {
            final idx = _discounts.indexWhere((d) => d.id == saved.id);
            if (idx != -1) {
              _discounts[idx] = saved;
            } else {
              _discounts.insert(0, saved);
            }
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF8F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF2D231E),
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Kelola Diskon & Promo',
          style: TextStyle(
            color: Color(0xFF2D231E),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF2D231E)),
            tooltip: 'Segarkan',
            onPressed: _loadData,
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFF0EBE6)),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-promo-fab'),
        backgroundColor: const Color(0xFF8D321F),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Tambah Promo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: () => _showAddEditDialog(),
      ),
      body: _isLoading
          ? const Center(
              child: AppLoadingState(message: 'Memuat data diskon...'),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Hero explanation banner
                    _buildHeroBanner(),
                    const SizedBox(height: AppSpacing.md),

                    if (_errorMessage != null) ...[
                      AppBanner(
                        message: _errorMessage!,
                        type: AppBannerType.info,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Filter chips: Scope
                    _buildScopeFilter(),
                    const SizedBox(height: AppSpacing.sm),

                    // Filter chips: Channel
                    _buildChannelFilter(),
                    const SizedBox(height: AppSpacing.md),

                    // Discount Cards List
                    if (_filteredDiscounts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: AppEmptyState(
                          icon: Icons.local_offer_outlined,
                          title: 'Tidak Ada Promo Sesuai Filter',
                          description:
                              'Ganti filter atau buat promo diskon baru dengan tombol di bawah.',
                        ),
                      )
                    else
                      ..._filteredDiscounts.map((d) => _buildDiscountCard(d)),

                    const SizedBox(height: 80), // Padding for FAB
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8D321F), Color(0xFF6E2415)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8D321F).withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.discount_rounded, color: Colors.white, size: 36),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aturan & Strategi Promo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Atur diskon total order atau menu tertentu, batasi per merchant (GoFood, GrabFood, ShopeeFood, Offline), dan tentukan syarat min. belanja.',
                  style: TextStyle(
                    color: Color(0xFFF9EFE7),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const Text(
            'Target: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF7A6B63),
            ),
          ),
          const SizedBox(width: 6),
          _buildChip(
            key: const Key('filter-scope-all'),
            label: 'Semua Target',
            selected: _selectedScope == 'ALL',
            onSelected: () => setState(() => _selectedScope = 'ALL'),
          ),
          const SizedBox(width: 6),
          _buildChip(
            key: const Key('filter-scope-order'),
            label: 'Total Belanja (Order)',
            selected: _selectedScope == 'ORDER',
            onSelected: () => setState(() => _selectedScope = 'ORDER'),
          ),
          const SizedBox(width: 6),
          _buildChip(
            key: const Key('filter-scope-item'),
            label: 'Menu Spesifik (Item)',
            selected: _selectedScope == 'ITEM',
            onSelected: () => setState(() => _selectedScope = 'ITEM'),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelFilter() {
    final channels = [
      {'code': 'ALL', 'label': 'Semua Channel'},
      {'code': 'OFFLINE', 'label': 'Kasir Offline'},
      {'code': 'GOFOOD', 'label': 'GoFood'},
      {'code': 'GRABFOOD', 'label': 'GrabFood'},
      {'code': 'SHOPEEFOOD', 'label': 'ShopeeFood'},
      {'code': 'WHATSAPP', 'label': 'WhatsApp'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const Text(
            'Merchant: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF7A6B63),
            ),
          ),
          const SizedBox(width: 6),
          ...channels.map(
            (c) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _buildChip(
                key: Key('filter-channel-${c['code']}'),
                label: c['label']!,
                selected: _selectedChannel == c['code'],
                onSelected: () => setState(() => _selectedChannel = c['code']!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    Key? key,
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      key: key,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: selected ? Colors.white : const Color(0xFF2D231E),
      ),
      selectedColor: const Color(0xFF8D321F),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? const Color(0xFF8D321F) : const Color(0xFFE2E8F0),
        ),
      ),
    );
  }

  Widget _buildDiscountCard(Discount discount) {
    final isPercent = discount.type == 'PERCENTAGE';
    final valueText = isPercent
        ? '${discount.value}%'
        : _formatRupiah(discount.value);

    Color channelBg;
    Color channelText;
    switch (discount.channel) {
      case 'GOFOOD':
        channelBg = const Color(0xFFE8F5E9);
        channelText = const Color(0xFF2E7D32);
        break;
      case 'GRABFOOD':
        channelBg = const Color(0xFFE0F2F1);
        channelText = const Color(0xFF00796B);
        break;
      case 'SHOPEEFOOD':
        channelBg = const Color(0xFFFFF3E0);
        channelText = const Color(0xFFE65100);
        break;
      case 'WHATSAPP':
        channelBg = const Color(0xFFE8F5E9);
        channelText = const Color(0xFF1B5E20);
        break;
      case 'OFFLINE':
        channelBg = const Color(0xFFEDE7F6);
        channelText = const Color(0xFF512DA8);
        break;
      default:
        channelBg = const Color(0xFFF1F5F9);
        channelText = const Color(0xFF475569);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Discount Icon / Value Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: discount.isActive
                        ? const Color(0xFFFFF3E0)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: discount.isActive
                          ? const Color(0xFFFFB74D)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        valueText,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: discount.isActive
                              ? const Color(0xFFE65100)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                      Text(
                        isPercent ? 'DISKON' : 'POTONGAN',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: discount.isActive
                              ? const Color(0xFFBF360C)
                              : const Color(0xFF94A3B8),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Name & Badges
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        discount.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2D231E),
                        ),
                      ),
                      if (discount.code != null &&
                          discount.code!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            'KODE: ${discount.code}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          // Scope Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: discount.scope == 'ITEM'
                                  ? const Color(0xFFE0F7FA)
                                  : const Color(0xFFF3E5F5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              discount.scope == 'ITEM'
                                  ? 'Menu Spesifik'
                                  : 'Total Belanja',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: discount.scope == 'ITEM'
                                    ? const Color(0xFF006064)
                                    : const Color(0xFF4A148C),
                              ),
                            ),
                          ),

                          // Channel Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: channelBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              discount.channel == 'ALL'
                                  ? 'Semua Channel'
                                  : discount.channel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: channelText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Active Switch
                Switch.adaptive(
                  value: discount.isActive,
                  activeTrackColor: const Color(0xFF2E7D32),
                  onChanged: (_) => _toggleDiscount(discount),
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFF0EBE6)),
            const SizedBox(height: 8),

            // Requirements Details (Min order, Max discount, Target items)
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (discount.minOrderAmount > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shopping_bag_outlined,
                        size: 13,
                        color: Color(0xFF7A6B63),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Min. belanja ${_formatRupiah(discount.minOrderAmount)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7A6B63),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                if (discount.maxDiscountAmount != null &&
                    discount.maxDiscountAmount! > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_outlined,
                        size: 13,
                        color: Color(0xFF7A6B63),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Maks. potongan ${_formatRupiah(discount.maxDiscountAmount!)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7A6B63),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                if (discount.scope == 'ITEM' && discount.menuIds.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.restaurant_menu_rounded,
                        size: 13,
                        color: Color(0xFF7A6B63),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${discount.menuIds.length} Menu Terkait',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7A6B63),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Action row (Edit, Delete)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Ubah'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF8D321F),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _showAddEditDialog(existing: discount),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded, size: 15),
                  label: const Text('Hapus'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _deleteDiscount(discount),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog to Create or Edit Discount
class _DiscountFormDialog extends StatefulWidget {
  final Discount? existing;
  final PesenHubApiClient? apiClient;
  final ValueChanged<Discount> onSaved;

  const _DiscountFormDialog({
    this.existing,
    this.apiClient,
    required this.onSaved,
  });

  @override
  State<_DiscountFormDialog> createState() => _DiscountFormDialogState();
}

class _DiscountFormDialogState extends State<_DiscountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _valueController;
  late final TextEditingController _maxDiscountController;
  late final TextEditingController _minOrderController;

  late String _scope; // ORDER, ITEM
  late String _channel; // ALL, OFFLINE, GOFOOD, GRABFOOD, SHOPEEFOOD, WHATSAPP
  late String _type; // PERCENTAGE, FIXED
  late bool _isActive;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _nameController = TextEditingController(text: d?.name ?? '');
    _codeController = TextEditingController(text: d?.code ?? '');
    _valueController = TextEditingController(
      text: d?.value != null ? '${d!.value}' : '',
    );
    _maxDiscountController = TextEditingController(
      text: d?.maxDiscountAmount != null ? '${d!.maxDiscountAmount}' : '',
    );
    _minOrderController = TextEditingController(
      text: d?.minOrderAmount != null ? '${d!.minOrderAmount}' : '',
    );
    _scope = d?.scope ?? 'ORDER';
    _channel = d?.channel ?? 'ALL';
    _type = d?.type ?? 'PERCENTAGE';
    _isActive = d?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _valueController.dispose();
    _maxDiscountController.dispose();
    _minOrderController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final name = _nameController.text.trim();
    final code = _codeController.text.trim();
    final value = int.tryParse(_valueController.text.trim()) ?? 0;
    final maxDiscount = int.tryParse(_maxDiscountController.text.trim());
    final minOrder = int.tryParse(_minOrderController.text.trim());

    final payload = <String, dynamic>{
      'name': name,
      if (code.isNotEmpty) 'code': code,
      'scope': _scope,
      'channel': _channel,
      'type': _type,
      'value': value,
      if (maxDiscount != null && maxDiscount > 0)
        'max_discount_amount': maxDiscount,
      if (minOrder != null && minOrder > 0) 'min_order_amount': minOrder,
      'is_active': _isActive,
      'menu_ids': widget.existing?.menuIds ?? <String>[],
    };

    try {
      Discount saved;
      if (widget.existing != null) {
        if (widget.apiClient != null) {
          saved = await widget.apiClient!.updateDiscount(
            widget.existing!.id,
            payload,
          );
        } else {
          saved = widget.existing!.copyWith(
            name: name,
            code: code.isEmpty ? null : code,
            scope: _scope,
            channel: _channel,
            type: _type,
            value: value,
            maxDiscountAmount: maxDiscount,
            minOrderAmount: minOrder,
            isActive: _isActive,
          );
        }
      } else {
        if (widget.apiClient != null) {
          saved = await widget.apiClient!.createDiscount(payload);
        } else {
          saved = Discount(
            id: 'disc-local-${DateTime.now().millisecondsSinceEpoch}',
            name: name,
            code: code.isEmpty ? null : code,
            scope: _scope,
            channel: _channel,
            type: _type,
            value: value,
            maxDiscountAmount: maxDiscount,
            minOrderAmount: minOrder ?? 0,
            isActive: _isActive,
          );
        }
      }

      if (mounted) {
        widget.onSaved(saved);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan promo: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9EFE7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.local_offer_rounded,
                        color: Color(0xFF8D321F),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isEdit ? 'Ubah Promo / Diskon' : 'Tambah Promo Baru',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2D231E),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(height: 16),

                // Form Scrollable Body
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Nama Promo
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Nama Promo / Diskon *',
                            hintText: 'Contoh: Diskon GoFood Martabak 20%',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Nama promo wajib diisi'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.sm),

                        // Kode Promo
                        TextFormField(
                          controller: _codeController,
                          decoration: InputDecoration(
                            labelText: 'Kode Promo (Opsional)',
                            hintText: 'Contoh: GFMARTABAK20',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),

                        // Target Scope
                        DropdownButtonFormField<String>(
                          initialValue: _scope,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Target Promo *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'ORDER',
                              child: Text(
                                'Total Pembelian (Semua Pesanan)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'ITEM',
                              child: Text(
                                'Menu Tertentu (Spesifik Menu)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _scope = v ?? 'ORDER'),
                        ),
                        const SizedBox(height: AppSpacing.sm),

                        // Channel / Merchant
                        DropdownButtonFormField<String>(
                          initialValue: _channel,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Merchant / Saluran Penjualan *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'ALL',
                              child: Text(
                                'Semua Saluran (General / Umum)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'OFFLINE',
                              child: Text(
                                'Kasir Manual (Offline)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'GOFOOD',
                              child: Text(
                                'Khusus GoFood',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'GRABFOOD',
                              child: Text(
                                'Khusus GrabFood',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'SHOPEEFOOD',
                              child: Text(
                                'Khusus ShopeeFood',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'WHATSAPP',
                              child: Text(
                                'Khusus WhatsApp',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _channel = v ?? 'ALL'),
                        ),
                        const SizedBox(height: AppSpacing.sm),

                        // Tipe Diskon
                        DropdownButtonFormField<String>(
                          initialValue: _type,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Jenis Potongan *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'PERCENTAGE',
                              child: Text('Persentase (%)'),
                            ),
                            DropdownMenuItem(
                              value: 'FIXED',
                              child: Text('Nominal Tetap (Rp)'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _type = v ?? 'PERCENTAGE'),
                        ),
                        const SizedBox(height: AppSpacing.sm),

                        // Nilai Diskon
                        TextFormField(
                          controller: _valueController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: _type == 'PERCENTAGE'
                                ? 'Besar Diskon (%) *'
                                : 'Nominal Potongan (Rp) *',
                            hintText: _type == 'PERCENTAGE'
                                ? 'Contoh: 20'
                                : 'Contoh: 10000',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Nilai diskon wajib diisi';
                            }
                            final n = int.tryParse(v.trim());
                            if (n == null || n <= 0) {
                              return 'Nilai harus angka lebih dari 0';
                            }
                            if (_type == 'PERCENTAGE' && n > 100) {
                              return 'Persentase maksimal 100%';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.sm),

                        // Maksimal Diskon (hanya jika PERCENTAGE)
                        if (_type == 'PERCENTAGE') ...[
                          TextFormField(
                            controller: _maxDiscountController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Batas Maksimal Diskon (Rp, Opsional)',
                              hintText: 'Contoh: 15000',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],

                        // Minimal Pembelian
                        TextFormField(
                          controller: _minOrderController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Minimal Pembelian (Rp, Opsional)',
                            hintText: 'Contoh: 50000',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),

                        // Status Aktif
                        SwitchListTile.adaptive(
                          title: const Text(
                            'Status Promo Aktif',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: const Text(
                            'Jika dinonaktifkan, promo tidak akan muncul di kasir.',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: _isActive,
                          activeTrackColor: const Color(0xFF2E7D32),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setState(() => _isActive = v),
                        ),
                      ],
                    ),
                  ),
                ),

                const Divider(height: 16),

                // Submit Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Batal'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8D321F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isSaving ? null : _handleSave,
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(isEdit ? 'Simpan Perubahan' : 'Buat Promo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
