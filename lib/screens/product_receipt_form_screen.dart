import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import '../services/api_service.dart';
import '../utils/toast.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/quick_create_product_dialog.dart';
import '../widgets/waybill_analysis_dialog.dart';

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
  List<Supplier> _suppliers = [];
  int? _selectedSupplierId;
  final TextEditingController _supplierNameController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final TextEditingController _barcodeController = TextEditingController();
  List<String> _images = [];
  List<String> _localImagePaths = [];
  int? _editingPriceIndex;
  TextEditingController? _priceEditController;
  bool _isSaving = false;
  bool _isBarcodeLoading = false;
  bool _isUploadingImages = false;
  bool _isAnalyzingWaybill = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refocusBarcodeField();
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

  Future<void> _loadSuppliers() async {
    setState(() {
      _error = null;
    });
    try {
      final suppliers = await widget.apiService.getSuppliers();
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
      });
      _refocusBarcodeField();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить поставщиков';
      });
    }
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
        setState(() {
          _images.add(uploadedPath);
          _localImagePaths.add(path);
        });
      }
    } catch (e) {
      if (mounted) showToast(context, 'Ошибка загрузки: $e');
    } finally {
      if (mounted) setState(() => _isUploadingImages = false);
      if (mounted) _refocusBarcodeField();
    }
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
      if (index < _localImagePaths.length) {
        _localImagePaths.removeAt(index);
      }
    });
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

  /// Analyze the last uploaded invoice image with AI, then show
  /// [WaybillAnalysisDialog] so the user can review and import items.
  Future<void> _analyzeWaybillWithAI() async {
    if (_localImagePaths.isEmpty) {
      showToast(context, 'Сначала загрузите фото накладной');
      return;
    }

    // Use the last uploaded local image
    final path = _localImagePaths.last;

    setState(() => _isAnalyzingWaybill = true);

    try {
      final result = await widget.apiService.analyzeWaybill(path);

      if (!mounted) return;

      if (result.items.isEmpty) {
        showToast(context, 'ИИ не распознал товаров на фото');
        return;
      }

      // 2. Load all products + saved AI→product mappings in parallel
      final futures = await Future.wait([
        widget.apiService.getProducts(),
        widget.apiService.getWaybillMappings(),
      ]);
      final allProducts = futures[0] as List<Product>;
      final mappings = futures[1] as Map<String, int>;

      if (!mounted) return;

      final productById = {for (final p in allProducts) p.id: p};

      final resolved = <ResolvedWaybillItem>[];
      for (final aiItem in result.items) {
        Product? product;

        // 1. Saved mapping (exact ai_name match)
        final aiName = aiItem.name;
        if (aiName != null && mappings.containsKey(aiName)) {
          product = productById[mappings[aiName]];
        }

        // 2. Barcode match (if no mapping found)
        if (product == null) {
          final barcode = aiItem.barcode?.trim();
          if (barcode != null && barcode.isNotEmpty) {
            product = allProducts
                .where((p) => p.barcode == barcode)
                .firstOrNull;
          }
        }

        resolved.add(ResolvedWaybillItem(aiItem: aiItem, product: product));
      }

      if (!mounted) return;

      // 3. Show dialog and wait for user's selection
      final selected = await showDialog<List<ResolvedWaybillItem>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => WaybillAnalysisDialog(
          result: result,
          resolvedItems: resolved,
          allProducts: allProducts,
          apiService: widget.apiService,
        ),
      );

      if (!mounted) return;
      if (selected == null || selected.isEmpty) {
        _refocusBarcodeField();
        return;
      }

      // 4. Apply supplier from AI analysis:
      //    - if supplier exists in DB -> select it in dropdown
      //    - otherwise fill manual supplier name field
      _applySupplierFromAi(result.supplier);

      // 4. Import selected items into the receipt
      int added = 0;
      for (final item in selected) {
        if (item.product == null) continue;
        final product = item.product!;
        final existingIndex = _items.indexWhere(
          (e) => e.productId == product.id,
        );
        final quantity =
            item.importQuantity ?? (product.unit == 'pcs' ? 1.0 : 0.1);
        final price = item.importPrice ?? product.purchasePrice;

        setState(() {
          if (existingIndex >= 0) {
            _items[existingIndex].quantity += quantity;
            _items[existingIndex].price = price;
          } else {
            _items.insert(
              0,
              CartItem(
                productId: product.id,
                name: product.name,
                price: price,
                quantity: quantity,
                unit: product.unit,
              ),
            );
            added++;
          }
        });
      }

      if (mounted) {
        showToast(
          context,
          added > 0
              ? 'Импортировано позиций: $added'
              : 'Позиции обновлены',
        );
      }
    } catch (e) {
      if (mounted) {
        showToast(context, 'Ошибка анализа: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzingWaybill = false);
        _refocusBarcodeField();
      }
    }
  }

  String _normalizeSupplierName(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void _applySupplierFromAi(String? aiSupplierName) {
    final rawName = aiSupplierName?.trim();
    if (rawName == null || rawName.isEmpty) return;

    final normalizedAi = _normalizeSupplierName(rawName);
    if (normalizedAi.isEmpty) return;

    Supplier? matched;

    // 1) Exact normalized match
    for (final supplier in _suppliers) {
      final normalizedSupplier = _normalizeSupplierName(supplier.name);
      if (normalizedSupplier == normalizedAi) {
        matched = supplier;
        break;
      }
    }

    // 2) Partial contains match (both directions)
    if (matched == null) {
      for (final supplier in _suppliers) {
        final normalizedSupplier = _normalizeSupplierName(supplier.name);
        if (normalizedSupplier.contains(normalizedAi) ||
            normalizedAi.contains(normalizedSupplier)) {
          matched = supplier;
          break;
        }
      }
    }

    setState(() {
      if (matched != null) {
        _selectedSupplierId = matched.id;
        _supplierNameController.clear();
      } else {
        _selectedSupplierId = null;
        _supplierNameController.text = rawName;
      }
    });
  }

  String _imageUrl(String path) => widget.apiService.fileUrl(path);

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

  Future<void> _save() async {
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
      final receipt = await widget.apiService.createProductReceipt(
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
      showToast(context, 'Поступление создано');
      context.go('/product-receipts/${receipt.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Не удалось сохранить поступление';
      });
      showToast(context, _error ?? 'Ошибка');
      _refocusBarcodeField();
    }
  }

  double get _itemsTotal => _items.fold(0, (sum, item) => sum + item.total);

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
      final v = double.tryParse(controller.text.replaceFirst(',', '.').trim());
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
                IconButton(icon: const Icon(Icons.save), onPressed: _save),
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
                      value: _selectedSupplierId,
                      decoration: const InputDecoration(
                        labelText: 'Поставщик',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Не выбран'),
                        ),
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
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isUploadingImages
                                ? null
                                : _pickAndUploadImages,
                            icon: _isUploadingImages
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.photo_library_outlined),
                            label: const Text('Фото накладной'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: (_isAnalyzingWaybill ||
                                    _isUploadingImages ||
                                    _localImagePaths.isEmpty)
                                ? null
                                : _analyzeWaybillWithAI,
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF6750A4).withValues(alpha: 0.12),
                              foregroundColor: const Color(0xFF6750A4),
                            ),
                            icon: _isAnalyzingWaybill
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF6750A4),
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('Анализ ИИ'),
                          ),
                        ),
                      ],
                    ),
                    if (_images.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 76,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _images.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                            onTap: () =>
                                                _startEditPrice(index),
                                            child:
                                                (_editingPriceIndex == index &&
                                                    _priceEditController !=
                                                        null)
                                                ? SizedBox(
                                                    width: double.infinity,
                                                    child: TextField(
                                                      controller:
                                                          _priceEditController,
                                                      autofocus: true,
                                                      keyboardType:
                                                          const TextInputType.numberWithOptions(
                                                            decimal: true,
                                                          ),
                                                      decoration:
                                                          const InputDecoration(
                                                            isDense: true,
                                                            border:
                                                                OutlineInputBorder(),
                                                            contentPadding:
                                                                EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      8,
                                                                  vertical: 4,
                                                                ),
                                                          ),
                                                      onSubmitted: (_) =>
                                                          _finishEditPrice(
                                                            save: true,
                                                          ),
                                                      onEditingComplete: () =>
                                                          _finishEditPrice(
                                                            save: true,
                                                          ),
                                                    ),
                                                  )
                                                : Text(
                                                    _unitPriceTimesQuantityLine(
                                                      item,
                                                    ),
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
                                          onPressed: () =>
                                              _updateQuantity(index, -1),
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
                                                decoration:
                                                    TextDecoration.underline,
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
                                          onPressed: () =>
                                              _updateQuantity(index, 1),
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
                        ],
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(
                      color: AppColors.muted.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Итого:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
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
