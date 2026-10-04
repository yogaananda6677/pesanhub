import 'package:flutter/material.dart';
import '../../contact/models/whatsapp_contact.dart';
import '../../data/remote/pesenhub_api_client.dart';
import '../../theme/app_spacing.dart';

/// Screen for managing WhatsApp contacts and Chat Rules
/// (e.g. Marking numbers as non-customers so AI doesn't auto-reply).
class ContactRulesView extends StatefulWidget {
  final PesenHubApiClient? apiClient;

  const ContactRulesView({super.key, this.apiClient});

  @override
  State<ContactRulesView> createState() => _ContactRulesViewState();
}

class _ContactRulesViewState extends State<ContactRulesView> {
  bool _isLoading = false;
  String _selectedFilter = 'ALL'; // 'ALL', 'CUSTOMER', 'NON_CUSTOMER', 'OTHER'
  final TextEditingController _searchController = TextEditingController();
  List<WhatsAppContact> _contacts = [];

  static final List<WhatsAppContact> _fallbackContacts = [
    WhatsAppContact(
      id: 'c-1',
      branchId: 'b-1',
      phoneE164: '+6281234567890',
      name: 'Budi Santoso',
      contactType: 'CUSTOMER',
      autoReplyEnabled: true,
      notes: 'Pelanggan setia martabak sapi',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
    WhatsAppContact(
      id: 'c-2',
      branchId: 'b-1',
      phoneE164: '+6281987654321',
      name: 'Toko Sumber Telur',
      contactType: 'NON_CUSTOMER',
      autoReplyEnabled: false,
      notes: 'Supplier telur bebek & ayam (Bukan Pelanggan)',
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
      updatedAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    WhatsAppContact(
      id: 'c-3',
      branchId: 'b-1',
      phoneE164: '+6285712345678',
      name: 'Pak RT Lingkungan',
      contactType: 'PERSONAL',
      autoReplyEnabled: false,
      notes: 'Urusan lingkungan & kasir (Jangan dibalas bot)',
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
      updatedAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    if (widget.apiClient == null) {
      setState(() => _contacts = List.from(_fallbackContacts));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String? filterType;
      if (_selectedFilter == 'CUSTOMER') filterType = 'CUSTOMER';
      if (_selectedFilter == 'NON_CUSTOMER') filterType = 'NON_CUSTOMER';

      final res = await widget.apiClient!.fetchContacts(
        type: filterType,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _contacts = res;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _contacts = List.from(_fallbackContacts);
          _isLoading = false;
        });
      }
    }
  }

  List<WhatsAppContact> get _filteredContacts {
    var list = _contacts;
    if (_selectedFilter == 'CUSTOMER') {
      list = list.where((c) => c.contactType == 'CUSTOMER').toList();
    } else if (_selectedFilter == 'NON_CUSTOMER') {
      list = list
          .where(
            (c) =>
                c.contactType == 'NON_CUSTOMER' || c.contactType == 'BLACKLIST',
          )
          .toList();
    } else if (_selectedFilter == 'OTHER') {
      list = list
          .where(
            (c) => c.contactType == 'VENDOR' || c.contactType == 'PERSONAL',
          )
          .toList();
    }

    final query = _searchController.text.toLowerCase().trim();
    if (query.isNotEmpty) {
      list = list.where((c) {
        return c.phoneE164.toLowerCase().contains(query) ||
            c.name.toLowerCase().contains(query) ||
            c.notes.toLowerCase().contains(query);
      }).toList();
    }
    return list;
  }

  Future<void> _toggleAutoReply(WhatsAppContact contact, bool enabled) async {
    final oldState = contact.autoReplyEnabled;
    setState(() {
      final idx = _contacts.indexWhere((c) => c.id == contact.id);
      if (idx != -1) {
        _contacts[idx] = contact.copyWith(autoReplyEnabled: enabled);
      }
    });

    if (widget.apiClient != null) {
      try {
        await widget.apiClient!.toggleContactAutoReply(contact.id, enabled);
      } catch (e) {
        if (mounted) {
          setState(() {
            final idx = _contacts.indexWhere((c) => c.id == contact.id);
            if (idx != -1) {
              _contacts[idx] = contact.copyWith(autoReplyEnabled: oldState);
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mengubah aturan balas otomatis: $e')),
          );
        }
      }
    }
  }

  Future<void> _openMarkNonCustomerDialog(WhatsAppContact contact) async {
    String selectedType = contact.contactType == 'CUSTOMER'
        ? 'NON_CUSTOMER'
        : contact.contactType;
    final notesController = TextEditingController(text: contact.notes);

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Tandai Kontak: ${contact.name.isNotEmpty ? contact.name : contact.phoneE164}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pilih klasifikasi kontak ini agar Asisten Jenggirat AI tahu cara menanganinya:',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Klasifikasi Kontak',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'CUSTOMER',
                      child: Text('Pelanggan (Balas Otomatis AI)'),
                    ),
                    DropdownMenuItem(
                      value: 'NON_CUSTOMER',
                      child: Text('Bukan Pelanggan (Jangan Dibalas)'),
                    ),
                    DropdownMenuItem(
                      value: 'VENDOR',
                      child: Text('Supplier / Vendor Bahan'),
                    ),
                    DropdownMenuItem(
                      value: 'PERSONAL',
                      child: Text('Pribadi / Internal Gerai'),
                    ),
                    DropdownMenuItem(
                      value: 'BLACKLIST',
                      child: Text('Blokir / Spam (Abaikan)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setDlgState(() => selectedType = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan / Alasan (Opsional)',
                    hintText: 'Misal: Supplier telur, keluarga kasir...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              key: const Key('save-mark-contact-button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8D321F),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Simpan Aturan'),
            ),
          ],
        ),
      ),
    );

    if (updated == true) {
      final newAutoReply = selectedType == 'CUSTOMER';
      final newNotes = notesController.text.trim();

      setState(() {
        final idx = _contacts.indexWhere((c) => c.id == contact.id);
        if (idx != -1) {
          _contacts[idx] = contact.copyWith(
            contactType: selectedType,
            autoReplyEnabled: newAutoReply,
            notes: newNotes,
          );
        }
      });

      if (widget.apiClient != null) {
        try {
          await widget.apiClient!.markContactNonCustomer(
            contact.id,
            contactType: selectedType,
            notes: newNotes,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  selectedType == 'CUSTOMER'
                      ? 'Kontak ditandai sebagai Pelanggan'
                      : 'Kontak ditandai sebagai Bukan Pelanggan (AI Tidak Membalas)',
                ),
                backgroundColor: selectedType == 'CUSTOMER'
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFC62828),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal menyimpan aturan: $e')),
            );
          }
        }
      }
    }
  }

  Future<void> _openAddContactDialog() async {
    final phoneCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String selectedType = 'NON_CUSTOMER';

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Tambah Kontak WhatsApp',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('input-contact-phone'),
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Nomor WhatsApp*',
                    hintText: '08123456789 / +628...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('input-contact-name'),
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Kontak (Opsional)',
                    hintText: 'Contoh: Supplier Minyak Goreng',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Tipe Kontak',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'CUSTOMER',
                      child: Text('Pelanggan (Balas AI)'),
                    ),
                    DropdownMenuItem(
                      value: 'NON_CUSTOMER',
                      child: Text('Bukan Pelanggan (Abaikan)'),
                    ),
                    DropdownMenuItem(
                      value: 'VENDOR',
                      child: Text('Supplier / Vendor'),
                    ),
                    DropdownMenuItem(
                      value: 'PERSONAL',
                      child: Text('Internal / Keluarga'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setDlgState(() => selectedType = val);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('input-contact-notes'),
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan Khusus',
                    hintText: 'Keterangan tambahan...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              key: const Key('submit-add-contact-button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8D321F),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (phoneCtrl.text.trim().isEmpty) return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Simpan Kontak'),
            ),
          ],
        ),
      ),
    );

    if (created == true && phoneCtrl.text.trim().isNotEmpty) {
      final phone = phoneCtrl.text.trim();
      final name = nameCtrl.text.trim();
      final notes = notesCtrl.text.trim();
      final autoReply = selectedType == 'CUSTOMER';

      if (widget.apiClient != null) {
        try {
          final newContact = await widget.apiClient!.upsertContact({
            'phone': phone,
            'name': name,
            'contact_type': selectedType,
            'auto_reply_enabled': autoReply,
            'notes': notes,
          });
          setState(() {
            _contacts.insert(0, newContact);
          });
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal menambah kontak: $e')),
            );
          }
        }
      } else {
        setState(() {
          _contacts.insert(
            0,
            WhatsAppContact(
              id: 'c-${DateTime.now().millisecondsSinceEpoch}',
              branchId: 'b-1',
              phoneE164: phone,
              name: name,
              contactType: selectedType,
              autoReplyEnabled: autoReply,
              notes: notes,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedList = _filteredContacts;

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
          'Filter Kontak & Aturan Chat AI',
          style: TextStyle(
            color: Color(0xFF2D231E),
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFF0EBE6)),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-contact-fab'),
        backgroundColor: const Color(0xFF8D321F),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded, size: 20),
        label: const Text(
          'Tambah Kontak',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: _openAddContactDialog,
      ),
      body: RefreshIndicator(
        onRefresh: _loadContacts,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeroBanner(),
              const SizedBox(height: AppSpacing.md),

              // Search bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Cari nomor telepon, nama, atau catatan...',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF7A6B63),
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2D9D2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2D9D2)),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('ALL', 'Semua (${_contacts.length})'),
                    const SizedBox(width: 8),
                    _buildFilterChip('CUSTOMER', 'Pelanggan'),
                    const SizedBox(width: 8),
                    _buildFilterChip('NON_CUSTOMER', 'Bukan Pelanggan'),
                    const SizedBox(width: 8),
                    _buildFilterChip('OTHER', 'Supplier / Internal'),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (displayedList.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF0EBE6)),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.contacts_outlined,
                        size: 44,
                        color: Color(0xFFB0A299),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Tidak ada kontak ditemukan',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedFilter == 'ALL'
                            ? 'Kontak WhatsApp akan otomatis tercatat saat ada pesan masuk.'
                            : 'Coba ubah filter atau kata kunci pencarian.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7A6B63),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayedList.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) =>
                      _buildContactCard(displayedList[idx]),
                ),

              const SizedBox(height: 80), // Fab space
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilter == key;
    return ChoiceChip(
      key: Key('filter-contact-$key'),
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF8D321F),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : const Color(0xFF4A3E38),
      ),
      side: BorderSide(
        color: isSelected ? const Color(0xFF8D321F) : const Color(0xFFE2D9D2),
      ),
      onSelected: (_) {
        setState(() => _selectedFilter = key);
      },
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9EFE7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0DCD3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF8D321F),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.security_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aturan Kontak & Filter Chat',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2D231E),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Tandai nomor bukan pelanggan (supplier, keluarga, spam) agar AI tidak salah membalas chat.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7A6B63),
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

  Widget _buildContactCard(WhatsAppContact contact) {
    Color badgeColor;
    Color badgeTextColor;
    String badgeLabel;

    switch (contact.contactType) {
      case 'CUSTOMER':
        badgeColor = const Color(0xFFE8F5E9);
        badgeTextColor = const Color(0xFF2E7D32);
        badgeLabel = 'Pelanggan';
        break;
      case 'NON_CUSTOMER':
        badgeColor = const Color(0xFFFFEBEE);
        badgeTextColor = const Color(0xFFC62828);
        badgeLabel = 'Bukan Pelanggan';
        break;
      case 'VENDOR':
        badgeColor = const Color(0xFFE3F2FD);
        badgeTextColor = const Color(0xFF1565C0);
        badgeLabel = 'Supplier / Vendor';
        break;
      case 'PERSONAL':
        badgeColor = const Color(0xFFFFF3E0);
        badgeTextColor = const Color(0xFFE65100);
        badgeLabel = 'Internal / Pribadi';
        break;
      default:
        badgeColor = const Color(0xFFECEFF1);
        badgeTextColor = const Color(0xFF455A64);
        badgeLabel = contact.contactType;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: contact.autoReplyEnabled
              ? const Color(0xFFF0EBE6)
              : const Color(0xFFFFCDD2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: contact.autoReplyEnabled
                    ? const Color(0xFFF9EFE7)
                    : const Color(0xFFECEFF1),
                child: Icon(
                  contact.autoReplyEnabled
                      ? Icons.smart_toy_outlined
                      : Icons.smart_toy_rounded,
                  color: contact.autoReplyEnabled
                      ? const Color(0xFF8D321F)
                      : const Color(0xFF90A4AE),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            contact.name.isNotEmpty
                                ? contact.name
                                : contact.phoneE164,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2D231E),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: badgeTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (contact.name.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        contact.phoneE164,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7A6B63),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (contact.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Catatan: ${contact.notes}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
              ),
            ),
          ],

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0xFFF4EEEA)),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      contact.autoReplyEnabled
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      size: 16,
                      color: contact.autoReplyEnabled
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFC62828),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        contact.autoReplyEnabled
                            ? 'AI Balas Otomatis: AKTIF'
                            : 'AI Balas: NONAKTIF',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: contact.autoReplyEnabled
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFC62828),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                key: Key('toggle-reply-${contact.id}'),
                value: contact.autoReplyEnabled,
                activeThumbColor: const Color(0xFF2E7D32),
                onChanged: (val) => _toggleAutoReply(contact, val),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                key: Key('mark-contact-button-${contact.id}'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(
                  Icons.edit_note_rounded,
                  size: 16,
                  color: Color(0xFF475569),
                ),
                label: const Text(
                  'Ubah Status',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () => _openMarkNonCustomerDialog(contact),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
