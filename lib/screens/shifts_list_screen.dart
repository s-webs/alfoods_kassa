import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../models/sales_payment_report_filter.dart';
import '../models/shift.dart';
import '../services/api_service.dart';
import '../services/shift_sales_report_pdf_service.dart';
import '../services/z_report_print_service.dart';
import '../utils/time_util.dart';
import '../utils/toast.dart';
import '../widgets/z_report_dialog.dart';

class ShiftsListScreen extends StatefulWidget {
  const ShiftsListScreen({
    super.key,
    required this.storage,
    required this.apiService,
  });

  final Storage storage;
  final ApiService apiService;

  @override
  State<ShiftsListScreen> createState() => _ShiftsListScreenState();
}

class _ShiftsListScreenState extends State<ShiftsListScreen> {
  final List<Shift> _shifts = [];
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  int _lastPage = 1;
  int _total = 0;
  DateTime? _reportDateFrom;
  DateTime? _reportDateTo;
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

  bool get _hasMore => _currentPage < _lastPage;

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _currentPage = 1;
        _shifts.clear();
      });
    }

    try {
      final page = await widget.apiService.getShifts(page: 1);
      if (!mounted) return;
      setState(() {
        _shifts
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
        _error = 'Не удалось загрузить смены';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await widget.apiService.getShifts(page: _currentPage + 1);
      if (!mounted) return;
      setState(() {
        _shifts.addAll(page.data);
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

  String _formatReportDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  Future<void> _pickReportDate(bool isFrom) async {
    final initial =
        isFrom ? (_reportDateFrom ?? DateTime.now()) : (_reportDateTo ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isFrom) {
          _reportDateFrom = picked;
        } else {
          _reportDateTo = picked;
        }
      });
    }
  }

  Future<void> _generatePeriodReport(SalesPaymentReportFilter filter) async {
    if (_reportDateFrom == null || _reportDateTo == null) {
      showToast(context, 'Укажите дату с и дату по для отчёта');
      return;
    }
    if (_reportDateFrom!.isAfter(_reportDateTo!)) {
      showToast(context, 'Дата «с» не может быть позже даты «по»');
      return;
    }

    setState(() => _isGeneratingReport = true);
    try {
      final sales = await widget.apiService.getAllSalesForPeriod(
        dateFrom: _reportDateFrom!,
        dateTo: _reportDateTo!,
        paymentReport: filter.apiValue,
      );
      if (!mounted) return;
      if (sales.isEmpty) {
        showToast(context, 'Нет продаж для отчёта');
        return;
      }

      final periodLabel =
          '${_formatReportDate(_reportDateFrom!)} – ${_formatReportDate(_reportDateTo!)}';
      final pdfBytes = await ShiftSalesReportPdfService.build(
        periodLabel: periodLabel,
        filterLabel: filter.label,
        sales: sales,
      );

      final fromStr =
          '${_reportDateFrom!.year}${_reportDateFrom!.month.toString().padLeft(2, '0')}${_reportDateFrom!.day.toString().padLeft(2, '0')}';
      final toStr =
          '${_reportDateTo!.year}${_reportDateTo!.month.toString().padLeft(2, '0')}${_reportDateTo!.day.toString().padLeft(2, '0')}';

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить отчёт по продажам',
        fileName: 'otchet_prodazhi_${filter.fileSuffix}_${fromStr}_${toStr}.pdf',
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Продажи',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (_total > 0)
                          Text(
                            'Смен: $_total',
                            style: TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/sales/search'),
                    icon: const Icon(Icons.search, size: 20),
                    label: const Text('Поиск продажи'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Отчёт PDF (по дате продажи)',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isGeneratingReport ? null : () => _pickReportDate(true),
                      child: Text(
                        _reportDateFrom == null
                            ? 'Дата с'
                            : _formatReportDate(_reportDateFrom!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isGeneratingReport ? null : () => _pickReportDate(false),
                      child: Text(
                        _reportDateTo == null
                            ? 'Дата по'
                            : _formatReportDate(_reportDateTo!),
                      ),
                    ),
                  ),
                  if (_isGeneratingReport)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    PopupMenuButton<SalesPaymentReportFilter>(
                      tooltip: 'Отчёт PDF',
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      onSelected: _generatePeriodReport,
                      itemBuilder: (context) => SalesPaymentReportFilter.values
                          .map(
                            (f) => PopupMenuItem(
                              value: f,
                              child: Text(f.label),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ],
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
                          Icon(Icons.error_outline,
                              size: 48, color: AppColors.danger),
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
                  : _shifts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.schedule,
                                  size: 64, color: AppColors.muted),
                              const SizedBox(height: 16),
                              Text(
                                'Нет смен',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _load(reset: true),
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _shifts.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _shifts.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              final shift = _shifts[index];
                              final zReport = shift.webkassaZReport;
                              final showZ = !shift.isOpen &&
                                  ZReportDialog.hasViewableData(zReport);
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  onTap: () => context.push(
                                    '/sales/shift/${shift.id}',
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: AppColors.primaryLight,
                                          child: Icon(
                                            shift.isOpen
                                                ? Icons.play_circle_filled
                                                : Icons.stop_circle,
                                            color: shift.isOpen
                                                ? AppColors.accent
                                                : AppColors.muted,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _formatShiftTitle(shift),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                shift.isOpen
                                                    ? 'Открыта'
                                                    : 'Закрыта',
                                                style: TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (showZ) ...[
                                          IconButton(
                                            tooltip: 'Печать Z-отчёта',
                                            icon: const Icon(
                                              Icons.print_outlined,
                                            ),
                                            onPressed: () {
                                              ZReportPrintService(
                                                widget.storage,
                                              ).print(
                                                context,
                                                zReport: zReport!,
                                                zReportAt:
                                                    shift.webkassaZReportAt,
                                              );
                                            },
                                          ),
                                          IconButton(
                                            tooltip: 'Z-отчёт WebKassa',
                                            icon: const Icon(
                                              Icons.summarize_outlined,
                                            ),
                                            onPressed: () {
                                              ZReportDialog.show(
                                                context,
                                                zReport: zReport!,
                                                zReportAt:
                                                    shift.webkassaZReportAt,
                                                storage: widget.storage,
                                              );
                                            },
                                          ),
                                        ],
                                        Icon(
                                          Icons.chevron_right,
                                          color: AppColors.muted,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
