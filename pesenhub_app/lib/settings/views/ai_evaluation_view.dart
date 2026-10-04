import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/remote/pesenhub_api_client.dart';
import '../../evaluation/models/ai_evaluation.dart';
import '../../theme/app_spacing.dart';

/// Screen for reviewing AI Customer Service chat turns, rating accuracy,
/// giving correction notes, and exporting training datasets for fine-tuning.
class AiEvaluationView extends StatefulWidget {
  final PesenHubApiClient? apiClient;

  const AiEvaluationView({super.key, this.apiClient});

  @override
  State<AiEvaluationView> createState() => _AiEvaluationViewState();
}

class _AiEvaluationViewState extends State<AiEvaluationView> {
  bool _isLoading = false;
  String _selectedFilter = 'ALL'; // 'ALL', 'UNREVIEWED', 'GOOD', 'BAD'
  final TextEditingController _searchController = TextEditingController();
  List<AiEvaluation> _evaluations = [];

  static final List<AiEvaluation> _fallbackEvaluations = [
    AiEvaluation(
      id: 'eval-1',
      branchId: 'b-1',
      senderPhone: '+6281234567890',
      customerName: 'Yoga',
      inputText: 'halo saya mau order minta katalognya dong kak',
      aiReply:
          'Halo kak Yoga! Selamat datang di Martabak & Terang Bulan Jenggirat. Berikut daftar menu lezat kami:\n🥞 Martabak Telur Spesial (Sosis, Ayam, Sapi)\n🧇 Terang Bulan Manis (1-3 Topping, Cut Pizza)\nKakak mau pesan menu yang mana? 😊',
      rating: 'GOOD',
      isReviewed: true,
      feedbackCategory: 'CORRECT',
      createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
    ),
    AiEvaluation(
      id: 'eval-2',
      branchId: 'b-1',
      senderPhone: '+6285712345678',
      customerName: 'Budi',
      inputText: 'terang bulan 1 topping coklat bisa gak adonannya red velvet?',
      aiReply:
          'Bisa banget kak Budi! Untuk Terang Bulan 1 Topping dengan adonan Red Velvet ada tambahan Rp 2.000 ya kak. Mau ukuran Biasa (Rp 20.000) atau Besar (Rp 27.000)? 😊',
      rating: 'UNRATED',
      isReviewed: false,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
    AiEvaluation(
      id: 'eval-3',
      branchId: 'b-1',
      senderPhone: '+6281999888777',
      customerName: 'Siti',
      inputText: 'bisa buat pesanan rapat kantor 30 box besok siang jam 12?',
      aiReply:
          'Bisa kak Siti! Kami siap melayani pesanan partai besar untuk rapat kantor. Silakan sebutkan rincian menu yang diinginkan ya kak, atau kasir kami akan segera mengonfirmasi jadwal pengambilannya.',
      rating: 'UNRATED',
      isReviewed: false,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadEvaluations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEvaluations() async {
    if (widget.apiClient == null) {
      setState(() => _evaluations = List.from(_fallbackEvaluations));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String? rating;
      bool? isReviewed;
      if (_selectedFilter == 'GOOD') rating = 'GOOD';
      if (_selectedFilter == 'BAD') rating = 'BAD';
      if (_selectedFilter == 'UNREVIEWED') isReviewed = false;

      final res = await widget.apiClient!.fetchAiEvaluations(
        rating: rating,
        isReviewed: isReviewed,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _evaluations = res;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _evaluations = List.from(_fallbackEvaluations);
          _isLoading = false;
        });
      }
    }
  }

  List<AiEvaluation> get _filteredEvaluations {
    var list = _evaluations;
    if (_selectedFilter == 'UNREVIEWED') {
      list = list.where((e) => !e.isReviewed).toList();
    } else if (_selectedFilter == 'GOOD') {
      list = list.where((e) => e.rating == 'GOOD').toList();
    } else if (_selectedFilter == 'BAD') {
      list = list
          .where((e) => e.rating == 'BAD' || e.rating == 'NEEDS_CORRECTION')
          .toList();
    }

    final query = _searchController.text.toLowerCase().trim();
    if (query.isNotEmpty) {
      list = list.where((e) {
        return e.senderPhone.toLowerCase().contains(query) ||
            e.customerName.toLowerCase().contains(query) ||
            e.inputText.toLowerCase().contains(query) ||
            e.aiReply.toLowerCase().contains(query);
      }).toList();
    }
    return list;
  }

  Future<void> _submitQuickRating(AiEvaluation eval, String rating) async {
    setState(() {
      final idx = _evaluations.indexWhere((e) => e.id == eval.id);
      if (idx != -1) {
        _evaluations[idx] = eval.copyWith(
          rating: rating,
          isReviewed: true,
          feedbackCategory: rating == 'GOOD' ? 'CORRECT' : 'NEEDS_CORRECTION',
        );
      }
    });

    if (widget.apiClient != null) {
      try {
        await widget.apiClient!.submitAiEvaluationReview(
          eval.id,
          rating: rating,
          feedbackCategory: rating == 'GOOD' ? 'CORRECT' : 'NEEDS_CORRECTION',
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Gagal menyimpan rating: $e')));
        }
      }
    }
  }

  Future<void> _openCorrectionDialog(AiEvaluation eval) async {
    String selectedCategory = eval.feedbackCategory ?? 'WRONG_INTENT';
    final notesController = TextEditingController(
      text: eval.correctionNotes ?? '',
    );
    final expectedController = TextEditingController(
      text: eval.expectedReply ?? eval.aiReply,
    );

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Koreksi & Jawaban Ideal AI',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Masukkan jawaban yang seharusnya agar dapat disimpan sebagai dataset evaluasi dan fine-tuning AI:',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Kategori Kesalahan',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'WRONG_MENU',
                      child: Text('Menu Salah / Tidak Cocok'),
                    ),
                    DropdownMenuItem(
                      value: 'WRONG_MODIFIER',
                      child: Text('Modifier / Topping Salah'),
                    ),
                    DropdownMenuItem(
                      value: 'WRONG_INTENT',
                      child: Text('Intent / Maksud Percakapan Salah'),
                    ),
                    DropdownMenuItem(
                      value: 'INAPPROPRIATE_TONE',
                      child: Text('Bahasa Kurang Sopan / Kaku'),
                    ),
                    DropdownMenuItem(
                      value: 'HALLUCINATION',
                      child: Text('Halusinasi / Informasi Palsu'),
                    ),
                    DropdownMenuItem(
                      value: 'CORRECT',
                      child: Text('Tepat (Hanya Koreksi Minor)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setDlgState(() => selectedCategory = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('input-correction-notes'),
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan Evaluasi',
                    hintText: 'Kenapa jawaban ini kurang tepat...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('input-expected-reply'),
                  controller: expectedController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Jawaban yang Seharusnya Diberikan*',
                    hintText:
                        'Tulis balasan ideal yang seharusnya diberikan oleh AI...',
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
              key: const Key('submit-correction-button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8D321F),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (expectedController.text.trim().isEmpty) return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Simpan Koreksi'),
            ),
          ],
        ),
      ),
    );

    if (submitted == true) {
      final notes = notesController.text.trim();
      final expected = expectedController.text.trim();

      setState(() {
        final idx = _evaluations.indexWhere((e) => e.id == eval.id);
        if (idx != -1) {
          _evaluations[idx] = eval.copyWith(
            rating: 'NEEDS_CORRECTION',
            isReviewed: true,
            feedbackCategory: selectedCategory,
            correctionNotes: notes,
            expectedReply: expected,
          );
        }
      });

      if (widget.apiClient != null) {
        try {
          await widget.apiClient!.submitAiEvaluationReview(
            eval.id,
            rating: 'NEEDS_CORRECTION',
            feedbackCategory: selectedCategory,
            correctionNotes: notes,
            expectedReply: expected,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Koreksi tersimpan ke dataset evaluasi AI!'),
                backgroundColor: Color(0xFF2E7D32),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal menyimpan koreksi: $e')),
            );
          }
        }
      }
    }
  }

  Future<void> _openExportDialog() async {
    List<Map<String, dynamic>> items = [];
    if (widget.apiClient != null) {
      try {
        items = await widget.apiClient!.exportAiTrainingDataset();
      } catch (e) {
        // Fallback demo export
        items = [
          {
            'messages': [
              {'role': 'user', 'content': 'halo mau pesan'},
              {
                'role': 'assistant',
                'content':
                    'Halo kak! Selamat datang di Martabak & Terang Bulan Jenggirat...',
              },
            ],
          },
        ];
      }
    } else {
      items = [
        {
          'messages': [
            {'role': 'user', 'content': 'halo mau pesan'},
            {
              'role': 'assistant',
              'content':
                  'Halo kak! Selamat datang di Martabak & Terang Bulan Jenggirat...',
            },
          ],
        },
      ];
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Export Dataset AI (${items.length} Data)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Dataset ini diformat dalam standar pesan percakapan (system, user, assistant) yang siap digunakan untuk evaluasi atau fine-tuning model LLM (Hermes / 9Router):',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          items[i].toString(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8D321F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Salin Semua Dataset ke Clipboard'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: items.toString()));
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dataset berhasil disalin ke clipboard!'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayedList = _filteredEvaluations;

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
          'Evaluasi & Training AI',
          style: TextStyle(
            color: Color(0xFF2D231E),
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            key: const Key('export-ai-dataset-button'),
            tooltip: 'Export Dataset JSONL',
            icon: const Icon(
              Icons.file_download_outlined,
              color: Color(0xFF8D321F),
            ),
            onPressed: _openExportDialog,
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFF0EBE6)),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadEvaluations,
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
                  hintText: 'Cari isi pesan atau nomor pelanggan...',
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
                    _buildFilterChip('ALL', 'Semua (${_evaluations.length})'),
                    const SizedBox(width: 8),
                    _buildFilterChip('UNREVIEWED', 'Belum Direview'),
                    const SizedBox(width: 8),
                    _buildFilterChip('GOOD', 'Akurat (👍)'),
                    const SizedBox(width: 8),
                    _buildFilterChip('BAD', 'Perlu Koreksi (👎)'),
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
                  child: const Column(
                    children: [
                      Icon(
                        Icons.rate_review_outlined,
                        size: 44,
                        color: Color(0xFFB0A299),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Tidak ada percakapan untuk dievaluasi',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Setiap turn percakapan WhatsApp yang dijawab oleh AI akan otomatis tercatat di sini.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
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
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, idx) =>
                      _buildEvaluationCard(displayedList[idx]),
                ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilter == key;
    return ChoiceChip(
      key: Key('filter-eval-$key'),
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
              Icons.psychology_rounded,
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
                  'Evaluasi & Dataset Pelatihan AI',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2D231E),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Beri nilai akurasi balasan bot dan simpan jawaban ideal sebagai dataset training untuk fine-tuning.',
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

  Widget _buildEvaluationCard(AiEvaluation eval) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: eval.isReviewed
              ? (eval.rating == 'GOOD'
                    ? const Color(0xFFA5D6A7)
                    : const Color(0xFFFFCC80))
              : const Color(0xFFF0EBE6),
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
          // Header: sender info & rating badge
          Row(
            children: [
              const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 16,
                color: Color(0xFF8D321F),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  eval.customerName.isNotEmpty
                      ? '${eval.customerName} (${eval.senderPhone})'
                      : eval.senderPhone,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D231E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildRatingBadge(eval),
            ],
          ),
          const SizedBox(height: 10),

          // User Message Bubble
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pesan Pelanggan:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  eval.inputText,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // AI Response Bubble
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF8F1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFC8E6C9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 12,
                      color: Color(0xFF2E7D32),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Balasan Asisten Jenggirat AI:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  eval.aiReply,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1B5E20),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),

          // If correction exists
          if (eval.expectedReply != null && eval.expectedReply!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFD8A8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💡 Jawaban Ideal yang Seharusnya (Dataset Training):',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB45309),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    eval.expectedReply!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9A3412),
                    ),
                  ),
                  if (eval.correctionNotes != null &&
                      eval.correctionNotes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Catatan: ${eval.correctionNotes}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF78350F),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0xFFF4EEEA)),
          ),

          // Action Row: Quick Rating & Correction Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    key: Key('rating-good-${eval.id}'),
                    tooltip: 'Balasan Sudah Bagus / Tepat',
                    icon: Icon(
                      eval.rating == 'GOOD'
                          ? Icons.thumb_up_alt_rounded
                          : Icons.thumb_up_alt_outlined,
                      color: eval.rating == 'GOOD'
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF64748B),
                      size: 20,
                    ),
                    onPressed: () => _submitQuickRating(eval, 'GOOD'),
                  ),
                  IconButton(
                    key: Key('rating-bad-${eval.id}'),
                    tooltip: 'Balasan Kurang Tepat / Perlu Koreksi',
                    icon: Icon(
                      eval.rating == 'BAD' || eval.rating == 'NEEDS_CORRECTION'
                          ? Icons.thumb_down_alt_rounded
                          : Icons.thumb_down_alt_outlined,
                      color:
                          eval.rating == 'BAD' ||
                              eval.rating == 'NEEDS_CORRECTION'
                          ? const Color(0xFFC62828)
                          : const Color(0xFF64748B),
                      size: 20,
                    ),
                    onPressed: () => _submitQuickRating(eval, 'BAD'),
                  ),
                ],
              ),
              OutlinedButton.icon(
                key: Key('correct-eval-button-${eval.id}'),
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
                  color: Color(0xFF8D321F),
                ),
                label: const Text(
                  'Koreksi Jawaban',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8D321F),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () => _openCorrectionDialog(eval),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRatingBadge(AiEvaluation eval) {
    if (!eval.isReviewed || eval.rating == 'UNRATED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Belum Direview',
          style: TextStyle(
            fontSize: 10,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (eval.rating == 'GOOD') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          '👍 Akurat',
          style: TextStyle(
            fontSize: 10,
            color: Color(0xFF2E7D32),
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '✍️ Ada Koreksi',
        style: TextStyle(
          fontSize: 10,
          color: Color(0xFFE65100),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
