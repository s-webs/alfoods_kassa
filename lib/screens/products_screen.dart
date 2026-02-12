import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/label_pdf_service.dart';
import '../widgets/product_edit_card.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

enum _ProductsSortKey { id, name, stock, price, purchasePrice }

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product> _products = [];
  List<Category> _categories = [];
  int? _selectedCategoryId;
  Product? _selectedProduct;
  String _searchQuery = '';
  Set<int> _selectedProductIds = {};
  bool _isLoading = true;
  int? _togglingActiveProductId;
  String? _error;
  _ProductsSortKey _sortKey = _ProductsSortKey.id;
  bool _sortAsc = false; // по умолчанию id по убыванию (новые сверху)

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Форматирование остатка для граммовых товаров без округления (1.5 → "1.5", 2 → "2").
  static String _formatStock(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    final s = value.toStringAsFixed(2);
    if (s.contains('.')) {
      final trimmed = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      return trimmed;
    }
    return s;
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final products = await widget.apiService.getProducts(
        categoryId: _selectedCategoryId,
      );
      final categories = await widget.apiService.getCategories();
      if (!mounted) return;
      setState(() {
        _products = products;
        _categories = categories;
        if (_selectedProduct != null) {
          final idx = products.indexWhere((p) => p.id == _selectedProduct!.id);
          _selectedProduct = idx >= 0 ? products[idx] : null;
        }
        _selectedProductIds.removeWhere(
          (id) => !products.any((p) => p.id == id),
        );
        if (_selectedProductIds.length == 1) {
          final id = _selectedProductIds.first;
          final product = products.firstWhere((p) => p.id == id);
          _selectedProduct = product;
        } else {
          _selectedProduct = null;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить товары';
        _isLoading = false;
      });
    }
  }

  int _compareProducts(Product a, Product b) {
    int cmp;
    switch (_sortKey) {
      case _ProductsSortKey.id:
        cmp = a.id.compareTo(b.id);
        break;
      case _ProductsSortKey.name:
        cmp = a.name.compareTo(b.name);
        break;
      case _ProductsSortKey.stock:
        cmp = a.stock.compareTo(b.stock);
        break;
      case _ProductsSortKey.price:
        cmp = a.price.compareTo(b.price);
        break;
      case _ProductsSortKey.purchasePrice:
        cmp = a.purchasePrice.compareTo(b.purchasePrice);
        break;
    }
    return _sortAsc ? cmp : -cmp;
  }

  void _onSort(_ProductsSortKey key) {
    setState(() {
      if (_sortKey == key) {
        _sortAsc = !_sortAsc;
      } else {
        _sortKey = key;
        _sortAsc = (key == _ProductsSortKey.name || key == _ProductsSortKey.stock);
      }
    });
  }

  Widget _sortHeader(String title, _ProductsSortKey key) {
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

  Future<void> _deleteSelectedProducts() async {
    if (_selectedProductIds.isEmpty) return;
    final count = _selectedProductIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить товары?'),
        content: Text('Будет удалено товаров: $count'),
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
      for (final id in _selectedProductIds) {
        await widget.apiService.deleteProduct(id);
      }
      if (!mounted) return;
      setState(() {
        _selectedProductIds.clear();
        _selectedProduct = null;
      });
      _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось удалить товары');
    }
  }

  Future<void> _toggleProductActive(Product p) async {
    setState(() => _togglingActiveProductId = p.id);
    try {
      await widget.apiService.updateProduct(p.id, {
        'is_active': !p.isActive,
      });
      if (!mounted) return;
      _load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _togglingActiveProductId = null);
    }
  }

  Future<void> _deleteProduct(Product p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: Text('Товар «${p.name}» будет удалён безвозвратно.'),
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
      await widget.apiService.deleteProduct(p.id);
      if (!mounted) return;
      _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось удалить');
    }
  }

  static const int _allCategoriesId = -1;

  String get _categoryFilterName {
    if (_selectedCategoryId == null || _selectedCategoryId == _allCategoriesId) {
      return 'Все';
    }
    for (final c in _categories) {
      if (c.id == _selectedCategoryId) return c.name;
    }
    return 'Все';
  }

  void _onCategoryChanged(int? id) {
    setState(() {
      _selectedCategoryId = id == _allCategoriesId ? null : id;
      _isLoading = true;
    });
    _load();
  }

  Future<void> _exportLowStockPdf() async {
    final lowStock = _products.where((p) => p.stock <= p.stockThreshold).toList();
    if (lowStock.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет заканчивающихся товаров')),
      );
      return;
    }
    try {
      final bytes = await LabelPdfService.buildLowStockReportPdf(lowStock);
      if (!mounted) return;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить PDF',
        fileName: 'zakanchivayushchiesya-tovary.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (path != null) {
        final savePath = path.endsWith('.pdf') ? path : '$path.pdf';
        await File(savePath).writeAsBytes(bytes);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сохранено: $savePath')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final List<Product> visibleProducts = query.isEmpty
        ? _products
        : _products.where((p) {
            final idStr = p.id.toString();
            final name = p.name.toLowerCase();
            final newName = (p.newName ?? '').toLowerCase();
            final barcode = (p.barcode ?? '').toLowerCase();
            return idStr.contains(query) ||
                name.contains(query) ||
                newName.contains(query) ||
                barcode.contains(query);
          }).toList();
    final List<Product> sortedProducts =
        List<Product>.from(visibleProducts)..sort(_compareProducts);

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
              if (_categories.isNotEmpty)
                PopupMenuButton<int?>(
                  onSelected: _onCategoryChanged,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.filter_list),
                        const SizedBox(width: 8),
                        Text(_categoryFilterName),
                      ],
                    ),
                  ),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _allCategoriesId,
                      child: const Text('Все категории'),
                    ),
                    ..._categories.map(
                      (c) => PopupMenuItem(value: c.id, child: Text(c.name)),
                    ),
                  ],
                ),
              if (_categories.isNotEmpty) const SizedBox(width: 8),
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Поиск (id, штрихкод, название)',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              if (_selectedProductIds.isNotEmpty) ...[
                Text(
                  'Выбрано: ${_selectedProductIds.length}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedProductIds.clear();
                      _selectedProduct = null;
                    });
                  },
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Снять выбор'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _deleteSelectedProducts,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                  ),
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Удалить'),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: _exportLowStockPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF заканчивающихся'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  final result = await context.push<bool>('/products/create');
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
              : _products.isEmpty
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
                        'Нет товаров',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        color: Colors.white,
                        child: RefreshIndicator(
                          onRefresh: () => _load(silent: true),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SingleChildScrollView(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: DataTable(
                                        showCheckboxColumn: false,
                                        headingRowColor:
                                            WidgetStateProperty.all(
                                              AppColors.primaryLight.withValues(
                                                alpha: 0.5,
                                              ),
                                            ),
                                        columnSpacing: 16,
                                        horizontalMargin: 8,
                                        columns: [
                                          DataColumn(
                                            label: Checkbox(
                                              value: sortedProducts.isNotEmpty &&
                                                  sortedProducts.every((p) =>
                                                      _selectedProductIds
                                                          .contains(p.id)),
                                              onChanged: (value) {
                                                setState(() {
                                                  if (value == true) {
                                                    _selectedProductIds
                                                      ..clear()
                                                      ..addAll(sortedProducts
                                                          .map((p) => p.id));
                                                    _selectedProduct = null;
                                                  } else {
                                                    _selectedProductIds
                                                        .removeWhere((id) =>
                                                            sortedProducts.any(
                                                                (p) =>
                                                                    p.id ==
                                                                    id));
                                                    if (_selectedProductIds
                                                        .isEmpty) {
                                                      _selectedProduct = null;
                                                    } else if (_selectedProductIds
                                                            .length ==
                                                        1) {
                                                      final id =
                                                          _selectedProductIds
                                                              .first;
                                                      _selectedProduct =
                                                          _products.firstWhere(
                                                        (prod) => prod.id == id,
                                                      );
                                                    } else {
                                                      _selectedProduct = null;
                                                    }
                                                  }
                                                });
                                              },
                                            ),
                                          ),
                                          DataColumn(
                                            label: _sortHeader('ID', _ProductsSortKey.id),
                                          ),
                                          DataColumn(
                                            label: _sortHeader('Название', _ProductsSortKey.name),
                                          ),
                                          DataColumn(
                                            label: _sortHeader('Остатки', _ProductsSortKey.stock),
                                          ),
                                          DataColumn(
                                            label: _sortHeader('Цена закупа', _ProductsSortKey.purchasePrice),
                                          ),
                                          DataColumn(
                                            label: _sortHeader('Цена', _ProductsSortKey.price),
                                          ),
                                          const DataColumn(
                                            label: Text('Цена со скидкой'),
                                          ),
                                          const DataColumn(
                                            label: Text('Сумма закупа'),
                                          ),
                                          const DataColumn(
                                            label: Text('Сумма'),
                                          ),
                                          const DataColumn(
                                            label: Text('Активен'),
                                          ),
                                          const DataColumn(
                                            label: Text('Действия'),
                                          ),
                                        ],
                                        rows: sortedProducts.map((p) {
                                          final purchaseCost =
                                              p.purchasePrice * p.stock;
                                          final stockValue = p.stock * p.price;
                                          // Штучные — целое число, граммовые — без округления (фактическое значение)
                                          final stockStr = p.unit == 'pcs'
                                              ? p.stock.toStringAsFixed(0)
                                              : _formatStock(p.stock);
                                          final isSelected =
                                              _selectedProduct?.id == p.id;
                                          final isChecked = _selectedProductIds
                                              .contains(p.id);
                                          return DataRow(
                                            selected: isSelected,
                                            cells: [
                                              DataCell(
                                                Checkbox(
                                                  value: isChecked,
                                                  onChanged: (value) {
                                                    setState(() {
                                                      if (value == true) {
                                                        _selectedProductIds.add(
                                                          p.id,
                                                        );
                                                        if (_selectedProductIds
                                                                .length ==
                                                            1) {
                                                          _selectedProduct = p;
                                                        } else {
                                                          _selectedProduct =
                                                              null;
                                                        }
                                                      } else {
                                                        _selectedProductIds
                                                            .remove(p.id);
                                                        if (_selectedProductIds
                                                            .isEmpty) {
                                                          _selectedProduct =
                                                              null;
                                                        } else if (_selectedProductIds
                                                                .length ==
                                                            1) {
                                                          final id =
                                                              _selectedProductIds
                                                                  .first;
                                                          _selectedProduct =
                                                              _products
                                                                  .firstWhere(
                                                                    (prod) =>
                                                                        prod.id ==
                                                                        id,
                                                                  );
                                                        } else {
                                                          _selectedProduct =
                                                              null;
                                                        }
                                                      }
                                                    });
                                                  },
                                                ),
                                              ),
                                              DataCell(Text('${p.id}')),
                                              DataCell(Text(p.name)),
                                              DataCell(
                                                p.stock <= p.stockThreshold
                                                    ? Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 4,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: AppColors.danger.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(8),
                                                          border: Border.all(
                                                            color: AppColors.danger.withValues(alpha: 0.5),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          stockStr,
                                                          style: const TextStyle(
                                                            color: AppColors.danger,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      )
                                                    : Text(stockStr),
                                              ),
                                              DataCell(
                                                Text(
                                                  p.purchasePrice
                                                      .toStringAsFixed(2),
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  p.price.toStringAsFixed(2),
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  p.discountPrice != null
                                                      ? p.discountPrice!
                                                            .toStringAsFixed(2)
                                                      : '-',
                                                ),
                                              ),
                                              DataCell(
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: AppColors.primary.withValues(alpha: 0.5),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    purchaseCost.toStringAsFixed(2),
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.primary,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF22c55e).withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: const Color(0xFF22c55e).withValues(alpha: 0.5),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    stockValue.toStringAsFixed(2),
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w600,
                                                      color: Color(0xFF16a34a),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                _togglingActiveProductId == p.id
                                                    ? const SizedBox(
                                                        width: 24,
                                                        height: 24,
                                                        child: CircularProgressIndicator(strokeWidth: 2),
                                                      )
                                                    : Switch(
                                                        value: p.isActive,
                                                        onChanged: (_) =>
                                                            _toggleProductActive(p),
                                                      ),
                                              ),
                                              DataCell(
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.edit,
                                                      ),
                                                      onPressed: () async {
                                                        final result =
                                                            await context.push<
                                                              bool
                                                            >(
                                                              '/products/${p.id}/edit',
                                                            );
                                                        if (result == true &&
                                                            mounted) {
                                                          _load(silent: true);
                                                        }
                                                      },
                                                    ),
                                                    IconButton(
                                                      icon: Icon(
                                                        Icons.delete,
                                                        color: AppColors.danger,
                                                      ),
                                                      onPressed: () =>
                                                          _deleteProduct(p),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            onSelectChanged: (_) {
                                              setState(() {
                                                if (_selectedProductIds
                                                    .contains(p.id)) {
                                                  _selectedProductIds.remove(
                                                    p.id,
                                                  );
                                                  _selectedProduct = null;
                                                } else {
                                                  _selectedProductIds.clear();
                                                  _selectedProductIds.add(p.id);
                                                  _selectedProduct = p;
                                                }
                                              });
                                            },
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    if (_selectedProduct != null)
                      SizedBox(
                        width: 280,
                        child: ProductEditCard(
                          key: ValueKey(_selectedProduct!.id),
                          product: _selectedProduct!,
                          apiService: widget.apiService,
                          categories: _categories,
                          onSaved: () => _load(silent: true),
                          onDeleted: () {
                            setState(() => _selectedProduct = null);
                            _load(silent: true);
                          },
                          onOpenFullEdit: () async {
                            final result = await context.push<bool>(
                              '/products/${_selectedProduct!.id}/edit',
                            );
                            if (result == true && mounted) _load(silent: true);
                          },
                          onClose: () {
                            setState(() => _selectedProduct = null);
                          },
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
