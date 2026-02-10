import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/shift.dart';
import '../services/api_service.dart';
import '../state/cashier_state.dart';
import '../services/receipt_pdf_service.dart';
import '../services/receipt_printer_service.dart';
import '../utils/slugify.dart';
import '../widgets/add_product_dialog.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({
    super.key,
    required this.storage,
    required this.apiService,
  });

  final Storage storage;
  final ApiService apiService;

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  List<Shift> _shifts = [];
  bool _isLoading = true;
  bool _isOpeningShift = false;
  bool _isClosingShift = false;
  bool _isSelling = false;
  String? _error;
  final FocusNode _barcodeFocusNode = FocusNode();
  final TextEditingController _barcodeController = TextEditingController();
  bool _isBarcodeLoading = false;
  int? _editingNameIndex;
  int? _editingPriceIndex;
  TextEditingController? _nameEditController;
  TextEditingController? _priceEditController;
  bool _isResetting = false;

  @override
  void initState() {
    super.initState();
    _loadShifts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _barcodeFocusNode.dispose();
    _barcodeController.dispose();
    _nameEditController?.dispose();
    _priceEditController?.dispose();
    super.dispose();
  }

  Future<void> _loadShifts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final shifts = await widget.apiService.getShifts();
      if (!mounted) return;
      setState(() {
        _shifts = shifts;
        _isLoading = false;
        // Сбрасываем флаги открытия/закрытия смены после успешной загрузки,
        // чтобы не оставались "залипшие" спиннеры от предыдущих операций.
        _isOpeningShift = false;
        _isClosingShift = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить смены';
        _isLoading = false;
      });
    }
  }

  Future<void> _openShift() async {
    setState(() {
      _isOpeningShift = true;
      _error = null;
    });
    try {
      await widget.apiService.createShift();
      await _loadShifts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось открыть смену';
        _isOpeningShift = false;
      });
    }
  }

  Future<void> _closeShift() async {
    final shift = _currentOpenShift;
    if (shift == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Закрыть смену?'),
        content: const Text('Вы уверены, что хотите закрыть текущую смену?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isClosingShift = true;
      _error = null;
    });
    try {
      await widget.apiService.closeShift(shift.id);
      await _loadShifts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось закрыть смену';
        _isClosingShift = false;
      });
    }
  }

  static double _quantityStep(String unit) =>
      unit == 'pcs' ? 1.0 : 0.1; // штучные +1, граммовые +100 г (0.1 кг)

  void _addProduct(Product product) {
    final state = CashierStateScope.of(context);
    final step = _quantityStep(product.unit);
    state.addOrIncrementQuantity(
      product.id,
      step,
      CartItem(
        productId: product.id,
        name: product.name,
        price: product.effectivePrice,
        quantity: step,
        unit: product.unit,
      ),
    );
  }

  void _updateQuantity(int index, double delta) {
    final state = CashierStateScope.of(context);
    final item = state.cart[index];
    final step = _quantityStep(item.unit);
    final newQty = item.quantity + delta * step;
    state.updateQuantityAt(index, newQty);
  }

  Future<void> _editQuantity(int index) async {
    final state = CashierStateScope.of(context);
    final item = state.cart[index];
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
      state.updateQuantityAt(index, result);
    }
  }

  void _removeFromCart(int index) {
    CashierStateScope.of(context).removeAt(index);
  }

  void _startEditName(int index) {
    final state = CashierStateScope.of(context);
    if (index < 0 || index >= state.cart.length) return;
    setState(() {
      _editingNameIndex = index;
    _nameEditController?.dispose();
    _nameEditController = TextEditingController(text: state.cart[index].name);
    });
  }

  void _finishEditName({bool save = true}) {
    final index = _editingNameIndex;
    final state = CashierStateScope.of(context);
    if (index == null || index < 0 || index >= state.cart.length) return;
    final controller = _nameEditController;
    if (controller != null && save) {
      final text = controller.text.trim();
      if (text.isNotEmpty) {
        CashierStateScope.of(context).updateNameAt(index, text);
      }
    }
    _nameEditController?.dispose();
    _nameEditController = null;
    _editingNameIndex = null;
  }

  void _startEditPrice(int index) {
    final state = CashierStateScope.of(context);
    if (index < 0 || index >= state.cart.length) return;
    setState(() {
      _editingPriceIndex = index;
      _priceEditController?.dispose();
      _priceEditController = TextEditingController(
        text: state.cart[index].price.toStringAsFixed(2),
      );
    });
  }

  void _finishEditPrice({bool save = true}) {
    final index = _editingPriceIndex;
    final state = CashierStateScope.of(context);
    if (index == null || index < 0 || index >= state.cart.length) return;
    final controller = _priceEditController;
    if (controller != null && save) {
      final text = controller.text.replaceFirst(',', '.').trim();
      final value = double.tryParse(text);
      if (value != null && value >= 0) {
        CashierStateScope.of(context).updatePriceAt(index, value);
      }
    }
    _priceEditController?.dispose();
    _priceEditController = null;
    _editingPriceIndex = null;
  }

  Future<void> _showAddProductDialog() async {
    final product = await showDialog<Product>(
      context: context,
      builder: (ctx) => AddProductDialog(apiService: widget.apiService),
    );
    if (product != null && mounted) {
      _addProduct(product);
    }
    if (mounted) {
      _barcodeFocusNode.requestFocus();
    }
  }

  /// Эмуляция сканера: ввод штрихкода вручную для проверки без реального сканера.
  Future<void> _showBarcodeTestDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Тест сканера штрихкода'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Штрихкод',
              hintText: 'Введите штрихкод товара',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.of(ctx).pop(controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );
    if (result != null && result.isNotEmpty && mounted) {
      _onBarcodeSubmitted(result);
    }
    if (mounted) {
      _barcodeFocusNode.requestFocus();
    }
  }

  Future<void> _onBarcodeSubmitted(String value) async {
    final barcode = value.trim();
    if (barcode.isEmpty) return;
    _barcodeController.clear();
    if (_isBarcodeLoading || !mounted) return;
    setState(() => _isBarcodeLoading = true);
    try {
      final product = await widget.apiService.getProductByBarcode(barcode);
      if (!mounted) return;
      if (product != null) {
        _addProduct(product);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Добавлено: ${product.name}')),
        );
      } else {
        await _showBarcodeNotFoundDialog(barcode);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка поиска товара')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBarcodeLoading = false);
    }
  }

  /// Модалка при ненайденном штрихкоде: добавить в корзину снимком или в базу Product.
  Future<void> _showBarcodeNotFoundDialog(String barcode) async {
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Товар не найден'),
          content: Text(
            'Штрихкод «$barcode» не найден в каталоге. Что сделать?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('cart'),
              child: const Text('Добавить в корзину (только на эту продажу)'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('product'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              child: const Text('Добавить товар в базу'),
            ),
          ],
        );
      },
    );
    if (choice == 'cart' && mounted) {
      await _showAddSnapshotToCartDialog(barcode);
    } else if (choice == 'product' && mounted) {
      await _showAddProductToDbDialog(barcode);
    }
    if (mounted) _barcodeFocusNode.requestFocus();
  }

  /// Добавить произвольную позицию в корзину (снимок, product_id: 0).
  Future<void> _showAddSnapshotToCartDialog(String barcode) async {
    final nameController = TextEditingController(text: 'Товар $barcode');
    final priceController = TextEditingController(text: '0');
    String unit = 'pcs';
    final quantityController = TextEditingController(text: '1');

    if (!mounted) return;
    final result = await showDialog<({String name, double price, String unit, double quantity})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Добавить в корзину (только на эту продажу)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Название',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Цена, ₸',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(
                        labelText: 'Единица',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'pcs', child: Text('шт')),
                        DropdownMenuItem(value: 'g', child: Text('г')),
                      ],
                      onChanged: (v) => setDialogState(() => unit = v ?? 'pcs'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantityController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Количество',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final price = double.tryParse(
                      priceController.text.replaceFirst(',', '.').trim(),
                    );
                    final qty = double.tryParse(
                      quantityController.text.replaceFirst(',', '.').trim(),
                    );
                    if (name.isNotEmpty &&
                        price != null &&
                        price >= 0 &&
                        qty != null &&
                        qty > 0) {
                      Navigator.of(ctx).pop((
                        name: name,
                        price: price,
                        unit: unit,
                        quantity: qty,
                      ));
                    }
                  },
                  child: const Text('Добавить'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      CashierStateScope.of(context).addItem(
        CartItem(
          productId: 0,
          name: result.name,
          price: result.price,
          quantity: result.quantity,
          unit: result.unit,
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Позиция добавлена в корзину')),
      );
    }
  }

  /// Создать товар в базе и добавить его в корзину.
  Future<void> _showAddProductToDbDialog(String barcode) async {
    final nameController = TextEditingController(text: 'Товар $barcode');
    final priceController = TextEditingController(text: '0');
    String unit = 'pcs';

    if (!mounted) return;
    final productData = await showDialog<({String name, double price, String unit})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Добавить товар в базу'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Название',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Цена, ₸',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(
                        labelText: 'Единица',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'pcs', child: Text('шт')),
                        DropdownMenuItem(value: 'g', child: Text('г')),
                      ],
                      onChanged: (v) => setDialogState(() => unit = v ?? 'pcs'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Штрихкод: $barcode',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final price = double.tryParse(
                      priceController.text.replaceFirst(',', '.').trim(),
                    );
                    if (name.isNotEmpty && price != null && price >= 0) {
                      Navigator.of(ctx).pop((
                        name: name,
                        price: price,
                        unit: unit,
                      ));
                    }
                  },
                  child: const Text('Создать и добавить в корзину'),
                ),
              ],
            );
          },
        );
      },
    );

    if (productData == null || !mounted) return;

    final baseSlug = slugify(productData.name).isEmpty
        ? 'product-${barcode.replaceAll(RegExp(r'[^a-z0-9]'), '-')}'
        : '${slugify(productData.name)}-$barcode';
    final slug = '$baseSlug-${DateTime.now().millisecondsSinceEpoch}';
    final data = <String, dynamic>{
      'name': productData.name,
      'slug': slug,
      'unit': productData.unit,
      'price': productData.price,
      'barcode': barcode,
      'stock': 0,
      'is_active': true,
    };

    try {
      final product = await widget.apiService.createProduct(data);
      if (!mounted) return;
      _addProduct(product);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Товар «${product.name}» создан и добавлен в корзину')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось создать товар (проверьте slug или сеть)')),
        );
      }
    }
    if (mounted) _barcodeFocusNode.requestFocus();
  }

  Future<void> _sell() async {
    final state = CashierStateScope.of(context);
    if (state.cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Корзина пуста')),
      );
      return;
    }
    final shift = _currentOpenShift;
    if (shift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Смена не открыта')),
      );
      return;
    }

    setState(() {
      _isSelling = true;
      _error = null;
    });
    try {
      if (state.lastSavedSaleId == null) {
        final items = state.cart.map((c) => c.toJson()).toList();
        await widget.apiService.createSale(shiftId: shift.id, items: items);
      }
      if (!mounted) return;
      state.clearCart();
      setState(() => _isSelling = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Продажа оформлена')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось оформить продажу';
        _isSelling = false;
      });
    }
  }

  Future<void> _resetCart() async {
    final state = CashierStateScope.of(context);
    if (state.cart.isEmpty) return;
    final hadSavedSale = state.lastSavedSaleId != null;
    setState(() => _isResetting = true);
    try {
      if (state.lastSavedSaleId != null) {
        await widget.apiService.deleteSale(state.lastSavedSaleId!);
      }
      if (!mounted) return;
      state.clearCart();
      setState(() => _isResetting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hadSavedSale ? 'Продажа отменена, корзина очищена' : 'Корзина очищена',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isResetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка сброса: ${e.toString().replaceFirst('Exception: ', '')}'),
        ),
      );
    }
  }

  Shift? get _currentOpenShift {
    for (final s in _shifts) {
      if (s.isOpen) return s;
    }
    return null;
  }

  String get _cashierName {
    final name = widget.storage.user?['name']?.toString();
    return name != null && name.isNotEmpty ? name : 'Кассир';
  }

  /// Сохраняет текущую корзину как продажу (если ещё не сохранена) и возвращает id чека.
  Future<int?> _ensureSaleSaved() async {
    final state = CashierStateScope.of(context);
    final shift = _currentOpenShift;
    if (shift == null || state.cart.isEmpty) return null;
    if (state.lastSavedSaleId != null) return state.lastSavedSaleId;
    try {
      final items = state.cart.map((c) => c.toJson()).toList();
      final sale = await widget.apiService.createSale(shiftId: shift.id, items: items);
      if (!mounted) return null;
      state.setLastSavedSaleId(sale.id);
      return sale.id;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить продажу')),
        );
      }
      return null;
    }
  }

  Future<void> _printReceipt() async {
    final state = CashierStateScope.of(context);
    if (state.cart.isEmpty) return;
    if (!Platform.isWindows) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Печать чеков доступна только на Windows')),
      );
      return;
    }
    try {
      final saleId = await _ensureSaleSaved();
      if (saleId == null && state.lastSavedSaleId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось сохранить продажу для чека')),
          );
        }
        return;
      }
      final id = saleId ?? state.lastSavedSaleId!;
      final bytes = ReceiptPrinterService.buildReceipt(
        saleId: id,
        cashierName: _cashierName,
        items: state.cart,
        total: state.cartTotal,
        dateTime: DateTime.now(),
      );
      await ReceiptPrinterService.printReceipt(
        printerName: widget.storage.receiptPrinterName,
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Чек отправлен на печать')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ошибка печати: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Future<void> _saveReceiptPdf() async {
    final state = CashierStateScope.of(context);
    if (state.cart.isEmpty) return;
    try {
      final saleId = await _ensureSaleSaved();
      if (saleId == null && state.lastSavedSaleId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось сохранить продажу для чека')),
          );
        }
        return;
      }
      final id = saleId ?? state.lastSavedSaleId!;
      final pdfBytes = await ReceiptPdfService.buildReceiptPdf(
        saleId: id,
        cashierName: _cashierName,
        items: state.cart,
        total: state.cartTotal,
        dateTime: DateTime.now(),
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить чек в PDF',
        fileName: 'chek-$id.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (!mounted) return;
      if (path != null && path.isNotEmpty) {
        final savePath = path.endsWith('.pdf') ? path : '$path.pdf';
        await File(savePath).writeAsBytes(pdfBytes);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Чек сохранён: $savePath')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ошибка: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = CashierStateScope.of(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildShiftBlock(context),
                if (_currentOpenShift != null) _buildTopActions(context),
                if (_error != null) _buildErrorBlock(context),
                Expanded(child: _buildCartBlock(context)),
                _buildActionBlock(context),
              ],
            ),
            // Невидимое поле для приёма ввода со сканера штрихкодов (эмуляция клавиатуры)
            Positioned(
          left: 0,
          top: 0,
          child: SizedBox(
            width: 1,
            height: 1,
            child: TextField(
                controller: _barcodeController,
                focusNode: _barcodeFocusNode,
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
      },
    );
  }

  Widget _buildShiftBlock(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.muted.withValues(alpha: 0.5)),
        ),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentOpenShift == null
          ? Row(
              children: [
                Icon(Icons.schedule, color: AppColors.muted, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Смена не открыта',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _isOpeningShift ? null : _openShift,
                  icon: _isOpeningShift
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow, size: 20),
                  label: Text(
                    _isOpeningShift ? 'Открытие...' : 'Открыть смену',
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.accent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Смена открыта',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'С ${_formatDate(_currentOpenShift!.openedAt)}',
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isClosingShift ? null : _closeShift,
                  icon: _isClosingShift
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.stop_circle, size: 20),
                  label: Text(
                    _isClosingShift ? 'Закрытие...' : 'Закрыть смену',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTopActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.muted.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton.icon(
            onPressed: !_isSelling ? _showAddProductDialog : null,
            icon: const Icon(Icons.add),
            label: const Text('Добавить вручную'),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: !_isSelling ? _showBarcodeTestDialog : null,
            icon: const Icon(Icons.qr_code_scanner, size: 20),
            label: const Text('Тест сканера'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBlock(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.danger.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error!, style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Widget _buildCartBlock(BuildContext context) {
    final state = CashierStateScope.of(context);
    return Container(
      color: AppColors.primaryLight.withValues(alpha: 0.3),
      child: state.cart.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 64,
                    color: AppColors.muted,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Корзина пуста',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.cart.length,
              itemBuilder: (context, index) {
                final item = state.cart[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Редактирование названия по клику
                              (_editingNameIndex == index &&
                                      _nameEditController != null)
                                  ? TextField(
                                      controller: _nameEditController,
                                      autofocus: true,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                      ),
                                      onSubmitted: (_) => _finishEditName(),
                                      onEditingComplete: () => _finishEditName(),
                                    )
                                  : GestureDetector(
                                      onTap: () => _startEditName(index),
                                      child: Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                              const SizedBox(height: 4),
                              // Редактирование цены по клику
                              (_editingPriceIndex == index &&
                                      _priceEditController != null)
                                  ? SizedBox(
                                      width: 140,
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
                                            vertical: 6,
                                          ),
                                        ),
                                        onSubmitted: (_) => _finishEditPrice(),
                                        onEditingComplete: () =>
                                            _finishEditPrice(),
                                      ),
                                    )
                                  : GestureDetector(
                                      onTap: () => _startEditPrice(index),
                                      child: Text(
                                        '${item.price.toStringAsFixed(2)} ₸ × ${item.quantity} ${item.unit}',
                                        style: TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 13,
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
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _updateQuantity(index, -1),
                              iconSize: 22,
                            ),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _editQuantity(index),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minWidth: 44,
                                    ),
                                    child: Text(
                                      item.quantity.toStringAsFixed(
                                        item.unit == 'pcs' ? 0 : 2,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => _updateQuantity(index, 1),
                              iconSize: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${item.total.toStringAsFixed(2)} ₸',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: AppColors.danger,
                                size: 22,
                              ),
                              onPressed: () => _removeFromCart(index),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildActionBlock(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (CashierStateScope.of(context).cart.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                'Итого: ${CashierStateScope.of(context).cartTotal.toStringAsFixed(2)} ₸',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          const Spacer(),
          if (CashierStateScope.of(context).cart.isNotEmpty) ...[
            OutlinedButton.icon(
              onPressed: _printReceipt,
              icon: const Icon(Icons.print, size: 20),
              label: const Text('Печать чека'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _saveReceiptPdf,
              icon: const Icon(Icons.picture_as_pdf, size: 20),
              label: const Text('В PDF'),
            ),
            const SizedBox(width: 12),
          ],
          if (CashierStateScope.of(context).cart.isNotEmpty) ...[
            OutlinedButton.icon(
              onPressed: !_isResetting ? _resetCart : null,
              icon: _isResetting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.clear_all, size: 20),
              label: Text(_isResetting ? 'Сброс...' : 'Сброс'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
            ),
            const SizedBox(width: 12),
          ],
          FilledButton.icon(
            onPressed:
                _currentOpenShift != null &&
                    CashierStateScope.of(context).cart.isNotEmpty &&
                    !_isSelling
                ? _sell
                : null,
            icon: _isSelling
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.point_of_sale),
            label: Text(_isSelling ? 'Оформление...' : 'Продать'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          ),
        ],
      ),
    );
  }
}
