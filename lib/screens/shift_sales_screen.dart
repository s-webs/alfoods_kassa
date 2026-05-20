import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/sale.dart';
import '../models/shift.dart';
import '../services/api_service.dart';
import '../services/shift_sales_report_pdf_service.dart';
import '../utils/time_util.dart';
import '../utils/toast.dart';
import '../widgets/sale_payment_chip.dart';

enum ShiftSalesOfdFilter {
  all('all', 'Все'),
  ofd('ofd', 'ОФД'),
  nonOfd('non_ofd', 'Продажи');

  const ShiftSalesOfdFilter(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

class ShiftSalesScreen extends StatefulWidget {
  const ShiftSalesScreen({
    super.key,
    required this.apiService,
    required this.shiftId,
  });

  final ApiService apiService;
  final int shiftId;

  @override
  State<ShiftSalesScreen> createState() => _ShiftSalesScreenState();
}

class _ShiftSalesScreenState extends State<ShiftSalesScreen> {
  final List<Sale> _sales = [];
  final ScrollController _scrollController = ScrollController();

  Shift? _shift;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  int _lastPage = 1;
  int _total = 0;
  ShiftSalesOfdFilter _ofdFilter = ShiftSalesOfdFilter.all;
  bool _isGeneratingReport = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  bool get _hasMore => _currentPage < _lastPage;

  Future<void> _loadShiftMeta() async {
    final shift = await widget.apiService.getShift(widget.shiftId);
    if (!mounted) return;
    setState(() => _shift = shift);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _currentPage = 1;
        _sales.clear();
      });
    }

