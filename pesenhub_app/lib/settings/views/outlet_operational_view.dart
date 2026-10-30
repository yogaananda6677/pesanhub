import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/local/local_database.dart';
import '../../data/remote/pesenhub_api_client.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Screen 4: Outlet & Operasional
/// Integrasi penuh profil gerai dan sinkronisasi jam/hari buka operasional ke database (Issue #179).
class OutletOperationalView extends StatefulWidget {
  final List<Map<String, dynamic>>? availableBranches;
  final String? currentBranchId;
  final String? branchName;
  final String? branchAddress;
  final PesenHubApiClient? apiClient;
  final LocalDatabase? localDatabase;

  const OutletOperationalView({
    super.key,
    this.availableBranches,
    this.currentBranchId,
    this.branchName,
    this.branchAddress,
    this.apiClient,
    this.localDatabase,
  });

  @override
  State<OutletOperationalView> createState() => _OutletOperationalViewState();
}

class _OutletOperationalViewState extends State<OutletOperationalView> {
  // Operational state
  bool _isOpen = true;
  String _openTime = '16:00';
  String _closeTime = '23:30';
  String _openDays = 'SENIN,SELASA,RABU,KAMIS,JUMAT,SABTU,MINGGU';

  // Branch brand info
  late String _activeBranchId;
  late String _brandName;
  late String _brandAddress;
  String _brandPhone = '+62 813-9022-4134';

  List<Map<String, dynamic>> _branches = [];
  bool _isLoading = false;
  bool _isSaving = false;

  static const List<String> _allDays = [
    'SENIN',
    'SELASA',
    'RABU',
    'KAMIS',
    'JUMAT',
    'SABTU',
    'MINGGU',
  ];

  @override
  void initState() {
    super.initState();
    _activeBranchId =
        widget.currentBranchId ?? 'b0000000-0000-0000-0000-000000000001';
    _brandName = widget.branchName ?? 'Martabak & Terang Bulan Jenggirat';
    _brandAddress = widget.branchAddress ?? 'Jl. Ahmad Yani No. 45, Banyuwangi';

    if (widget.availableBranches != null &&
        widget.availableBranches!.isNotEmpty) {
      _branches = List.from(widget.availableBranches!);
    } else {
      _branches = [
        {
          'id': 'b-1',
          'code': 'BWX',
          'name': 'Cabang Utama Banyuwangi',
          'address': 'Jl. Ahmad Yani No. 45, Banyuwangi',
          'phone': '+62 813-9022-4134',
          'open_time': '16:00',
          'close_time': '23:30',
          'open_days': 'SENIN,SELASA,RABU,KAMIS,JUMAT,SABTU,MINGGU',
          'is_open': true,
          'is_main': true,
          'is_active': true,
        },
      ];
    }

    _loadOperationalData();
  }

