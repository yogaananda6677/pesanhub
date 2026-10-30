import 'package:flutter/material.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/remote/pesenhub_api_client.dart';
import '../../queue/models/queue_order.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../controllers/history_controller.dart';
import '../widgets/order_receipt_modal.dart';

class HistoryView extends StatefulWidget {
  final HistoryController? controller;
  final PesenHubApiClient? apiClient;
  final String? branchId;
  final List<QueueOrder>? initialOrders;

  const HistoryView({
    super.key,
    this.controller,
    this.apiClient,
    this.branchId,
    this.initialOrders,
  });

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  late final HistoryController _controller;
  late final TextEditingController _searchController;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _ownsController = true;
      _controller = HistoryController(
        apiClient: widget.apiClient,
        branchId: widget.branchId,
        initialOrders: widget.initialOrders,
      );
      _controller.loadOrders();
    }
    _searchController = TextEditingController(text: _controller.searchQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year, now.month, now.day, 23, 59, 59),
      initialDateRange:
          _controller.customDateRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      await _controller.setDateRangeFilter(
        HistoryDateRangeFilter.custom,
        customRange: picked,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final orders = _controller.filteredOrders;

        return RefreshIndicator(
          onRefresh: _controller.refresh,
          color: AppColors.primary,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide =
                  constraints.maxWidth >= AppSpacing.tabletBreakpoint;
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? AppSpacing.xl : AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search & Filters Card
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Search Input
                          TextField(
                            key: const Key('history-search-input'),
                            controller: _searchController,
                            onChanged: (val) => _controller.setSearchQuery(val),
                            decoration: InputDecoration(
                              hintText:
                                  'Cari nomor nota, nama pelanggan, atau menu...',
                              hintStyle: const TextStyle(
                                fontSize: 13,
                                color: AppColors.neutralTextLight,
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: AppColors.neutralTextMuted,
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: () {
                                        _searchController.clear();
                                        _controller.setSearchQuery('');
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: AppColors.warmSurface,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),

                          // Status Filter Chips
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final filter in HistoryStatusFilter.values)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      key: Key('history-filter-${filter.name}'),
                                      label: Text(filter.label),
                                      selected:
                                          _controller.statusFilter == filter,
                                      onSelected: (selected) {
                                        if (selected) {
                                          _controller.setStatusFilter(filter);
                                        }
                                      },
                                      selectedColor: AppColors.primaryContainer,
                                      labelStyle: TextStyle(
                                        color:
                                            _controller.statusFilter == filter
                                            ? AppColors.primary
                                            : AppColors.slate,
                                        fontWeight:
                                            _controller.statusFilter == filter
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        fontSize: 12,
                                      ),
                                      side: BorderSide(
                                        color:
                                            _controller.statusFilter == filter
                                            ? AppColors.terracottaBorder
                                            : AppColors.border,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Date Range Filter Chips
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final filter
                                    in HistoryDateRangeFilter.values)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      key: Key(
                                        'history-date-filter-${filter.name}',
                                      ),
                                      label: Text(
                                        filter ==
                                                    HistoryDateRangeFilter
                                                        .custom &&
                                                _controller.customDateRange !=
                                                    null
                                            ? '${_controller.customDateRange!.start.day}/${_controller.customDateRange!.start.month} - ${_controller.customDateRange!.end.day}/${_controller.customDateRange!.end.month}'
                                            : filter.label,
                                      ),
                                      selected:
                                          _controller.dateRangeFilter == filter,
                                      onSelected: (selected) {
                                        if (selected) {
                                          if (filter ==
                                              HistoryDateRangeFilter.custom) {
                                            _pickCustomDateRange();
                                          } else {
                                            _controller.setDateRangeFilter(
                                              filter,
                                            );
                                          }
                                        }
                                      },
                                      selectedColor: AppColors.warmSurface,
                                      labelStyle: TextStyle(
                                        color:
                                            _controller.dateRangeFilter ==
                                                filter
                                            ? AppColors.terracottaDark
                                            : AppColors.neutralTextMuted,
                                        fontWeight:
                                            _controller.dateRangeFilter ==
                                                filter
                                            ? FontWeight.w700
                                            : FontWeight.normal,
                                        fontSize: 11,
                                      ),
                                      side: BorderSide(
                                        color:
                                            _controller.dateRangeFilter ==
                                                filter
                                            ? AppColors.terracottaBorder
                                            : AppColors.border,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Loading State
                    if (_controller.isLoading)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        alignment: Alignment.center,
                        child: const Column(
                          children: [
                            CircularProgressIndicator(color: AppColors.primary),
                            SizedBox(height: 12),
                            Text(
                              'Memuat riwayat transaksi...',
                              style: TextStyle(
                                color: AppColors.neutralText,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    // Error State
                    else if (_controller.errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.accentRedBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.accentRedBorder),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 36,
                              color: AppColors.accentRed,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _controller.errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.accentRed,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              key: const Key('history-retry-button'),
                              onPressed: _controller.refresh,
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Coba Lagi'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accentRed,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    // Empty State
                    else if (orders.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: 48,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: const BoxDecoration(
                                color: AppColors.terracottaLight,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.receipt_long_outlined,
                                size: 36,
                                color: AppColors.terracotta,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            const Text(
                              'Tidak Ada Transaksi Ditemukan',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Coba sesuaikan kata kunci pencarian atau ganti filter tanggal.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.neutralText,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    // Orders List
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: orders.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final order = orders[index];
                          final isCancelled = order.isCancelled;
                          final isCompleted = order.isCompleted;

                          return Container(
                            key: Key('history-order-card-${order.orderNumber}'),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => OrderReceiptModal.show(
                                  context,
                                  order: order,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Card Header: Order # & Status Chip
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                order.orderNumber,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                order.formattedTime,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors
                                                      .neutralTextLight,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isCancelled
                                                  ? AppColors.accentRedBg
                                                  : (isCompleted
                                                        ? AppColors
                                                              .accentGreenBg
                                                        : AppColors
                                                              .accentAmberBg),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isCancelled
                                                  ? 'Batal'
                                                  : (isCompleted
                                                        ? 'Selesai'
                                                        : order.orderStatus),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: isCancelled
                                                    ? AppColors.accentRed
                                                    : (isCompleted
                                                          ? AppColors
                                                                .accentGreenDeep
                                                          : AppColors
                                                                .slateDark),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),

                                      // Customer name & item summary
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${order.customerName.isEmpty ? "Pelanggan Umum" : order.customerName} • ${order.items.length} menu',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.slate,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            CurrencyFormatter.formatRupiah(
                                              order.totalAmount,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),

                                      // Cancellation Reason Preview (if cancelled)
                                      if (isCancelled &&
                                          order.cancellationReason != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Alasan: ${order.cancellationReason}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.accentRed,
                                            fontStyle: FontStyle.italic,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],

                                      const SizedBox(height: 6),
                                      const Divider(
                                        color: AppColors.cardBorderSubtle,
                                        height: 8,
                                      ),
                                      const SizedBox(height: 2),

                                      // Footer row with action hint
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            order.diningOptionLabel,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.neutralTextMuted,
                                            ),
                                          ),
                                          const Row(
                                            children: [
                                              Text(
                                                'Lihat Struk',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 16,
                                                color: AppColors.primary,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
