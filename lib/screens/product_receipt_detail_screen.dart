import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/product_receipt.dart';
import '../models/supplier.dart';
import '../services/api_service.dart';
import '../utils/time_util.dart';
import '../utils/toast.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/quick_create_product_dialog.dart';

class ProductReceiptDetailScreen extends StatefulWidget {
  const ProductReceiptDetailScreen({
    super.key,
    required this.apiService,
    required this.receiptId,
  });

  final ApiService apiService;
  final int receiptId;

  @override
  State<ProductReceiptDetailScreen> createState() =>
      _ProductReceiptDetailScreenState();
}

class _ProductReceiptDetailScreenState
    extends State<ProductReceiptDetailScreen> {
  ProductReceipt? _receipt;
  List<CartItem> _items = [];
  List<Supplier> _suppliers = [];
  int? _selectedSupplierId;
  final TextEditingController _supplierNameController =
      TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final TextEditingController _barcodeController = TextEditingController();
  List<String> _images = [];
  int? _editingPriceIndex;
  TextEditingController? _priceEditController;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isBarcodeLoading = false;
  bool _isUploadingImages = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _priceEditController?.dispose();
    _supplierNameController.dispose();
    _barcodeFocusNode.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  /// Как на кассе: надёжно возвращает фокус на скрытое поле HID-сканера.
  void _refocusBarcodeField() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _barcodeFocusNode.canRequestFocus) {
          _barcodeFocusNode.requestFocus();
        }
      });
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final receipt = await widget.apiService.getProductReceipt(widget.receiptId);
      final suppliers = await widget.apiService.getSuppliers();
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _items = receipt.items
            .map(
              (e) => CartItem(
                productId: e.productId,
                name: e.name,
                price: e.price,
                quantity: e.quantity,
                unit: e.unit,
              ),
            )
            .toList()
            .reversed
            .toList();
        _suppliers = suppliers;
        _selectedSupplierId = receipt.supplierId;
        _supplierNameController.text = receipt.supplierName ?? '';
        _images = List<String>.from(receipt.images);
        _isLoading = false;
      });
      if (mounted) _refocusBarcodeField();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить поступление';
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_receipt == null) return;
    if (_items.isEmpty) {
      showToast(context, 'Добавьте хотя бы одну позицию');
      _refocusBarcodeField();
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.apiService.updateProductReceipt(
        widget.receiptId,
        supplierId: _selectedSupplierId,
        supplierName:
            _selectedSupplierId == null &&
                _supplierNameController.text.isNotEmpty
            ? _supplierNameController.text.trim()
            : null,
        items: _items.map((e) => e.toJson()).toList(),
        images: _images,
      );
      if (!mounted) return;
      showToast(context, 'Поступление обновлено');
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Не удалось сохранить';
      });
      _refocusBarcodeField();
    }
  }

  double get _itemsTotal =>
      _items.fold(0, (sum, item) => sum + item.total);

  void _addProduct(Product product) {
    setState(() {
      final existingIndex = _items.indexWhere(
        (item) => item.productId == product.id,
      );
      if (existingIndex >= 0) {
        final line = _items[existingIndex];
        line.quantity += product.unit == 'pcs' ? 1.0 : 0.1;
        _items.removeAt(existingIndex);
        _items.insert(0, line);
      } else {
        _items.insert(
          0,
          CartItem(
            productId: product.id,
            name: product.name,
            price: product.purchasePrice,
            quantity: 1,
            unit: product.unit,
          ),
        );
      }
    });
  }

  Future<void> _onBarcodeSubmitted(String value) async {
    final barcode = value.trim();
    if (barcode.isEmpty) return;
    final isDigitsOnly = RegExp(r'^\d+$').hasMatch(barcode);
    if (!isDigitsOnly || barcode.length > 32) {
      if (mounted) {
        showToast(context, 'Поддерживаются только штрихкоды (цифры)');
      }
      _refocusBarcodeField();
      return;
    }
    _barcodeController.clear();
    if (_isBarcodeLoading || !mounted) return;
    setState(() => _isBarcodeLoading = true);
    try {
      final result = await widget.apiService.resolveBarcodeForCashier(barcode);
      if (!mounted) return;
      if (result != null) {
        if (result.isProduct && result.product != null) {
          _addProduct(result.product!);
          showToast(context, 'Добавлено: ${result.product!.name}');
        } else if (result.isSet && result.productSet != null) {
          showToast(context, 'Сеты не поддерживаются в поступлениях');
        } else {
          await _offerCreateProductForBarcode(barcode);
        }
      } else {
        await _offerCreateProductForBarcode(barcode);
      }
    } catch (_) {
      if (mounted) {
        showToast(context, 'Ошибка поиска товара');
      }
    } finally {
      if (mounted) setState(() => _isBarcodeLoading = false);
      if (mounted) _refocusBarcodeField();
    }
  }

  Future<void> _pickAndUploadImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty || !mounted) {
      _refocusBarcodeField();
      return;
    }
    setState(() => _isUploadingImages = true);
    try {
      for (final f in result.files) {
        final path = f.path;
        if (path == null || path.isEmpty) continue;
        final uploadedPath = await widget.apiService.uploadReceiptImage(
          path,
          filename: f.name,
        );
        if (!mounted) return;
        setState(() => _images.add(uploadedPath));
      }
    } catch (e) {
      if (mounted) showToast(context, 'Ошибка загрузки: $e');
    } finally {
      if (mounted) setState(() => _isUploadingImages = false);
      if (mounted) _refocusBarcodeField();
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
    _refocusBarcodeField();
  }

  Future<void> _showImagePreview(String path) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Накладная'),
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
          body: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Image.network(
                _imageUrl(path),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Text(
                    'Не удалось загрузить изображение',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) _refocusBarcodeField();
  }

  String _imageUrl(String path) => widget.apiService.fileUrl(path);

  void _updateQuantity(int index, double delta) {
    setState(() {
      final item = _items[index];
      final step = item.unit == 'pcs' ? 1.0 : 0.1;
      item.quantity += delta * step;
      if (item.quantity <= 0) {
        _items.removeAt(index);
      }
    });
    _refocusBarcodeField();
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
    if (!mounted) return;
    if (result != null) {
      setState(() {
        if (result <= 0) {
          _items.removeAt(index);
        } else {
          _items[index].quantity = result;
        }
      });
    }
    _refocusBarcodeField();
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
    _refocusBarcodeField();
  }

  /// Короткая подпись между [−] и [+] (как в макете: «1» для штук).
  String _quantityStepperLabel(CartItem item) {
    if (item.unit == 'pcs') {
      return item.quantity.round().toString();
    }
    return item.quantity.toStringAsFixed(2);
  }

  /// Вторая строка карточки: «1800.00 ₸ × 1.0 pcs».
  String _unitPriceTimesQuantityLine(CartItem item) {
    final qtyPart = item.unit == 'pcs'
        ? '${item.quantity.toStringAsFixed(1)} pcs'
        : '${item.quantity.toStringAsFixed(2)} ${item.unit}';
    return '${item.price.toStringAsFixed(2)} ₸ × $qtyPart';
  }

  Future<void> _showAddProductDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AddProductDialog(
        apiService: widget.apiService,
        activeOnly: false,
        onAddProduct: (p) {
          _addProduct(p);
          _refocusBarcodeField();
        },
        onAddSet: (_) {
          showToast(context, 'Сеты не поддерживаются в поступлениях');
          _refocusBarcodeField();
        },
      ),
    );
    if (mounted) _refocusBarcodeField();
  }

  Future<void> _showCreateProductDialog({
    String? initialBarcode,
    String? initialName,
  }) async {
    final product = await showDialog<Product?>(
      context: context,
      builder: (ctx) => QuickCreateProductDialog(
        apiService: widget.apiService,
        initialBarcode: initialBarcode,
        initialName: initialName,
      ),
    );
    if (product != null && mounted) {
      _addProduct(product);
      showToast(context, 'Товар создан и добавлен в поступление');
    }
    if (mounted) _refocusBarcodeField();
  }

  Future<void> _offerCreateProductForBarcode(String barcode) async {
    final create = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Товар не найден'),
        content: Text(
          'Штрихкод «$barcode» не найден в каталоге. Создать новый товар?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (create == true && mounted) {
      await _showCreateProductDialog(
        initialBarcode: barcode,
        initialName: 'Товар $barcode',
      );
    }
  }

  String _formatDate(DateTime dt) {
    final t = TimeUtil.toUtcPlus5Wall(dt);
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _receipt == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Поступление')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error ?? 'Ошибка', style: TextStyle(color: AppColors.danger)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Scaffold(
      appBar: AppBar(
        title: Text('Поступление #${_receipt!.id}'),
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
                Text(
                  'Дата: ${_formatDate(_receipt!.createdAt)}',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  value: _selectedSupplierId,
                  decoration: const InputDecoration(
                    labelText: 'Поставщик',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Не выбран')),
                    ..._suppliers.map(
                      (supplier) => DropdownMenuItem<int?>(
                        value: supplier.id,
                        child: Text(supplier.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedSupplierId = value;
                      if (value != null) {
                        _supplierNameController.clear();
                      }
                    });
                    _refocusBarcodeField();
                  },
                ),
                if (_selectedSupplierId == null) ...[
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
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _showAddProductDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Добавить товар вручную'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showCreateProductDialog(),
                        icon: const Icon(Icons.add_box_outlined),
                        label: const Text('Создать товар'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Фокус на сканер штрихкода',
                      onPressed: _refocusBarcodeField,
                      icon: const Icon(Icons.keyboard_alt_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed:
                      _isUploadingImages ? null : _pickAndUploadImages,
                  icon: _isUploadingImages
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_library_outlined),
                  label: const Text('Добавить фото накладной'),
                ),
                if (_images.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 76,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _images.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final path = _images[index];
                        return Stack(
                          children: [
                            GestureDetector(
                              onTap: () => _showImagePreview(path),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  _imageUrl(path),
                                  width: 76,
                                  height: 76,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: InkWell(
                                onTap: () => _removeImage(index),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
                ..._items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                GestureDetector(
                                  onTap: () => _startEditPrice(index),
                                  child:
                                      (_editingPriceIndex == index &&
                                          _priceEditController != null)
                                      ? SizedBox(
                                          width: double.infinity,
                                          child: TextField(
                                            controller: _priceEditController,
                                            autofocus: true,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                            ),
                                            onSubmitted: (_) =>
                                                _finishEditPrice(save: true),
                                            onEditingComplete: () =>
                                                _finishEditPrice(save: true),
                                          ),
                                        )
                                      : Text(
                                          _unitPriceTimesQuantityLine(item),
                                          style: TextStyle(
                                            fontSize: 13,
                                            height: 1.25,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 22,
                                  color: Color(0xFF424242),
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 40,
                                  minHeight: 40,
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _updateQuantity(index, -1),
                              ),
                              GestureDetector(
                                onTap: () => _editQuantity(index),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: Text(
                                    _quantityStepperLabel(item),
                                    style: TextStyle(
                                      decoration: TextDecoration.underline,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  size: 22,
                                  color: Color(0xFF424242),
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 40,
                                  minHeight: 40,
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _updateQuantity(index, 1),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${item.total.toStringAsFixed(2)} ₸',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 22,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 40,
                                  minHeight: 40,
                                ),
                                visualDensity: VisualDensity.compact,
                                color: AppColors.danger,
                                onPressed: () {
                                  setState(() {
                                    _items.removeAt(index);
                                  });
                                  _refocusBarcodeField();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (_items.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Нет товаров',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  ),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _showAddProductDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Добавить товар'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showCreateProductDialog(),
                        icon: const Icon(Icons.add_box_outlined),
                        label: const Text('Создать товар'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Фокус на сканер штрихкода',
                      onPressed: _refocusBarcodeField,
                      icon: const Icon(Icons.keyboard_alt_outlined),
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
              keyboardType: TextInputType.number,
              enabled: !_isBarcodeLoading,
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