  Future<void> _loadOperationalData() async {
    // 1. Load from local cache first (offline-first)
    if (widget.localDatabase != null) {
      try {
        final cached = await widget.localDatabase!.getMetadata(
          'cached_branch_operational',
        );
        if (cached != null && cached.isNotEmpty && mounted) {
          final data = jsonDecode(cached) as Map<String, dynamic>;
          setState(() {
            _applyBranchData(data);
          });
        }
      } catch (_) {
        // Ignored in test environments without sqflite
      }
    }

    // 2. Fetch fresh data from backend
    if (widget.apiClient != null) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      try {
        final branches = await widget.apiClient!.fetchBranches();
        if (branches.isNotEmpty && mounted) {
          setState(() {
            _branches = branches;
            // Match current active branch or fallback to default
            final active = branches.firstWhere(
              (b) => b['id'] == _activeBranchId || b['is_default'] == true,
              orElse: () => branches.first,
            );
            _applyBranchData(active);
          });

          // Save to local SQLite cache
          if (widget.localDatabase != null) {
            try {
              final active = branches.firstWhere(
                (b) => b['id'] == _activeBranchId || b['is_default'] == true,
                orElse: () => branches.first,
              );
              await widget.localDatabase!.setMetadata(
                'cached_branch_operational',
                jsonEncode(active),
              );
            } catch (_) {}
          }
        }
      } catch (err) {
        // Network failure; offline fallback already active
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _applyBranchData(Map<String, dynamic> data) {
    if (data['id'] != null) {
      _activeBranchId = data['id'].toString();
    }
    if (data['name'] != null && data['name'].toString().isNotEmpty) {
      _brandName = data['name'].toString();
    }
    if (data['address'] != null && data['address'].toString().isNotEmpty) {
      _brandAddress = data['address'].toString();
    }
    if (data['phone'] != null && data['phone'].toString().isNotEmpty) {
      _brandPhone = data['phone'].toString();
    }
    if (data['open_time'] != null && data['open_time'].toString().isNotEmpty) {
      _openTime = data['open_time'].toString();
    }
    if (data['close_time'] != null &&
        data['close_time'].toString().isNotEmpty) {
      _closeTime = data['close_time'].toString();
    }
    if (data['open_days'] != null && data['open_days'].toString().isNotEmpty) {
      _openDays = data['open_days'].toString();
    }
    if (data['is_open'] != null) {
      _isOpen = data['is_open'] == true;
    }
  }

  Future<void> _updateOperationalStatus(bool newStatus) async {
    final previousStatus = _isOpen;
    setState(() => _isOpen = newStatus);

    if (widget.apiClient != null) {
      try {
        await widget.apiClient!.updateBranchOperational(
          _activeBranchId,
          isOpen: newStatus,
        );
        _cacheCurrentProfile();
      } catch (err) {
        if (mounted) {
          setState(() => _isOpen = previousStatus);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal memperbarui status: $err'),
              backgroundColor: AppColors.accentRed,
            ),
          );
          return;
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus
                ? 'Status kasir: BUKA SEKARANG'
                : 'Status kasir: TUTUP SEMENTARA',
          ),
          backgroundColor: newStatus
              ? AppColors.accentGreenDeep
              : AppColors.accentRed,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _cacheCurrentProfile() async {
    if (widget.localDatabase == null) return;
    try {
      final payload = {
        'id': _activeBranchId,
        'name': _brandName,
        'address': _brandAddress,
        'phone': _brandPhone,
        'open_time': _openTime,
        'close_time': _closeTime,
        'open_days': _openDays,
        'is_open': _isOpen,
      };
      await widget.localDatabase!.setMetadata(
        'cached_branch_operational',
        jsonEncode(payload),
      );
    } catch (_) {}
  }

  String _formatOpenDaysDisplay(String rawDays) {
    final days = rawDays.split(',').map((d) => d.trim().toUpperCase()).toSet();
    if (days.length == 7) {
      return 'Setiap Hari (Senin - Minggu)';
    }
    if (days.length == 6 && !days.contains('MINGGU')) {
      return 'Senin - Sabtu (Minggu Libur)';
    }
    if (days.length == 5 &&
        !days.contains('SABTU') &&
        !days.contains('MINGGU')) {
      return 'Senin - Jumat (Weekend Libur)';
    }
    // Format capitalized
    final readable = days
        .map((d) {
          if (d.length <= 1) return d;
          return d[0].toUpperCase() + d.substring(1).toLowerCase();
        })
        .join(', ');
    return readable.isEmpty ? 'Belum Diatur' : readable;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.terracottaDark,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Outlet & Operasional',
          style: TextStyle(
            color: AppColors.terracottaDark,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.terracotta,
                    ),
                  ),
                ),
              ),
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.cardBorder),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Hero banner
            _buildHeroBanner(),
            const SizedBox(height: AppSpacing.lg),

            // 2. Brand & General Info
            _buildSectionHeader('BRAND & INFORMASI GERAI'),
            _buildBrandCard(),
            const SizedBox(height: AppSpacing.lg),

            // 3. Jam Operasional Kasir
            _buildSectionHeader('JAM OPERASIONAL KASIR'),
            _buildOperationalHoursCard(),
            const SizedBox(height: AppSpacing.lg),

