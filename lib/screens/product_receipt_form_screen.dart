import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/cart_item.dart';
import '../models/counterparty.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../utils/toast.dart';
import '../widgets/add_product_dialog.dart';

class ProductReceiptFormScreen extends StatefulWidget {
  const ProductReceiptFormScreen({
    super.key,
    required this.apiService,
  });

  final ApiService apiService;

  @override
  State<ProductReceiptFormScreen> createState() =>
      _ProductReceiptFormScreenState();
}

class _ProductReceiptFormScreenState extends State<ProductReceiptFormScreen> {
  final List<CartItem> _items = [];
  List<Counterparty> _counterparties = [];
  int? _selectedCounterpartyId;
  final TextEditingController _supplierNameController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final TextEditingController _barcodeController = TextEditingController();
  int? _editingPriceIndex;
  TextEditingController? _priceEditController;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isBarcodeLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCounterparties();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _barcodeFocusNode.dispose();
    _barcodeController.dispose();
    _supplierNameController.dispose();
    _priceEditController?.dispose();
    super.dispose();
  }

  Future<void> _loadCounterparties() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final counterparties = await widget.apiService.getCounterparties();
      if (!mounted) return;
      setState(() {
        _counterparties = counterparties;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить контрагентов';
        _isLoading = false;
      });
    }
  }

  Future<void> _onBarcodeSubmitted(String value) async {
    final barcode = value.trim();
    if (barcode.isEmpty) return;
    _barcodeController.clear();
    if (_isBarcodeLoading || !mounted) return;
    setState(() => _isBarcodeLoading = true);
    try {
      final result = await widget.apiService.resolveBarcode(barcode);
      if (!mounted) return;
      if (result != null) {
        if (result.isProduct && result.product != null) {
          _addProduct(result.product!);
          showToast(context, 'Добавлено: ${result.product!.name}');
        } else if (result.isSet && result.productSet != null) {
          showToast(context, 'Сеты не поддерживаются в поступлениях');
        } else {
          showToast(context, 'Товар с штрихкодом "$barcode" не найден');
        }
      } else {
        showToast(context, 'Товар с штрихкодом "$barcode" не найден');
      }
    } catch (_) {
      if (mounted) {
        showToast(context, 'Ошибка поиска товара');
      }
    } finally {
      if (mounted) setState(() => _isBarcodeLoading = false);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _barcodeFocusNode.canRequestFocus) {
            _barcodeFocusNode.requestFocus();
          }
        });
      }
    }
  }

  void _addProduct(Product product) {
    setState(() {
      final existingIndex = _items.indexWhere((item) => item.productId == product.id);
      if (existingIndex >= 0) {
        _items[existingIndex].quantity += product.unit == 'pcs' ? 1.0 : 0.1;
      } else {
        _items.insert(0, CartItem(
          productId: product.id,
          name: product.name,
          price: product.purchasePrice,
          quantity: 1,
          unit: product.unit,
        ));
      }
    });
  }

  Future<void> _showAddProductDialog() async {
    final result = await showDialog<Object>(
      context: context,
      builder: (ctx) => AddProductDialog(apiService: widget.apiService),
    );
    if (result != null && mounted) {
      if (result is Product) {
        _addProduct(result);
      }
    }
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _barcodeFocusNode.canRequestFocus) {
          _barcodeFocusNode.requestFocus();
        }
      });
    }
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      showToast(context, 'Добавьте хотя бы одну позицию');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final receipt = await widget.apiService.createProductReceipt(
        counterpartyId: _selectedCounterpartyId,
        supplierName: _selectedCounterpartyId == null && _supplierNameController.text.isNotEmpty
            ? _supplierNameController.text.trim()
            : null,
        items: _items.map((e) => e.toJson()).toList(),
      );
      if (!mounted) return;
      showToast(context, 'Поступление создано');
      context.go('/product-receipts/${receipt.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Не удалось сохранить поступление';
      });
      showToast(context, _error ?? 'Ошибка');
    }
  }

  double get _itemsTotal =>
      _items.fold(0, (sum, item) => sum + item.total);

  void _updateQuantity(int index, double delta) {
    setState(() {
      final item = _items[index];
      final step = item.unit == 'pcs' ? 1.0 : 0.1;
      item.quantity += delta * step;
      if (item.quantity <= 0) {
        _items.removeAt(index);
      }
    });
  }

  Future<void> _editQuantity(int index) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    final isPcs = item.unit == 'pcs';
    final initial = isPcs
        ? item.quantity.toInt().toString()
        : item.quantity.toStringAsFixed(2);

    final controller = TextEditingController(text: initial);
    double? parseQuantity() {
      final v = double.tryParse(
        controller.text.replaceFirst(',', '.').trim(),
      );
      if (v == null || v < 0) return null;
      if (isPcs) return v.roundToDouble();
      return v; // граммовые: любое число (0.15, 0.25 и т.д.)
    }

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Количество: ${item.name}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: isPcs ? 'Штук' : 'Кг (0.1 = 100 г)',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              final v = parseQuantity();
              if (v != null) Navigator.of(ctx).pop(v);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final v = parseQuantity();
                if (v != null) Navigator.of(ctx).pop(v);
              },
              child: const Text('Ок'),
            ),
          ],
        );
      },
    );
    if (result != null && mounted) {
      setState(() {
        if (result <= 0) {
          _items.removeAt(index);
        } else {
          _items[index].quantity = result;
        }
      });
    }
  }

  void _startEditPrice(int index) {
    if (index < 0 || index >= _items.length) return;
    setState(() {
      _editingPriceIndex = index;
      _priceEditController?.dispose();
      _priceEditController = TextEditingController(
        text: _items[index].price.toStringAsFixed(2),
      );
    });
  }

  void _finishEditPrice({bool save = true}) {
    final index = _editingPriceIndex;
    if (index == null || index < 0 || index >= _items.length) return;
    final controller = _priceEditController;
    if (controller != null && save) {
      final text = controller.text.replaceFirst(',', '.').trim();
      final value = double.tryParse(text);
      if (value != null && value >= 0) {
        setState(() {
          _items[index].price = value;
        });
      }
    }
    _priceEditController?.dispose();
    _priceEditController = null;
    _editingPriceIndex = null;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Новое поступление'),
            actions: [
              if (_isSaving)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: _save,
                ),
            ],
          ),
          body: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<int?>(
                      value: _selectedCounterpartyId,
                      decoration: const InputDecoration(
                        labelText: 'Контрагент',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Не выбран')),
                        ..._counterparties.map(
                          (c) => DropdownMenuItem<int?>(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedCounterpartyId = value;
                          if (value != null) {
                            _supplierNameController.clear();
                          }
                        });
                      },
                    ),
                    if (_selectedCounterpartyId == null) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _supplierNameController,
                        decoration: const InputDecoration(
                          labelText: 'Название поставщика',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _showAddProductDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить товар вручную'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _items.isEmpty
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
                              'Отсканируйте штрихкод товара',
                              style: TextStyle(
                                fontSize: 16,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          ..._items.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(item.name),
                                subtitle: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () => _startEditPrice(index),
                                      child: (_editingPriceIndex == index && _priceEditController != null)
                                          ? SizedBox(
                                              width: 100,
                                              child: TextField(
                                                controller: _priceEditController,
                                                autofocus: true,
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                decoration: const InputDecoration(
                                                  isDense: true,
                                                  border: OutlineInputBorder(),
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                ),
                                                onSubmitted: (_) => _finishEditPrice(save: true),
                                                onEditingComplete: () => _finishEditPrice(save: true),
                                              ),
                                            )
                                          : Text(
                                              '${item.price.toStringAsFixed(2)} ₸ × ',
                                              style: TextStyle(
                                                decoration: TextDecoration.underline,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _editQuantity(index),
                                      child: Text(
                                        '${item.quantity.toStringAsFixed(item.unit == 'pcs' ? 0 : 2)} ${item.unit}',
                                        style: TextStyle(
                                          decoration: TextDecoration.underline,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${item.total.toStringAsFixed(2)} ₸',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline),
                                      onPressed: () => _updateQuantity(index, -1),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline),
                                      onPressed: () => _updateQuantity(index, 1),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      color: AppColors.danger,
                                      onPressed: () {
                                        setState(() {
                                          _items.removeAt(index);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: AppColors.muted.withValues(alpha: 0.5)),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Итого:',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${_itemsTotal.toStringAsFixed(2)} ₸',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          child: SizedBox(
            width: 1,
            height: 1,
            child: TextField(
              controller: _barcodeController,
              focusNode: _barcodeFocusNode,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onSubmitted: _onBarcodeSubmitted,
            ),
          ),
        ),
      ],
    );
  }
}
