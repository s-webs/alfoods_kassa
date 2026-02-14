import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/product.dart';
import '../models/product_set.dart';
import '../services/api_service.dart';

class AddProductDialog extends StatefulWidget {
  const AddProductDialog({
    super.key,
    required this.apiService,
    this.onAddProduct,
    this.onAddSet,
  });

  final ApiService apiService;
  /// При указании — товар добавляется через callback, диалог остаётся открытым.
  final void Function(Product)? onAddProduct;
  /// При указании — сет добавляется через callback, диалог остаётся открытым.
  final void Function(ProductSet)? onAddSet;

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog>
    with SingleTickerProviderStateMixin {
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  List<ProductSet> _sets = [];
  List<ProductSet> _filteredSets = [];
  String _searchQuery = '';
  bool _isLoading = true;
  String? _error;
  final _searchController = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.apiService.getProducts(active: true),
        widget.apiService.getSets(active: true),
      ]);
      final products = results[0] as List<Product>;
      final sets = results[1] as List<ProductSet>;
      final sortedProducts =
          List<Product>.from(products)..sort((a, b) => a.name.compareTo(b.name));
      final sortedSets =
          List<ProductSet>.from(sets)..sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _products = sortedProducts;
        _sets = sortedSets;
        _filterProducts();
        _filterSets();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Не удалось загрузить данные';
        _isLoading = false;
      });
    }
  }

  void _filterProducts() {
    final query = _searchQuery.toLowerCase().trim();
    if (query.isEmpty) {
      _filteredProducts = List.from(_products);
    } else {
      _filteredProducts = _products
          .where((p) => p.name.toLowerCase().contains(query))
          .toList();
    }
  }

  void _filterSets() {
    final query = _searchQuery.toLowerCase().trim();
    if (query.isEmpty) {
      _filteredSets = List.from(_sets);
    } else {
      _filteredSets =
          _sets.where((s) => s.name.toLowerCase().contains(query)).toList();
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _filterProducts();
      _filterSets();
    });
  }

  void _selectProduct(Product product) {
    if (widget.onAddProduct != null) {
      widget.onAddProduct!(product);
    } else {
      Navigator.pop(context, product);
    }
  }

  void _selectSet(ProductSet productSet) {
    if (widget.onAddSet != null) {
      widget.onAddSet!(productSet);
    } else {
      Navigator.pop(context, productSet);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Поиск по названию...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: _onSearchChanged,
                      autofocus: true,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Товары'),
                Tab(text: 'Сеты'),
              ],
            ),
            const Divider(height: 1),
            Flexible(
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
                            ],
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildProductList(),
                            _buildSetList(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductList() {
    if (_filteredProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: AppColors.muted,
            ),
            const SizedBox(height: 16),
            Text(
              'Ничего не найдено',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        final p = _filteredProducts[index];
        return ListTile(
          title: Text(p.name),
          subtitle: Text(
            '${p.effectivePrice.toStringAsFixed(2)} ₸ • ${p.unit}',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
            ),
          ),
          trailing: const Icon(Icons.add),
          onTap: () => _selectProduct(p),
        );
      },
    );
  }

  Widget _buildSetList() {
    if (_filteredSets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: AppColors.muted,
            ),
            const SizedBox(height: 16),
            Text(
              'Ничего не найдено',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _filteredSets.length,
      itemBuilder: (context, index) {
        final s = _filteredSets[index];
        return ListTile(
          title: Text(s.name),
          subtitle: Text(
            '${s.effectivePrice.toStringAsFixed(2)} ₸ • шт',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
            ),
          ),
          trailing: const Icon(Icons.add),
          onTap: () => _selectSet(s),
        );
      },
    );
  }
}
