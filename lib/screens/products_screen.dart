import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

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
      final trimmed = s
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.$'), '');
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
        _sortAsc =
            (key == _ProductsSortKey.name || key == _ProductsSortKey.stock);
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

  Widget _buildTableHeader(List<Product> sortedProducts) {
    final allSelected =
        sortedProducts.isNotEmpty &&
        sortedProducts.every((p) => _selectedProductIds.contains(p.id));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: AppColors.primaryLight.withValues(alpha: 0.5),
      child: Row(
        children: [
          SizedBox(
            width: _colCheck,
            child: Center(
              child: Checkbox(
                value: allSelected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedProductIds.clear();
                      _selectedProductIds.addAll(
                        sortedProducts.map((p) => p.id),
                      );
                      _selectedProduct = null;
                    } else {
                      _selectedProductIds.removeWhere(
                        (id) => sortedProducts.any((p) => p.id == id),
                      );
                      _selectedProduct = null;
                    }
                  });
                },
              ),
            ),
          ),
          SizedBox(
            width: _colId,
            child: _sortHeader('ID', _ProductsSortKey.id),
          ),
          Expanded(child: _sortHeader('Название', _ProductsSortKey.name)),
          SizedBox(
            width: _colStock,
            child: _sortHeader('Остатки', _ProductsSortKey.stock),
          ),
          SizedBox(
            width: _colPurchase,
            child: _sortHeader('Цена закупа', _ProductsSortKey.purchasePrice),
          ),
          SizedBox(
            width: _colPrice,
            child: _sortHeader('Цена', _ProductsSortKey.price),
          ),
          const SizedBox(width: _colDiscount, child: Text('Цена со скидкой')),
          const SizedBox(width: _colCost, child: Text('Сумма закупа')),
          const SizedBox(width: _colValue, child: Text('Сумма')),
          const SizedBox(width: _colActive, child: Text('Активен')),
          const SizedBox(width: _colActions, child: Text('Действия')),
        ],
      ),
    );
  }

  Widget _buildProductRow(Product p, List<Product> sortedProducts) {
    final stockStr = p.unit == 'pcs'
        ? p.stock.toStringAsFixed(0)
        : _formatStock(p.stock);
    final purchaseCost = p.purchasePrice * p.stock;
    final stockValue = p.stock * p.effectivePrice;
    final isSelected = _selectedProduct?.id == p.id;
    final isChecked = _selectedProductIds.contains(p.id);
    return Material(
      color: isSelected
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      child: InkWell(
        onTap: () {
          setState(() {
            if (_selectedProductIds.contains(p.id)) {
              _selectedProductIds.remove(p.id);
              _selectedProduct = null;
            } else {
              _selectedProductIds.clear();
              _selectedProductIds.add(p.id);
              _selectedProduct = p;
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: _colCheck,
                child: Center(
                  child: Checkbox(
                    value: isChecked,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedProductIds.add(p.id);
                          _selectedProduct = sortedProducts.length == 1
                              ? p
                              : null;
                          if (_selectedProductIds.length == 1)
                            _selectedProduct = p;
                        } else {
                          _selectedProductIds.remove(p.id);
                          _selectedProduct = null;
                        }
                      });
                    },
                  ),
                ),
              ),
              SizedBox(width: _colId, child: Text('${p.id}')),
              Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
              SizedBox(
                width: _colStock,
                child: p.stock <= p.stockThreshold
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
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
              SizedBox(
                width: _colPurchase,
                child: Text(p.purchasePrice.toStringAsFixed(2)),
              ),
              SizedBox(
                width: _colPrice,
                child: Text(p.price.toStringAsFixed(2)),
              ),
              SizedBox(
                width: _colDiscount,
                child: Text(
                  p.discountPrice != null
                      ? p.discountPrice!.toStringAsFixed(2)
                      : '-',
                ),
              ),
              SizedBox(
                width: _colCost,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
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
              SizedBox(
                width: _colValue,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
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
              SizedBox(
                width: _colActive,
                child: _togglingActiveProductId == p.id
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Switch(
                        value: p.isActive,
                        onChanged: (_) => _toggleProductActive(p),
                      ),
              ),
              SizedBox(
                width: _colActions,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final result = await context.push<bool>(
                          '/products/${p.id}/edit',
                        );
                        if (result == true && mounted) _load(silent: true);
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete, color: AppColors.danger),
                      onPressed: () => _deleteProduct(p),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
      await widget.apiService.updateProduct(p.id, {'is_active': !p.isActive});
      if (!mounted) return;
      _load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
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

  static const double _colCheck = 48, _colId = 52, _colStock = 88;
  static const double _colPurchase = 110, _colPrice = 72, _colDiscount = 80;
  static const double _colCost = 92,
      _colValue = 100,
      _colActive = 64,
      _colActions = 100;

  String get _categoryFilterName {
    if (_selectedCategoryId == null ||
        _selectedCategoryId == _allCategoriesId) {
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

  /// Печать остатков (заканчивающихся товаров) — открывает системное окно печати.
  Future<void> _printLowStock() async {
    final lowStock = _products
        .where((p) => p.stock <= p.stockThreshold)
        .toList();
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
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Остатки_заканчивающихся',
        format: PdfPageFormat.a4,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка печати: $e')));
    }
  }

  Future<void> _printProductsTable(
    List<Product> list,
    String variantName,
  ) async {
    if (list.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Нет товаров для печати')));
      return;
    }
    try {
      Uint8List bytes;
      switch (variantName) {
        case 'name_barcode_stock':
          bytes = await LabelPdfService.buildProductsPrintNameBarcodeStock(
            list,
          );
          break;
        case 'name_price':
          bytes = await LabelPdfService.buildProductsPrintNamePrice(list);
          break;
        case 'full':
          bytes = await LabelPdfService.buildProductsPrintFull(list);
          break;
        default:
          return;
      }
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Товары_$variantName',
        format: PdfPageFormat.a4,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка печати: $e')));
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
    final List<Product> sortedProducts = List<Product>.from(visibleProducts)
      ..sort(_compareProducts);

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
              PopupMenuButton<String>(
                icon: const Icon(Icons.print, size: 20),
                tooltip: 'Печать',
                onSelected: (value) {
                  final list = sortedProducts;
                  if (value == 'low_stock') {
                    _printLowStock();
                  } else {
                    _printProductsTable(list, value);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'name_barcode_stock',
                    child: ListTile(
                      leading: Icon(Icons.print),
                      title: Text('Название / Штрихкод / остаток'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'name_price',
                    child: ListTile(
                      leading: Icon(Icons.print),
                      title: Text('Название / цена'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'full',
                    child: ListTile(
                      leading: Icon(Icons.print),
                      title: Text(
                        'Название / остаток / цена прихода / цена / суммы',
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'low_stock',
                    child: ListTile(
                      leading: Icon(Icons.inventory),
                      title: Text('Печать остатков'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
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
                              return SizedBox(
                                width: constraints.maxWidth,
                                height: constraints.maxHeight,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildTableHeader(sortedProducts),
                                    Expanded(
                                      child: ListView.builder(
                                        itemCount: sortedProducts.length,
                                        itemBuilder: (context, index) {
                                          return _buildProductRow(
                                            sortedProducts[index],
                                            sortedProducts,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
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