            // 4. Daftar Cabang Gerai
            _buildSectionHeader('DAFTAR CABANG GERAI (${_branches.length})'),
            ..._branches.map((b) => _buildBranchCard(b)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.slate,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.terracottaLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.terracottaBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.terracotta,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profil Gerai & Operasional',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.terracottaDark,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Atur identitas brand, jam buka kasir, dan pantau cabang aktif.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.neutralText,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandCard() {
    final initial = _brandName.trim().isNotEmpty
        ? _brandName.trim()[0].toUpperCase()
        : 'J';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppColors.terracotta,
                      AppColors.terracottaGradientEnd,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _brandName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.terracottaDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Kuliner Martabak & Terang Bulan Spesial',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.neutralText,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: AppColors.terracotta,
                ),
                onPressed: _showEditBrandDialog,
                tooltip: 'Ubah Data Gerai',
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: AppColors.cardBorderSubtle),
          ),
          _buildInfoRow(
            icon: Icons.location_on_outlined,
            label: 'Alamat Gerai',
            value: _brandAddress,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.phone_outlined,
            label: 'Kontak CS & Gerai',
            value: _brandPhone,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Tahun Berdiri',
            value: '2024 (Mitra Usaha Kuliner)',
          ),
        ],
      ),
    );
  }

  Widget _buildOperationalHoursCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isOpen
                      ? AppColors.accentGreenBg
                      : AppColors.accentRedBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.access_time_filled_rounded,
                  color: _isOpen
                      ? AppColors.accentGreenDeep
                      : AppColors.accentRed,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status Layanan Kasir',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.neutralText,
                      ),
                    ),
                    Text(
                      _isOpen ? 'Buka Sekarang' : 'Tutup Sementara',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _isOpen
                            ? AppColors.accentGreenDeep
                            : AppColors.accentRed,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _isOpen,
                activeThumbColor: AppColors.terracotta,
                onChanged: _updateOperationalStatus,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: AppColors.cardBorderSubtle),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Jam Buka - Tutup:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.terracottaDark,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.terracottaLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_openTime - $_closeTime WIB',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.terracotta,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hari Operasional:',
                style: TextStyle(fontSize: 12, color: AppColors.neutralText),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _formatOpenDaysDisplay(_openDays),
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.terracottaDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _showEditHoursDialog,
            icon: const Icon(Icons.edit_calendar_outlined, size: 16),
            label: const Text('Ubah Jam & Hari Operasional'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.terracotta,
              side: const BorderSide(color: AppColors.terracottaBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchCard(Map<String, dynamic> branch) {
    final isMain = branch['is_main'] == true || branch['is_default'] == true;
    final name = branch['name']?.toString() ?? 'Cabang';
    final address = branch['address']?.toString() ?? '-';
    final phone = branch['phone']?.toString() ?? '-';
    final branchIsOpen = branch['is_open'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMain
              ? AppColors.terracotta.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isMain
                  ? AppColors.terracottaLight
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.store_outlined,
              color: isMain ? AppColors.terracotta : AppColors.slateDark,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.terracottaDark,
                        ),
                      ),
                    ),
                    if (isMain)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.terracotta,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'PUSAT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: branchIsOpen
                              ? AppColors.accentGreenBg
                              : AppColors.accentRedBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          branchIsOpen ? 'BUKA' : 'TUTUP',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: branchIsOpen
                                ? AppColors.accentGreenDeep
                                : AppColors.accentRed,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.neutralText,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.phone_android,
                      size: 13,
                      color: AppColors.neutralTextLight,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      phone,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.neutralTextLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.terracotta),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.neutralText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.terracottaDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  void _showEditHoursDialog() {
    final openCtrl = TextEditingController(text: _openTime);
    final closeCtrl = TextEditingController(text: _closeTime);
    final selectedDays = _openDays
        .split(',')
        .map((d) => d.trim().toUpperCase())
        .where((d) => d.isNotEmpty)
        .toSet();

    final isTablet =
        MediaQuery.sizeOf(context).width >= AppSpacing.tabletBreakpoint;

    Widget buildContent(BuildContext ctx, StateSetter setModalState) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.terracottaLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.access_time_rounded,
                    color: AppColors.terracotta,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Ubah Jam & Hari Operasional',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 22,
                    color: AppColors.slate,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  splashRadius: 20,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.surfaceVariant),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: openCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Jam Buka (HH:MM)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.wb_sunny_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: closeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Jam Tutup (HH:MM)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.nightlight_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Hari Buka Operasional',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.terracottaDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _allDays.map((day) {
                      final isSelected = selectedDays.contains(day);
                      return FilterChip(
                        label: Text(day),
                        selected: isSelected,
                        selectedColor: AppColors.terracottaLight,
                        checkmarkColor: AppColors.terracotta,
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? AppColors.terracotta
                              : AppColors.slate,
                        ),
                        onSelected: (val) {
                          setModalState(() {
                            if (val) {
                              selectedDays.add(day);
                            } else {
                              if (selectedDays.length > 1) {
                                selectedDays.remove(day);
                              }
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.surfaceVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Batal',
                    style: TextStyle(color: AppColors.neutralText),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(ctx);
                          final newOpen = openCtrl.text.trim();
                          final newClose = closeCtrl.text.trim();
                          final newDays = selectedDays.join(',');

                          final timeReg = RegExp(
                            r'^([01][0-9]|2[0-3]):[0-5][0-9]$',
                          );
                          if (!timeReg.hasMatch(newOpen) ||
                              !timeReg.hasMatch(newClose)) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Format jam harus valid (HH:MM, contoh: 16:00).',
                                ),
                                backgroundColor: AppColors.accentRed,
                              ),
                            );
                            return;
                          }

                          setState(() {
                            _openTime = newOpen;
                            _closeTime = newClose;
                            _openDays = newDays;
                            _isSaving = true;
                          });

                          if (widget.apiClient != null) {
                            try {
                              await widget.apiClient!.updateBranchOperational(
                                _activeBranchId,
                                openTime: newOpen,
                                closeTime: newClose,
                                openDays: newDays,
                              );
                              _cacheCurrentProfile();
                            } catch (err) {
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Gagal menyimpan ke database: $err',
                                    ),
                                    backgroundColor: AppColors.accentRed,
                                  ),
                                );
                              }
                            }
                          } else {
                            _cacheCurrentProfile();
                          }

                          if (mounted) {
                            setState(() => _isSaving = false);
                            if (ctx.mounted) {
                              navigator.pop();
                            }
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Jam operasional berhasil disimpan ke database.',
                                ),
                                backgroundColor: AppColors.accentGreenDeep,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.terracotta,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    minimumSize: const Size(100, 48),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Simpan'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (isTablet) {
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 500),
              child: Material(
                color: Colors.white,
                child: buildContent(ctx, setModalState),
              ),
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) => Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            clipBehavior: Clip.antiAlias,
            child: buildContent(ctx, setModalState),
          ),
        ),
      );
    }
  }

  void _showEditBrandDialog() {
    final nameCtrl = TextEditingController(text: _brandName);
    final addressCtrl = TextEditingController(text: _brandAddress);
    final phoneCtrl = TextEditingController(text: _brandPhone);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ubah Informasi Gerai'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nama Gerai / Brand',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Alamat Gerai',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Kontak CS / WhatsApp',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(ctx);
              final newName = nameCtrl.text.trim();
              final newAddress = addressCtrl.text.trim();
              final newPhone = phoneCtrl.text.trim();
              if (newName.isEmpty) return;

              setState(() {
                _brandName = newName;
                _brandAddress = newAddress;
                _brandPhone = newPhone;
              });

              if (widget.apiClient != null) {
                try {
                  await widget.apiClient!.updateBranchOperational(
                    _activeBranchId,
                    name: newName,
                    address: newAddress,
                    phone: newPhone,
                  );
                  _cacheCurrentProfile();
                } catch (_) {}
              } else {
                _cacheCurrentProfile();
              }

              if (mounted) {
                if (ctx.mounted) {
                  navigator.pop();
                }
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Data gerai berhasil disimpan ke database.'),
                    backgroundColor: AppColors.accentGreenDeep,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.terracotta,
              foregroundColor: Colors.white,
            ),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