    try {
      if (_shift == null) {
        await _loadShiftMeta();
      }

      final page = await widget.apiService.getSales(
        shiftId: widget.shiftId,
        page: 1,
        ofdFilter: _ofdFilter.apiValue,
      );
      if (!mounted) return;
      setState(() {
        _sales
          ..clear()
          ..addAll(page.data);
        _currentPage = page.currentPage;
        _lastPage = page.lastPage;
        _total = page.total;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить продажи';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await widget.apiService.getSales(
        shiftId: widget.shiftId,
        page: _currentPage + 1,
        ofdFilter: _ofdFilter.apiValue,
      );
      if (!mounted) return;
      setState(() {
        _sales.addAll(page.data);
        _currentPage = page.currentPage;
        _lastPage = page.lastPage;
        _total = page.total;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  String _formatShiftTitle(Shift s) {
    final opened =
        '${TimeUtil.toUtcPlus5Wall(s.openedAt).day.toString().padLeft(2, '0')}.${TimeUtil.toUtcPlus5Wall(s.openedAt).month.toString().padLeft(2, '0')}.${TimeUtil.toUtcPlus5Wall(s.openedAt).year} '
        '${TimeUtil.toUtcPlus5Wall(s.openedAt).hour.toString().padLeft(2, '0')}:${TimeUtil.toUtcPlus5Wall(s.openedAt).minute.toString().padLeft(2, '0')}';
    if (s.closedAt != null) {
      final closed =
          '${TimeUtil.toUtcPlus5Wall(s.closedAt!).hour.toString().padLeft(2, '0')}:${TimeUtil.toUtcPlus5Wall(s.closedAt!).minute.toString().padLeft(2, '0')}';
      return '$opened – $closed';
    }
    return '$opened (открыта)';
  }

  String _reportFileSuffix(ShiftSalesOfdFilter filter) => switch (filter) {
        ShiftSalesOfdFilter.all => 'vse',
        ShiftSalesOfdFilter.ofd => 'ofd',
        ShiftSalesOfdFilter.nonOfd => 'prodazhi',
      };

  Future<void> _generateShiftReport(ShiftSalesOfdFilter filter) async {
    setState(() => _isGeneratingReport = true);
    try {
      final sales = await widget.apiService.getAllSalesForShift(
        shiftId: widget.shiftId,
        ofdFilter: filter.apiValue,
      );
      if (!mounted) return;
      if (sales.isEmpty) {
        showToast(context, 'Нет продаж для отчёта');
        return;
      }

      final shiftPeriod = _shift != null
          ? _formatShiftTitle(_shift!)
          : 'Смена #${widget.shiftId}';

      final pdfBytes = await ShiftSalesReportPdfService.build(
        shiftId: widget.shiftId,
        shiftPeriod: shiftPeriod,
        filterLabel: filter.label,
        sales: sales,
      );

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить отчёт по смене',
        fileName:
            'otchet-smena-${widget.shiftId}-${_reportFileSuffix(filter)}.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (!mounted) return;
      if (path != null && path.isNotEmpty) {
        final savePath = path.endsWith('.pdf') ? path : '$path.pdf';
        await File(savePath).writeAsBytes(pdfBytes);
        if (mounted) {
          showToast(context, 'Отчёт сохранён: $savePath');
        }
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          'Ошибка отчёта: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingReport = false);
    }
  }

  String get _emptyListMessage => switch (_ofdFilter) {
        ShiftSalesOfdFilter.all => 'Нет продаж в этой смене',
        ShiftSalesOfdFilter.ofd => 'Нет ОФД-продаж в этой смене',
        ShiftSalesOfdFilter.nonOfd => 'Нет не-ОФД продаж в этой смене',
      };

  String _formatSaleDateTime(DateTime dt) {
    final t = TimeUtil.toUtcPlus5Wall(dt);
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildSaleTile(Sale sale) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: sale.isPartiallyReturned
              ? AppColors.accent.withValues(alpha: 0.2)
              : AppColors.primaryLight,
          child: Icon(
            Icons.receipt,
            color: sale.isPartiallyReturned
                ? AppColors.accent
                : AppColors.primary,
          ),
        ),
        title: SaleListAmountTitle(sale: sale),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${sale.totalQty} шт. • #${sale.id} • ${_formatSaleDateTime(sale.createdAt)}',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                SaleStatusChip(sale: sale),
                SalePaymentChip(sale: sale, compact: true),
                if (sale.isOnCredit)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'в долг',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final result = await context.push<bool>('/sales/sale/${sale.id}');
          if (result == true && mounted) _load(reset: true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: AppColors.muted.withValues(alpha: 0.5)),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _shift != null
                          ? 'Смена от ${_formatShiftTitle(_shift!)}'
                          : 'Смена #${widget.shiftId}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (_total > 0)
                      Text(
                        'Продаж: $_total',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                  ],
                ),
              ),
              if (_isGeneratingReport)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                PopupMenuButton<ShiftSalesOfdFilter>(
                  tooltip: 'Отчёт по смене',
                  icon: const Icon(Icons.summarize_outlined),
                  onSelected: _generateShiftReport,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: ShiftSalesOfdFilter.all,
                      child: Text('Все продажи'),
                    ),
                    const PopupMenuItem(
                      value: ShiftSalesOfdFilter.ofd,
                      child: Text('ОФД-продажи'),
                    ),
                    const PopupMenuItem(
                      value: ShiftSalesOfdFilter.nonOfd,
                      child: Text('Продажи'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<ShiftSalesOfdFilter>(
            segments: ShiftSalesOfdFilter.values
                .map(
                  (f) => ButtonSegment(
                    value: f,
                    label: Text(f.label),
                  ),
                )
                .toList(),
            selected: {_ofdFilter},
            onSelectionChanged: _isLoading
                ? null
                : (selected) {
                    final next = selected.first;
                    if (next == _ofdFilter) return;
                    setState(() => _ofdFilter = next);
                    _load(reset: true);
                  },
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: AppColors.danger,
                          ),
                          const SizedBox(height: 16),
                          Text(_error!),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => _load(reset: true),
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    )
                  : _sales.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 64,
                                color: AppColors.muted,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _emptyListMessage,
                                style: Theme.of(context).textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _load(reset: true),
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _sales.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _sales.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              return _buildSaleTile(_sales[index]);
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
