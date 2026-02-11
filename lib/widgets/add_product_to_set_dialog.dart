import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/product.dart';
import '../services/api_service.dart';

/// Результат выбора товара для добавления в сет.
class AddProductToSetResult {
  const AddProductToSetResult({
    required this.product,
    required this.quantity,
  });

  final Product product;
  final double quantity;
}

/// Диалог выбора товара и количества для добавления в сет.
class AddProductToSetDialog extends StatefulWidget {
  const AddProductToSetDialog({
    super.key,
    required this.apiService,
    required this.excludedProductIds,
  });

  final ApiService apiService;
  final Set<int> excludedProductIds;

  @override
  State<AddProductToSetDialog> createState() => _AddProductToSetDialogState();
}

class _AddProductToSetDialogState extends State<AddProductToSetDialog> {
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  String _searchQuery = '';
  bool _isLoading = true;
  String? _error;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await widget.apiService.getProducts();
      final sorted =
          List<Product>.from(list)..sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _products = sorted;
        _filterProducts();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Не удалось загрузить товары';
        _isLoading = false;
      });
    }
  }

  void _filterProducts() {
    final query = _searchQuery.toLowerCase().trim();
    if (query.isEmpty) {
      _filteredProducts = _products
          .where((p) => !widget.excludedProductIds.contains(p.id))
          .toList();
    } else {
      _filteredProducts = _products
          .where((p) =>
              !widget.excludedProductIds.contains(p.id) &&
              p.name.toLowerCase().contains(query))
          .toList();
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _filterProducts();
    });
  }

  Future<void> _selectProduct(Product product) async {
    final quantity = await showDialog<double>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: '1');
        return AlertDialog(
          title: Text('Количество: ${product.name}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Количество',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              final v = double.tryParse(
                controller.text.replaceFirst(',', '.').trim(),
              );
              if (v != null && v > 0) {
                Navigator.of(ctx).pop(v);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(
                  controller.text.replaceFirst(',', '.').trim(),
                );
                if (v != null && v > 0) {
                  Navigator.of(ctx).pop(v);
                }
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );
    if (quantity != null && quantity > 0 && mounted) {
      Navigator.pop(context, AddProductToSetResult(product: product, quantity: quantity));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 500),
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
                      : _filteredProducts.isEmpty
                          ? Center(
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
                                    'Нет товаров для добавления',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
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
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
