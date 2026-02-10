import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/sale.dart';
import '../services/api_service.dart';

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
  List<Sale> _allSales = [];
  List<Sale> _filteredSales = [];
  bool _isLoading = true;
  bool _searched = false;
  String? _error;
  final _saleIdController = TextEditingController();
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saleIdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final sales = await widget.apiService.getSales();
      if (!mounted) return;
      setState(() {
        _allSales = sales;
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

  void _search() {
    final saleIdText = _saleIdController.text.trim();
    final saleId = saleIdText.isEmpty ? null : int.tryParse(saleIdText);

    var list = List<Sale>.from(_allSales);

    if (saleId != null) {
      list = list.where((s) => s.id == saleId).toList();
    }

    if (_dateFrom != null) {
      final from = DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day);
      list = list.where((s) => s.createdAt.isAfter(from) || s.createdAt.isAtSameMomentAs(from)).toList();
    }
    if (_dateTo != null) {
      final to = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59);
      list = list.where((s) => s.createdAt.isBefore(to) || s.createdAt.isAtSameMomentAs(to)).toList();
    }

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    setState(() {
      _filteredSales = list;
      _searched = true;
    });
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                          const SizedBox(height: 16),
                          Text(_error!),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _saleIdController,
                            decoration: const InputDecoration(
                              labelText: 'Номер чека',
                              hintText: 'Необязательно',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.receipt_long),
                            ),
                            keyboardType: TextInputType.number,
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
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _search,
                            icon: const Icon(Icons.search, size: 20),
                            label: const Text('Искать'),
                          ),
                          const SizedBox(height: 24),
                          if (_searched) ...[
                            Text(
                              'Найдено: ${_filteredSales.length}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            if (_filteredSales.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    'Нет продаж по заданным условиям',
                                    style: TextStyle(color: AppColors.muted),
                                  ),
                                ),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _filteredSales.length,
                                itemBuilder: (context, index) {
                                  final sale = _filteredSales[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: sale.isReturned
                                            ? AppColors.muted.withValues(alpha: 0.3)
                                            : AppColors.primaryLight,
                                        child: Icon(
                                          Icons.receipt,
                                          color: sale.isReturned
                                              ? AppColors.muted
                                              : AppColors.primary,
                                        ),
                                      ),
                                      title: Text(
                                        '${sale.totalPrice.toStringAsFixed(2)} ₸',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '№${sale.id} • ${_formatDate(sale.createdAt)}',
                                              style: TextStyle(
                                                color: AppColors.muted,
                                                fontSize: 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: sale.isReturned
                                                  ? AppColors.muted.withValues(alpha: 0.2)
                                                  : AppColors.primaryLight.withValues(alpha: 0.5),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              sale.isReturned ? 'Возврат' : 'Продажа',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: sale.isReturned
                                                    ? AppColors.muted
                                                    : AppColors.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () async {
                                        final result = await context.push<bool>(
                                          '/sales/sale/${sale.id}',
                                        );
                                        if (result == true && mounted) _load();
                                      },
                                    ),
                                  );
                                },
                              ),
                          ],
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}
