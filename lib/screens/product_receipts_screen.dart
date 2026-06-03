import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/product_receipt.dart';
import '../models/supplier.dart';
import '../services/api_service.dart';
import '../utils/time_util.dart';

class ProductReceiptsScreen extends StatefulWidget {
  const ProductReceiptsScreen({
    super.key,
    required this.apiService,
  });

  final ApiService apiService;

  @override
  State<ProductReceiptsScreen> createState() => _ProductReceiptsScreenState();
}

class _ProductReceiptsScreenState extends State<ProductReceiptsScreen> {
  List<ProductReceipt> _receipts = [];
  List<Supplier> _suppliers = [];
  bool _isLoading = true;
  String? _error;

  int? _supplierId;
  String? _dateFrom;
  String? _dateTo;
  final _dateFromController = TextEditingController();
  final _dateToController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    _load();
  }

  @override
  void dispose() {
    _dateFromController.dispose();
    _dateToController.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await widget.apiService.getSuppliers();
      if (!mounted) return;
      setState(() => _suppliers = suppliers);
    } catch (_) {}
  }

  void _setDateFrom(DateTime? date) {
    if (date == null) return;
    setState(() {
      _dateFrom =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      _dateFromController.text = _dateFrom!;
    });
  }

  void _setDateTo(DateTime? date) {
    if (date == null) return;
    setState(() {
      _dateTo =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      _dateToController.text = _dateTo!;
    });
  }

  void _resetFilters() {
    setState(() {
      _supplierId = null;
      _dateFrom = null;
      _dateTo = null;
      _dateFromController.clear();
      _dateToController.clear();
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final receipts = await widget.apiService.getProductReceipts(
        supplierId: _supplierId,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      if (!mounted) return;
      setState(() {
        _receipts = receipts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить поступления';
        _isLoading = false;
      });
    }
  }

  String _formatDate(DateTime dt) {
    final t = TimeUtil.toUtcPlus5Wall(dt);
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
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
                    child: Text(
                      'Поступления товара',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => context.push('/product-receipts/create'),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Добавить'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<int?>(
                        key: ValueKey(_supplierId),
                        initialValue: _supplierId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Поставщик',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Все'),
                          ),
                          ..._suppliers.map(
                            (s) => DropdownMenuItem<int?>(
                              value: s.id,
                              child: Text(s.name),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _supplierId = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 130,
                      child: TextFormField(
                        controller: _dateFromController,
                        decoration: const InputDecoration(
                          labelText: 'Дата с',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        readOnly: true,
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          _setDateFrom(date);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 130,
                      child: TextFormField(
                        controller: _dateToController,
                        decoration: const InputDecoration(
                          labelText: 'Дата по',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        readOnly: true,
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          _setDateTo(date);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Искать'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _resetFilters,
                    child: const Text('Сбросить'),
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
                          Text(
                            _error!,
                            style: TextStyle(color: AppColors.danger),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _receipts.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    size: 64,
                                    color: AppColors.muted,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Нет поступлений',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _receipts.length,
                              itemBuilder: (context, index) {
                                final receipt = _receipts[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.accent
                                          .withValues(alpha: 0.2),
                                      child: Icon(
                                        Icons.inventory_2,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                    title: Text(
                                      '${receipt.totalPrice.toStringAsFixed(2)} ₸',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(receipt.supplierDisplayName),
                                        Text(
                                          _formatDate(receipt.createdAt),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: Text(
                                      '${receipt.items.length} шт.',
                                      style: TextStyle(
                                        color: AppColors.muted,
                                      ),
                                    ),
                                    onTap: () => context.push(
                                      '/product-receipts/${receipt.id}',
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
