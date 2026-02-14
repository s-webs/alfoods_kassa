import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../utils/barcode_generator.dart';
import '../utils/toast.dart';
import '../utils/barcode_image_helper.dart';

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
  late TextEditingController _newNameController;
  late TextEditingController _priceController;
  late TextEditingController _discountPriceController;
  late TextEditingController _stockController;
  late TextEditingController _stockThresholdController;
  late TextEditingController _purchasePriceController;
  late TextEditingController _barcodeController;

  int? _selectedCategoryId;
  String _selectedUnit = 'pcs';
  bool _isActive = true;
  bool _isSaving = false;
  String? _error;
  Uint8List? _barcodePreviewBytes;
  Timer? _barcodePreviewTimer;

  static const List<String> _units = ['pcs', 'g'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _newNameController = TextEditingController();
    _priceController = TextEditingController();
    _discountPriceController = TextEditingController();
    _stockController = TextEditingController();
    _stockThresholdController = TextEditingController();
    _purchasePriceController = TextEditingController();
    _barcodeController = TextEditingController();
    _updateFromProduct(widget.product);
    _barcodeController.addListener(_scheduleBarcodePreview);
  }

  void _scheduleBarcodePreview() {
    _barcodePreviewTimer?.cancel();
    _barcodePreviewTimer = Timer(const Duration(milliseconds: 400), _refreshBarcodePreview);
  }

  Future<void> _refreshBarcodePreview() async {
    final s = _barcodeController.text.trim();
    if (s.isEmpty) {
      if (mounted) setState(() => _barcodePreviewBytes = null);
      return;
    }
    final bytes = await barcodeToPngBytes(s, width: 200, height: 80);
    if (mounted) setState(() => _barcodePreviewBytes = bytes);
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
    _newNameController.text = p.newName ?? '';
    _priceController.text = p.price.toString();
    _discountPriceController.text = p.discountPrice?.toString() ?? '';
    _stockController.text = p.stock.toString();
    _stockThresholdController.text = p.stockThreshold.toString();
    _purchasePriceController.text = p.purchasePrice.toString();
    _barcodeController.text = p.barcode ?? '';
    _selectedCategoryId = p.categoryId;
    _selectedUnit = p.unit;
    _isActive = p.isActive;
    _refreshBarcodePreview();
  }

  @override
  void dispose() {
    _barcodePreviewTimer?.cancel();
    _barcodeController.removeListener(_scheduleBarcodePreview);
    _nameController.dispose();
    _newNameController.dispose();
    _priceController.dispose();
    _discountPriceController.dispose();
    _stockController.dispose();
    _stockThresholdController.dispose();
    _purchasePriceController.dispose();
    _barcodeController.dispose();
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
        'category_id': _selectedCategoryId,
        'unit': _selectedUnit,
        'price': price,
        'purchase_price': double.tryParse(_purchasePriceController.text) ?? 0,
        'new_name': _newNameController.text.trim().isEmpty
            ? null
            : _newNameController.text.trim(),
        'barcode': _barcodeController.text.trim().isEmpty
            ? null
            : _barcodeController.text.trim(),
        'stock': double.tryParse(_stockController.text) ?? 0,
        'stock_threshold': double.tryParse(_stockThresholdController.text) ?? 0,
        'is_active': _isActive,
      };
      final dp = double.tryParse(_discountPriceController.text);
      if (dp != null && dp > 0) {
        data['discount_price'] = dp;
      }

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
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Название',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text('Активен'),
                      const SizedBox(width: 8),
                      Switch(
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _newNameController,
                    decoration: const InputDecoration(
                      labelText: 'New name',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    initialValue: _selectedCategoryId,
                    decoration: const InputDecoration(labelText: 'Категория'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Без категории')),
                      ...widget.categories.map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
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
                    controller: _purchasePriceController,
                    decoration: const InputDecoration(
                        labelText: 'Закупочная цена'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _discountPriceController,
                    decoration: const InputDecoration(
                      labelText: 'Цена со скидкой',
                    ),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _barcodeController,
                          decoration: const InputDecoration(
                            labelText: 'Штрихкод',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton(
                          onPressed: () {
                            _barcodeController.text = generateBarcode();
                            _refreshBarcodePreview();
                          },
                          child: const Text('Сгенерировать'),
                        ),
                      ),
                    ],
                  ),
                  if (_barcodePreviewBytes != null) ...[
                    const SizedBox(height: 12),
                    const Text('Превью штрихкода', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    const SizedBox(height: 4),
                    Image.memory(
                      _barcodePreviewBytes!,
                      height: 56,
                      fit: BoxFit.contain,
                    ),
                  ],
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
