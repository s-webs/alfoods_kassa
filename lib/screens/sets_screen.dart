import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/product_set.dart';
import '../services/api_service.dart';
import '../utils/toast.dart';

class SetsScreen extends StatefulWidget {
  const SetsScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<SetsScreen> createState() => _SetsScreenState();
}

enum _SetsSortKey { id, name, price }

class _SetsScreenState extends State<SetsScreen> {
  List<ProductSet> _sets = [];
  String _searchQuery = '';
  bool _isLoading = true;
  int? _togglingActiveSetId;
  String? _error;
  _SetsSortKey _sortKey = _SetsSortKey.id;
  bool _sortAsc = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final list = await widget.apiService.getSets();
      if (!mounted) return;
      setState(() {
        _sets = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить сеты';
        _isLoading = false;
      });
    }
  }

  int _compareSets(ProductSet a, ProductSet b) {
    int cmp;
    switch (_sortKey) {
      case _SetsSortKey.id:
        cmp = a.id.compareTo(b.id);
        break;
      case _SetsSortKey.name:
        cmp = a.name.compareTo(b.name);
        break;
      case _SetsSortKey.price:
        cmp = a.price.compareTo(b.price);
        break;
    }
    return _sortAsc ? cmp : -cmp;
  }

  void _onSort(_SetsSortKey key) {
    setState(() {
      if (_sortKey == key) {
        _sortAsc = !_sortAsc;
      } else {
        _sortKey = key;
        _sortAsc = true;
      }
    });
  }

  Widget _sortHeader(String title, _SetsSortKey key) {
    final isActive = _sortKey == key;
    return InkWell(
      onTap: () => _onSort(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            const SizedBox(width: 4),
            Icon(
              isActive
                  ? (_sortAsc ? Icons.arrow_upward : Icons.arrow_downward)
                  : Icons.unfold_more,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  String _itemsSummary(ProductSet s) {
    if (s.items.isEmpty) return '—';
    return s.items
        .map((i) =>
            '${i.product?.name ?? 'ID:${i.productId}'} × ${i.quantity.toStringAsFixed(i.quantity == i.quantity.roundToDouble() ? 0 : 2)}')
        .join(', ');
  }

  Future<void> _toggleSetActive(ProductSet s) async {
    setState(() => _togglingActiveSetId = s.id);
    try {
      await widget.apiService.updateSet(s.id, {'is_active': !s.isActive});
      if (!mounted) return;
      _load(silent: true);
    } catch (e) {
      if (mounted) {
        showToast(context, 'Ошибка: $e');
      }
    } finally {
      if (mounted) setState(() => _togglingActiveSetId = null);
    }
  }

  Future<void> _deleteSet(ProductSet s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сет?'),
        content: Text('Сет «${s.name}» будет удалён безвозвратно.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await widget.apiService.deleteSet(s.id);
      if (!mounted) return;
      _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось удалить');
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final visibleSets = query.isEmpty
        ? _sets
        : _sets.where((s) {
            final idStr = s.id.toString();
            final name = s.name.toLowerCase();
            final barcode = (s.barcode ?? '').toLowerCase();
            return idStr.contains(query) ||
                name.contains(query) ||
                barcode.contains(query);
          }).toList();
    final sortedSets = List<ProductSet>.from(visibleSets)..sort(_compareSets);

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
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Поиск (id, штрихкод, название)',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () async {
                  final result = await context.push<bool>('/sets/create');
                  if (result == true && mounted) _load(silent: true);
                },
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Добавить'),
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
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: AppColors.danger,
                          ),
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
                  : _sets.isEmpty
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
                                'Нет сетов',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        )
                      : Container(
                          color: Colors.white,
                          width: double.infinity,
                          child: RefreshIndicator(
                            onRefresh: () => _load(silent: true),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  scrollDirection: Axis.horizontal,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minWidth: constraints.maxWidth,
                                      ),
                                      child: DataTable(
                                        headingRowColor: WidgetStateProperty.all(
                                          AppColors.primaryLight.withValues(alpha: 0.5),
                                        ),
                                        columnSpacing: 16,
                                        horizontalMargin: 8,
                                        columns: [
                                          DataColumn(
                                            label: _sortHeader('ID', _SetsSortKey.id),
                                          ),
                                          DataColumn(
                                            label: _sortHeader('Название', _SetsSortKey.name),
                                          ),
                                          DataColumn(
                                            label: _sortHeader('Цена', _SetsSortKey.price),
                                          ),
                                          const DataColumn(label: Text('Цена со скидкой')),
                                          const DataColumn(label: Text('Штрихкод')),
                                          const DataColumn(label: Text('Активен')),
                                          const DataColumn(label: Text('Состав')),
                                          const DataColumn(label: Text('Действия')),
                                        ],
                                        rows: sortedSets.map((s) {
                                          return DataRow(
                                            cells: [
                                              DataCell(Text('${s.id}')),
                                              DataCell(Text(s.name)),
                                              DataCell(Text(s.price.toStringAsFixed(2))),
                                              DataCell(Text(
                                                s.discountPrice != null
                                                    ? s.discountPrice!.toStringAsFixed(2)
                                                    : '-',
                                              )),
                                              DataCell(Text(s.barcode ?? '-')),
                                              DataCell(
                                                _togglingActiveSetId == s.id
                                                    ? const SizedBox(
                                                        width: 24,
                                                        height: 24,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                      )
                                                    : Switch(
                                                        value: s.isActive,
                                                        onChanged: (_) =>
                                                            _toggleSetActive(s),
                                                      ),
                                              ),
                                              DataCell(
                                                ConstrainedBox(
                                                  constraints: const BoxConstraints(
                                                    maxWidth: 200,
                                                  ),
                                                  child: Text(
                                                    _itemsSummary(s),
                                                    overflow: TextOverflow.ellipsis,
                                                    maxLines: 2,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: AppColors.muted,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.edit),
                                                      onPressed: () async {
                                                        final result =
                                                            await context.push<bool>(
                                                          '/sets/${s.id}/edit',
                                                        );
                                                        if (result == true && mounted) {
                                                          _load(silent: true);
                                                        }
                                                      },
                                                    ),
                                                    IconButton(
                                                      icon: Icon(
                                                        Icons.delete,
                                                        color: AppColors.danger,
                                                      ),
                                                      onPressed: () => _deleteSet(s),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
        ),
      ],
    );
  }
}
