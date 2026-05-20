import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/sale.dart';
import '../services/api_service.dart';
import '../utils/time_util.dart';
import '../widgets/sale_payment_chip.dart';

class SaleSearchScreen extends StatefulWidget {
  const SaleSearchScreen({
    super.key,
    required this.apiService,
  });

  final ApiService apiService;

  @override
  State<SaleSearchScreen> createState() => _SaleSearchScreenState();
}

class _SaleSearchScreenState extends State<SaleSearchScreen> {
  final List<Sale> _filteredSales = [];
  final ScrollController _scrollController = ScrollController();
  final _internalIdController = TextEditingController();
  final _webkassaCheckController = TextEditingController();

  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _searched = false;
  String? _error;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  int _currentPage = 1;
  int _lastPage = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _internalIdController.dispose();
    _webkassaCheckController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_searched || !_scrollController.hasClients || _isLoadingMore) return;
    if (_currentPage >= _lastPage) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Map<String, dynamic>? _searchParams() {
    final internalText = _internalIdController.text.trim();
    final webkassaText = _webkassaCheckController.text.trim();
    final saleId = internalText.isEmpty ? null : int.tryParse(internalText);

    if (saleId == null &&
        webkassaText.isEmpty &&
        _dateFrom == null &&
        _dateTo == null) {
      return null;
    }

    return {
      'saleId': saleId,
      'webkassa': webkassaText.isEmpty ? null : webkassaText,
    };
  }

  Future<void> _search() async {
    if (_searchParams() == null) {
      setState(() => _error = 'Укажите внутренний №, чек WebKassa или период дат');
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
      _searched = false;
      _filteredSales.clear();
      _currentPage = 1;
    });

    try {
      final params = _searchParams()!;
      final page = await widget.apiService.searchSales(
        saleId: params['saleId'] as int?,
        webkassaCheckNumber: params['webkassa'] as String?,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        page: 1,
      );
      if (!mounted) return;
      setState(() {
        _filteredSales.addAll(page.data);
        _currentPage = page.currentPage;
        _lastPage = page.lastPage;
        _total = page.total;
        _searched = true;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось выполнить поиск';
        _isSearching = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _currentPage >= _lastPage) return;
    final params = _searchParams();
    if (params == null) return;

    setState(() => _isLoadingMore = true);
    try {
      final page = await widget.apiService.searchSales(
        saleId: params['saleId'] as int?,
        webkassaCheckNumber: params['webkassa'] as String?,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        page: _currentPage + 1,
      );
      if (!mounted) return;
      setState(() {
        _filteredSales.addAll(page.data);
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

  String _formatDate(DateTime dt) {
    final t = TimeUtil.toUtcPlus5Wall(dt);
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate(bool isFrom) async {
    final initial = isFrom ? (_dateFrom ?? DateTime.now()) : (_dateTo ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
      });
    }
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
              '№${sale.id} • ${_formatDate(sale.createdAt)} • к-во: ${sale.totalQty}',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                SaleStatusChip(sale: sale),
                const SizedBox(width: 8),
                Expanded(
                  child: SalePaymentChip(sale: sale, compact: true),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final result = await context.push<bool>('/sales/sale/${sale.id}');
          if (result == true && mounted) _search();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMore = _currentPage < _lastPage;

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
                child: Text(
                  'Поиск продажи',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _internalIdController,
                decoration: const InputDecoration(
                  labelText: 'Внутренний чек (№ продажи)',
                  hintText: 'Например: 1523',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.receipt_long),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _webkassaCheckController,
                decoration: const InputDecoration(
                  labelText: 'Чек WebKassa',
                  hintText: 'Фискальный номер',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.verified_outlined),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(true),
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        _dateFrom != null
                            ? _formatDate(_dateFrom!).split(' ').first
                            : 'Дата от',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(false),
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        _dateTo != null
                            ? _formatDate(_dateTo!).split(' ').first
                            : 'Дата до',
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isSearching ? null : _search,
                icon: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search, size: 20),
                label: Text(_isSearching ? 'Поиск...' : 'Искать'),
              ),
              if (_searched) ...[
                const SizedBox(height: 16),
                Text(
                  'Найдено: $_total',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: !_searched
              ? const SizedBox.shrink()
              : _filteredSales.isEmpty
                  ? Center(
                      child: Text(
                        'Нет продаж по заданным условиям',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredSales.length + (hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _filteredSales.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        return _buildSaleTile(_filteredSales[index]);
                      },
                    ),
        ),
      ],
    );
  }
}
