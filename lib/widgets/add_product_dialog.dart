import 'dart:async';

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
    this.activeOnly = true,
  });

  final ApiService apiService;
  final void Function(Product)? onAddProduct;
  final void Function(ProductSet)? onAddSet;
  /// When false, inactive products and sets are included (e.g. cashier).
  final bool activeOnly;

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog>
    with SingleTickerProviderStateMixin {
  final List<Product> _products = [];
  final List<ProductSet> _sets = [];
  final _searchController = TextEditingController();
  final ScrollController _productScrollController = ScrollController();
  final ScrollController _setScrollController = ScrollController();
  late TabController _tabController;

  String _searchQuery = '';
  bool _isLoading = true;
  bool _isLoadingMoreProducts = false;
  bool _isLoadingMoreSets = false;
  String? _error;
  Timer? _searchDebounce;

  int _productPage = 1;
  int _productTotal = 0;
  bool _hasMoreProducts = false;

  int _setPage = 1;
  int _setTotal = 0;
  bool _hasMoreSets = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _productScrollController.addListener(_onProductScroll);
    _setScrollController.addListener(_onSetScroll);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _productScrollController.dispose();
    _setScrollController.dispose();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String? get _search => _searchQuery.trim().isEmpty ? null : _searchQuery.trim();

  void _onProductScroll() {
    if (_isLoadingMoreProducts || !_hasMoreProducts) return;
    if (_productScrollController.position.pixels >=
        _productScrollController.position.maxScrollExtent - 120) {
      _loadMoreProducts();
    }
  }

  void _onSetScroll() {
    if (_isLoadingMoreSets || !_hasMoreSets) return;
    if (_setScrollController.position.pixels >=
        _setScrollController.position.maxScrollExtent - 120) {
      _loadMoreSets();
    }
  }

  Future<void> _loadProducts({bool reset = false}) async {
    if (reset) {
      _productPage = 1;
      _productTotal = 0;
      _hasMoreProducts = false;
      _products.clear();
    }
    final result = await widget.apiService.getProductsPaginated(
      page: reset ? 1 : _productPage + 1,
      active: widget.activeOnly ? true : null,
      search: _search,
    );
    if (!mounted) return;
    setState(() {
      if (reset) {
        _products
          ..clear()
          ..addAll(result.data);
      } else {
        _products.addAll(result.data);
      }
      _productPage = result.currentPage;
      _productTotal = result.total;
      _hasMoreProducts = result.hasMore;
    });
  }

  Future<void> _loadSets({bool reset = false}) async {
    if (reset) {
      _setPage = 1;
      _setTotal = 0;
      _hasMoreSets = false;
      _sets.clear();
    }
    final result = await widget.apiService.getSetsPaginated(
      page: reset ? 1 : _setPage + 1,
      active: widget.activeOnly ? true : null,
      search: _search,
    );
    if (!mounted) return;
    setState(() {
      if (reset) {
        _sets
          ..clear()
          ..addAll(result.data);
      } else {
        _sets.addAll(result.data);
      }
      _setPage = result.currentPage;
      _setTotal = result.total;
      _hasMoreSets = result.hasMore;
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await Future.wait([
        _loadProducts(reset: true),
        _loadSets(reset: true),
      ]);
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить данные';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMoreProducts || !_hasMoreProducts) return;
    setState(() => _isLoadingMoreProducts = true);
    try {
      await _loadProducts(reset: false);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _isLoadingMoreProducts = false);
    }
  }

  Future<void> _loadMoreSets() async {
    if (_isLoadingMoreSets || !_hasMoreSets) return;
    setState(() => _isLoadingMoreSets = true);
    try {
      await _loadSets(reset: false);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _isLoadingMoreSets = false);
    }
  }

  Future<void> _reloadCatalog() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadProducts(reset: true),
        _loadSets(reset: true),
      ]);
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить данные';
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), _reloadCatalog);
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
                        hintText: 'Поиск по названию или штрихкоду...',
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
              tabs: [
                Tab(text: _productTotal > 0 ? 'Товары ($_productTotal)' : 'Товары'),
                Tab(text: _setTotal > 0 ? 'Сеты ($_setTotal)' : 'Сеты'),
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
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _load,
                                child: const Text('Повторить'),
                              ),
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
    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: AppColors.muted),
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
      controller: _productScrollController,
      itemCount: _products.length + (_hasMoreProducts ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _products.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _isLoadingMoreProducts
                  ? const CircularProgressIndicator()
                  : const SizedBox.shrink(),
            ),
          );
        }
        final p = _products[index];
        return ListTile(
          title: Text(p.name),
          subtitle: Text(
            '${p.effectivePrice.toStringAsFixed(2)} ₸ • ${p.unit}',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          trailing: const Icon(Icons.add),
          onTap: () => _selectProduct(p),
        );
      },
    );
  }

  Widget _buildSetList() {
    if (_sets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: AppColors.muted),
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
      controller: _setScrollController,
      itemCount: _sets.length + (_hasMoreSets ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _sets.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _isLoadingMoreSets
                  ? const CircularProgressIndicator()
                  : const SizedBox.shrink(),
            ),
          );
        }
        final s = _sets[index];
        return ListTile(
          title: Text(s.name),
          subtitle: Text(
            '${s.effectivePrice.toStringAsFixed(2)} ₸ • шт',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          trailing: const Icon(Icons.add),
          onTap: () => _selectSet(s),
        );
      },
    );
  }
}
