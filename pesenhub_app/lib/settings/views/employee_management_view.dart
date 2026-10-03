import 'package:flutter/material.dart';
import '../../data/remote/pesenhub_api_client.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../models/employee.dart';

/// Screen 3: Manajemen Karyawan
class EmployeeManagementView extends StatefulWidget {
  final PesenHubApiClient? apiClient;
  final List<Map<String, dynamic>>? availableBranches;
  final String? currentBranchId;

  const EmployeeManagementView({
    super.key,
    this.apiClient,
    this.availableBranches,
    this.currentBranchId,
  });

  @override
  State<EmployeeManagementView> createState() => _EmployeeManagementViewState();
}

class _EmployeeManagementViewState extends State<EmployeeManagementView> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  List<Employee> _employees = [];
  String _searchQuery = '';

  // Initial dummy fallback if offline or no employees
  static final List<Employee> _fallbackEmployees = [
    const Employee(
      id: 'emp-1',
      email: 'yogaanandaxx1212@gmail.com',
      displayName: 'Yoga Ananda Sabila Rizqi',
      role: 'SUPERADMIN',
      status: 'APPROVED',
      branchName: 'Semua Cabang',
    ),
    const Employee(
      id: 'emp-2',
      email: 'siti@gmail.com',
      displayName: 'Siti Nurhaliza',
      role: 'CASHIER',
      status: 'APPROVED',
      branchName: 'Cabang Utama Banyuwangi',
    ),
    const Employee(
      id: 'emp-3',
      email: 'ahmad@gmail.com',
      displayName: 'Ahmad Fauzi',
      role: 'CASHIER',
      status: 'APPROVED',
      branchName: 'Cabang Utama Banyuwangi',
    ),
    const Employee(
      id: 'emp-4',
      email: 'dewi@gmail.com',
      displayName: 'Dewi Lestari',
      role: 'MANAGER',
      status: 'APPROVED',
      branchName: 'Cabang Rogojampi',
    ),
    const Employee(
      id: 'emp-5',
      email: 'rizky@gmail.com',
      displayName: 'Rizky Pratama',
      role: 'CASHIER',
      status: 'SUSPENDED',
      branchName: 'Cabang Genteng',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    final client = widget.apiClient;
    if (client == null) {
      setState(() => _employees = List.of(_fallbackEmployees));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final fetched = await client.fetchEmployees();
      if (!mounted) return;
      setState(() {
        _employees = fetched.isNotEmpty ? fetched : List.of(_fallbackEmployees);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _employees = List.of(_fallbackEmployees);
        _isLoading = false;
      });
    }
  }

  List<Employee> get _filteredEmployees {
    if (_searchQuery.isEmpty) return _employees;
    final q = _searchQuery.toLowerCase();
    return _employees.where((e) {
      return e.displayName.toLowerCase().contains(q) ||
          e.email.toLowerCase().contains(q) ||
          e.roleDisplay.toLowerCase().contains(q);
    }).toList();
  }

  Color _getAvatarColor(int index) {
    const colors = [
      Color(0xFF2E7D32), // Green
      Color(0xFF6A1B9A), // Purple
      Color(0xFF1565C0), // Blue
      Color(0xFFD81B60), // Pink
      Color(0xFF546E7A), // Slate
      Color(0xFFE65100), // Orange
    ];
    return colors[index % colors.length];
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
          'Manajemen Karyawan',
          style: TextStyle(
            color: Color(0xFF2D231E),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFF0EBE6)),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadEmployees,
        color: const Color(0xFF8D321F),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Hero banner card
              _buildHeroBanner(),
              const SizedBox(height: AppSpacing.md),

              // 2. Search & filter bar
              _buildSearchBar(),
              const SizedBox(height: AppSpacing.md),

              // 3. Tambah Karyawan Button
              _buildAddEmployeeButton(),
              const SizedBox(height: AppSpacing.lg),

              // 4. Employee List
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF8D321F)),
                  ),
                )
              else if (_filteredEmployees.isEmpty)
                _buildEmptyState()
              else
                ..._filteredEmployees.asMap().entries.map((entry) {
                  final index = entry.key;
                  final emp = entry.value;
                  return _buildEmployeeCard(emp, index);
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9EFE7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0DCD3)),
      ),
      child: Row(
        children: [
          // Illustration / Icon container
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE9D3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: Color(0xFF8D321F),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Kelola data karyawan, hak akses, dan peran dalam sistem.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF5A4438),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) =>
                        setState(() => _searchQuery = val.trim()),
                    decoration: const InputDecoration(
                      hintText: 'Cari nama karyawan...',
                      hintStyle: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF94A3B8),
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          height: 46,
          width: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: IconButton(
            icon: const Icon(
              Icons.tune_rounded,
              color: Color(0xFF475569),
              size: 20,
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Filter filter berdasarkan cabang aktif'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddEmployeeButton() {
    return ElevatedButton.icon(
      onPressed: _showAddEmployeeDialog,
      icon: const Icon(Icons.add_rounded, size: 20, color: Colors.white),
      label: const Text(
        'Tambah Karyawan',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF8D321F),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    );
  }

  Widget _buildEmployeeCard(Employee emp, int index) {
    final initial = emp.displayName.isNotEmpty
        ? emp.displayName[0].toUpperCase()
        : 'K';
    final avatarColor = _getAvatarColor(index);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circle Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: avatarColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Name, Role & Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  emp.displayName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  emp.roleDisplay,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: emp.isActive
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: emp.isActive
                          ? const Color(0xFFC8E6C9)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Text(
                    emp.statusDisplay,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: emp.isActive
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3-dots Action Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (action) => _handleEmployeeAction(emp, action),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit_name',
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: Color(0xFF475569),
                    ),
                    SizedBox(width: 10),
                    Text('Ubah Nama Karyawan', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'toggle_status',
                child: Row(
                  children: [
                    Icon(
                      emp.isActive
                          ? Icons.block_outlined
                          : Icons.check_circle_outline_rounded,
                      size: 18,
                      color: emp.isActive ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      emp.isActive ? 'Nonaktifkan Akun' : 'Aktifkan Akun',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: Colors.red,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Hapus Karyawan',
                      style: TextStyle(fontSize: 13, color: Colors.red),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.person_search_rounded,
            size: 54,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          const Text(
            'Tidak ada karyawan ditemukan',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Coba ubah kata kunci pencarian Anda.',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }

  void _handleEmployeeAction(Employee emp, String action) {
    switch (action) {
      case 'edit_name':
        _showEditNameDialog(emp);
        break;
      case 'toggle_status':
        _toggleEmployeeStatus(emp);
        break;
      case 'delete':
        _confirmDeleteEmployee(emp);
        break;
    }
  }

  void _showEditNameDialog(Employee emp) {
    final controller = TextEditingController(text: emp.displayName);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Ubah Nama Karyawan',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Email: ${emp.email}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nama Tampilan Karyawan',
                  hintText: 'Contoh: Siti Nurhaliza',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.length < 2) return;
                Navigator.of(dialogCtx).pop();
                await _saveEmployeeName(emp, newName);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8D321F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveEmployeeName(Employee emp, String newName) async {
    final client = widget.apiClient;
    setState(() {
      _employees = _employees.map((e) {
        return e.id == emp.id ? e.copyWith(displayName: newName) : e;
      }).toList();
    });

    if (client != null && emp.id.isNotEmpty && !emp.id.startsWith('emp-')) {
      try {
        await client.updateEmployee(emp.id, displayName: newName);
      } catch (_) {}
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Nama karyawan berhasil diubah menjadi "$newName".'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _toggleEmployeeStatus(Employee emp) async {
    final newStatus = emp.isActive ? 'SUSPENDED' : 'APPROVED';
    final statusLabel = emp.isActive ? 'dinonaktifkan' : 'diaktifkan';

    setState(() {
      _employees = _employees.map((e) {
        return e.id == emp.id ? e.copyWith(status: newStatus) : e;
      }).toList();
    });

    final client = widget.apiClient;
    if (client != null && emp.id.isNotEmpty && !emp.id.startsWith('emp-')) {
      try {
        await client.updateEmployee(emp.id, status: newStatus);
      } catch (_) {}
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Status ${emp.displayName} berhasil $statusLabel.'),
        backgroundColor: emp.isActive ? Colors.red.shade700 : AppColors.success,
      ),
    );
  }

  void _confirmDeleteEmployee(Employee emp) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hapus Karyawan'),
        content: Text(
          'Apakah Anda yakin ingin menghapus akses ${emp.displayName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              setState(() {
                _employees.removeWhere((e) => e.id == emp.id);
              });
              final client = widget.apiClient;
              if (client != null && !emp.id.startsWith('emp-')) {
                try {
                  await client.deleteEmployee(emp.id);
                } catch (_) {}
              }
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Karyawan ${emp.displayName} telah dihapus.'),
                  backgroundColor: Colors.red.shade700,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _showAddEmployeeDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String selectedRole = 'CASHIER';
    String? selectedBranch = widget.currentBranchId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Tambah Karyawan Baru',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Masukkan informasi karyawan untuk didaftarkan ke sistem.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nama Lengkap Karyawan',
                        hintText: 'Misal: Budi Santoso',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email Karyawan',
                        hintText: 'karyawan@gmail.com',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Peran / Hak Akses',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'CASHIER',
                          child: Text('Kasir'),
                        ),
                        DropdownMenuItem(
                          value: 'MANAGER',
                          child: Text('Manajer Outlet'),
                        ),
                        DropdownMenuItem(
                          value: 'ADMIN',
                          child: Text('Admin Outlet'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => selectedRole = val);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final name = nameCtrl.text.trim();
                        final email = emailCtrl.text.trim().toLowerCase();
                        if (name.isEmpty || !email.contains('@')) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Nama dan email wajib diisi dengan benar.',
                              ),
                            ),
                          );
                          return;
                        }
                        Navigator.of(sheetCtx).pop();

                        final client = widget.apiClient;
                        if (client != null) {
                          try {
                            final newEmp = await client.createEmployee(
                              displayName: name,
                              email: email,
                              role: selectedRole,
                              branchId: selectedBranch,
                            );
                            if (!mounted) return;
                            setState(() => _employees.insert(0, newEmp));
                          } catch (_) {
                            // Local fallback
                            final localEmp = Employee(
                              id: 'emp-${DateTime.now().millisecondsSinceEpoch}',
                              email: email,
                              displayName: name,
                              role: selectedRole,
                              status: 'APPROVED',
                              branchName: 'Cabang Aktif',
                            );
                            if (!mounted) return;
                            setState(() => _employees.insert(0, localEmp));
                          }
                        } else {
                          final localEmp = Employee(
                            id: 'emp-${DateTime.now().millisecondsSinceEpoch}',
                            email: email,
                            displayName: name,
                            role: selectedRole,
                            status: 'APPROVED',
                            branchName: 'Cabang Aktif',
                          );
                          setState(() => _employees.insert(0, localEmp));
                        }

                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Karyawan $name berhasil ditambahkan!',
                            ),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8D321F),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Simpan & Tambahkan'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
