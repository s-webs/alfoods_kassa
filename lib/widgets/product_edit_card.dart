import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../utils/toast.dart';

class ProductEditCard extends StatefulWidget {
  const ProductEditCard({
    super.key,
    required this.product,
    required this.apiService,
    required this.categories,
  required this.onSaved,
  required this.onDeleted,
  required this.onOpenFullEdit,
  required this.onClose,
  });

  final Product product;
  final ApiService apiService;
  final List<Category> categories;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;
  final Future<void> Function() onOpenFullEdit;
  final VoidCallback onClose;

  @override
  State<ProductEditCard> createState() => _ProductEditCardState();
}

class _ProductEditCardState extends State<ProductEditCard> {
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _stockController;
  late TextEditingController _stockThresholdController;
  late TextEditingController _purchasePriceController;

  String _selectedUnit = 'pcs';
  bool _isSaving = false;
  String? _error;

  static const List<String> _units = ['pcs', 'g'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _priceController = TextEditingController();
    _stockController = TextEditingController();
    _stockThresholdController = TextEditingController();
    _purchasePriceController = TextEditingController();
    _updateFromProduct(widget.product);
  }

  @override
  void didUpdateWidget(ProductEditCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      _updateFromProduct(widget.product);
    }
  }

  void _updateFromProduct(Product p) {
    _nameController.text = p.name;
    _priceController.text = p.price.toString();
    _stockController.text = p.stock.toString();
    _stockThresholdController.text = p.stockThreshold.toString();
    _purchasePriceController.text = p.purchasePrice.toString();
    _selectedUnit = p.unit;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _stockThresholdController.dispose();
    _purchasePriceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text);
    if (name.isEmpty) {
      showToast(context, 'Введите название');
      return;
    }
    if (price == null || price < 0) {
      showToast(context, 'Введите корректную цену');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{
        'name': name,
        'unit': _selectedUnit,
        'price': price,
        'purchase_price': double.tryParse(_purchasePriceController.text) ?? 0,
        'stock': double.tryParse(_stockController.text) ?? 0,
        'stock_threshold': double.tryParse(_stockThresholdController.text) ?? 0,
      };

      await widget.apiService.updateProduct(widget.product.id, data);
      if (!mounted) return;
      setState(() => _isSaving = false);
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Не удалось сохранить';
      });
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: Text(
          'Товар «${widget.product.name}» будет удалён безвозвратно.',
        ),
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
      await widget.apiService.deleteProduct(widget.product.id);
      if (!mounted) return;
      widget.onDeleted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось удалить');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: AppColors.muted.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Карточка товара',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedUnit,
                    decoration: const InputDecoration(labelText: 'Единица'),
                    items: _units
                        .map((u) => DropdownMenuItem(
                              value: u,
                              child: Text(u == 'pcs' ? 'шт.' : 'г'),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedUnit = v ?? 'pcs'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(labelText: 'Цена'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _stockController,
                    decoration: const InputDecoration(labelText: 'Остаток'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _stockThresholdController,
                    decoration: const InputDecoration(
                      labelText: 'Порог остатков',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _purchasePriceController,
                    decoration: const InputDecoration(
                        labelText: 'Закупочная цена'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Сохранить'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : () => widget.onOpenFullEdit(),
                    icon: const Icon(Icons.edit),
                    label: const Text('Полное редактирование'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _isSaving ? null : _delete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                    child: const Text('Удалить'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
