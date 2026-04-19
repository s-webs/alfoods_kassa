import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../models/cart_item.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../models/product_set.dart';
import '../models/shift.dart';
import '../services/api_service.dart';
import '../state/cashier_state.dart';
import '../services/receipt_pdf_service.dart';
import '../services/receipt_printer_service.dart';
import '../utils/barcode_generator.dart';
import '../utils/time_util.dart';
import '../utils/toast.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/credit_sale_dialog.dart';
import '../widgets/invoice_dialog.dart';

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
  bool _isAcceptingReturn = false;
  String? _error;
  final FocusNode _barcodeFocusNode = FocusNode();
  final TextEditingController _barcodeController = TextEditingController();
  bool _isBarcodeLoading = false;
  int? _editingNameIndex;
  int? _editingPriceIndex;
  TextEditingController? _nameEditController;
  TextEditingController? _priceEditController;
  FocusNode? _nameEditFocusNode;
  FocusNode? _priceEditFocusNode;
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
    _nameEditFocusNode?.removeListener(_onNameEditFocusChange);
    _nameEditFocusNode?.dispose();
    _priceEditFocusNode?.removeListener(_onPriceEditFocusChange);
    _priceEditFocusNode?.dispose();
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
      _refocusBarcodeField();
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

  void _addSet(ProductSet productSet) {
    final state = CashierStateScope.of(context);
    const step = 1.0; // сеты всегда pcs
    state.addOrIncrementQuantity(
      0,
      step,
      CartItem(
        productId: 0,
        setId: productSet.id,
        name: productSet.name,
        price: productSet.effectivePrice,
        quantity: step,
        unit: 'pcs',
      ),
      setId: productSet.id,
    );
  }

  void _updateQuantity(int index, double delta) {
    final state = CashierStateScope.of(context);
    final item = state.cart[index];
    final step = _quantityStep(item.unit);
    final newQty = item.quantity + delta * step;
    state.updateQuantityAt(index, newQty);
    _refocusBarcodeField();
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
    if (result != null && mounted) {
      state.updateQuantityAt(index, result);
      _refocusBarcodeField();
    }
  }

  void _removeFromCart(int index) {
    CashierStateScope.of(context).removeAt(index);
    _refocusBarcodeField();
  }

  /// Переключение между параллельными кассами по вкладке.
  ///
  /// Перед переключением закрываем незавершённое in-place редактирование
  /// (чтобы контроллеры не ссылались на индекс из другой корзины), затем
  /// меняем активный регистр в состоянии и возвращаем фокус в поле сканера.
  void _switchRegister(int index) {
    final state = CashierStateScope.of(context);
    if (index == state.activeIndex) return;
    if (_editingNameIndex != null) {
      _finishEditName(save: false);
    }
    if (_editingPriceIndex != null) {
      _finishEditPrice(save: false);
    }
    state.setActiveIndex(index);
    _refocusBarcodeField();
  }

  void _startEditName(int index) {
    final state = CashierStateScope.of(context);
    if (index < 0 || index >= state.cart.length) return;
    _nameEditFocusNode?.removeListener(_onNameEditFocusChange);
    _nameEditFocusNode?.dispose();
    _nameEditFocusNode = FocusNode();
    _nameEditFocusNode!.addListener(_onNameEditFocusChange);
    setState(() {
      _editingNameIndex = index;
      _nameEditController?.dispose();
      _nameEditController = TextEditingController(text: state.cart[index].name);
    });
  }

  void _onNameEditFocusChange() {
    if (_nameEditFocusNode != null && !_nameEditFocusNode!.hasFocus) {
      _nameEditFocusNode!.removeListener(_onNameEditFocusChange);
      _finishEditName();
    }
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
    _nameEditFocusNode?.removeListener(_onNameEditFocusChange);
    _nameEditFocusNode?.dispose();
    _nameEditFocusNode = null;
    _nameEditController?.dispose();
    _nameEditController = null;
    _editingNameIndex = null;
    setState(() {});
    _refocusBarcodeField();
  }

  void _startEditPrice(int index) {
    final state = CashierStateScope.of(context);
    if (index < 0 || index >= state.cart.length) return;
    _priceEditFocusNode?.removeListener(_onPriceEditFocusChange);
    _priceEditFocusNode?.dispose();
    _priceEditFocusNode = FocusNode();
    _priceEditFocusNode!.addListener(_onPriceEditFocusChange);
    setState(() {
      _editingPriceIndex = index;
      _priceEditController?.dispose();
      _priceEditController = TextEditingController(
        text: state.cart[index].price.toStringAsFixed(2),
      );
    });
  }

  void _onPriceEditFocusChange() {
    if (_priceEditFocusNode != null && !_priceEditFocusNode!.hasFocus) {
      _priceEditFocusNode!.removeListener(_onPriceEditFocusChange);
      _finishEditPrice();
    }
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
    _priceEditFocusNode?.removeListener(_onPriceEditFocusChange);
    _priceEditFocusNode?.dispose();
    _priceEditFocusNode = null;
    _priceEditController?.dispose();
    _priceEditController = null;
    _editingPriceIndex = null;
    setState(() {});
    _refocusBarcodeField();
  }

  Future<void> _showAddProductDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AddProductDialog(
        apiService: widget.apiService,
        onAddProduct: (p) => _addProduct(p),
        onAddSet: (s) => _addSet(s),
      ),
    );
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _barcodeFocusNode.canRequestFocus) {
          _barcodeFocusNode.requestFocus();
        }
      });
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
      // Фокус будет восстановлен в _onBarcodeSubmitted, поэтому здесь не нужно
    } else if (mounted) {
      // Если диалог закрыт без результата, восстанавливаем фокус
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _barcodeFocusNode.canRequestFocus) {
          _barcodeFocusNode.requestFocus();
        }
      });
    }
  }

  Future<void> _onBarcodeSubmitted(String value) async {
    final barcode = value.trim();
    if (barcode.isEmpty) return;
    // Большинство сканеров шлет штрихкод как набор цифр. QR-код часто приходит
    // с URL/спецсимволами — не даём таким строкам уходить в resolveBarcode.
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
      final result = await widget.apiService.resolveBarcode(barcode);
      if (!mounted) return;
      if (result != null) {
        if (result.isProduct && result.product != null) {
          _addProduct(result.product!);
          showToast(context, 'Добавлено: ${result.product!.name}');
        } else if (result.isSet && result.productSet != null) {
          _addSet(result.productSet!);
          showToast(context, 'Добавлено: ${result.productSet!.name}');
        } else {
          await _showBarcodeNotFoundDialog(barcode);
        }
      } else {
        await _showBarcodeNotFoundDialog(barcode);
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
      // Фокус будет восстановлен в _showAddProductToDbDialog
    } else if (mounted) {
      // Если диалог закрыт без выбора, восстанавливаем фокус
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _barcodeFocusNode.canRequestFocus) {
          _barcodeFocusNode.requestFocus();
        }
      });
    }
  }

  /// Добавить произвольную позицию в корзину (снимок, product_id: 0).
  Future<void> _showAddSnapshotToCartDialog(String barcode) async {
    final nameController = TextEditingController(text: 'Товар $barcode');
    final priceController = TextEditingController(text: '0');
    String unit = 'pcs';
    final quantityController = TextEditingController(text: '1');

    if (!mounted) return;
    final result =
        await showDialog<
          ({String name, double price, String unit, double quantity})
        >(
          context: context,
          builder: (ctx) {
            return StatefulBuilder(
              builder: (ctx, setDialogState) {
                return AlertDialog(
                  title: const Text(
                    'Добавить в корзину (только на эту продажу)',
                  ),
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
                          onChanged: (v) =>
                              setDialogState(() => unit = v ?? 'pcs'),
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
      showToast(context, 'Позиция добавлена в корзину');
    }
    if (mounted) {
      // Восстанавливаем фокус после закрытия диалога добавления снимка
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _barcodeFocusNode.canRequestFocus) {
          _barcodeFocusNode.requestFocus();
        }
      });
    }
  }

  /// Создать товар в базе и добавить его в корзину.
  Future<void> _showAddProductToDbDialog(String barcode) async {
    // Загружаем категории перед показом диалога
    List<Category> categories = [];
    try {
      categories = await widget.apiService.getCategories();
    } catch (_) {
      // Игнорируем ошибку загрузки категорий
    }

    final nameController = TextEditingController(text: 'Товар $barcode');
    final newNameController = TextEditingController();
    final priceController = TextEditingController(text: '0');
    final purchasePriceController = TextEditingController(text: '0');
    final discountPriceController = TextEditingController();
    final stockController = TextEditingController(text: '0');
    final stockThresholdController = TextEditingController(text: '0');
    final barcodeController = TextEditingController(text: barcode);

    int? selectedCategoryId;
    String selectedUnit = 'pcs';
    bool isActive = true;

    if (!mounted) return;
    final productData =
        await showDialog<
          ({
            String name,
            String? newName,
            double price,
            double purchasePrice,
            double? discountPrice,
            double stock,
            double stockThreshold,
            String unit,
            int? categoryId,
            String? barcode,
            bool isActive,
          })
        >(
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
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Название',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Text('Активен'),
                            const SizedBox(width: 8),
                            Switch(
                              value: isActive,
                              onChanged: (v) =>
                                  setDialogState(() => isActive = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: newNameController,
                          decoration: const InputDecoration(
                            labelText: 'New name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          value: selectedCategoryId,
                          decoration: const InputDecoration(
                            labelText: 'Категория',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Без категории'),
                            ),
                            ...categories.map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setDialogState(() => selectedCategoryId = v),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedUnit,
                          decoration: const InputDecoration(
                            labelText: 'Единица',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'pcs', child: Text('шт')),
                            DropdownMenuItem(value: 'g', child: Text('г')),
                          ],
                          onChanged: (v) =>
                              setDialogState(() => selectedUnit = v ?? 'pcs'),
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
                        TextField(
                          controller: purchasePriceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Закупочная цена, ₸',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: discountPriceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Цена со скидкой, ₸',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: stockController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Остаток',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: stockThresholdController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Порог остатков',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: barcodeController,
                                decoration: const InputDecoration(
                                  labelText: 'Штрихкод',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: OutlinedButton(
                                onPressed: () {
                                  barcodeController.text = generateBarcode();
                                },
                                child: const Text('Сгенерировать'),
                              ),
                            ),
                          ],
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
                        final purchasePrice =
                            double.tryParse(
                              purchasePriceController.text
                                  .replaceFirst(',', '.')
                                  .trim(),
                            ) ??
                            0;
                        final discountPrice =
                            discountPriceController.text.trim().isEmpty
                            ? null
                            : double.tryParse(
                                discountPriceController.text
                                    .replaceFirst(',', '.')
                                    .trim(),
                              );
                        final stock =
                            double.tryParse(
                              stockController.text
                                  .replaceFirst(',', '.')
                                  .trim(),
                            ) ??
                            0;
                        final stockThreshold =
                            double.tryParse(
                              stockThresholdController.text
                                  .replaceFirst(',', '.')
                                  .trim(),
                            ) ??
                            0;
                        final barcodeValue = barcodeController.text.trim();

                        if (name.isNotEmpty && price != null && price >= 0) {
                          Navigator.of(ctx).pop((
                            name: name,
                            newName: newNameController.text.trim().isEmpty
                                ? null
                                : newNameController.text.trim(),
                            price: price,
                            purchasePrice: purchasePrice,
                            discountPrice:
                                discountPrice != null && discountPrice > 0
                                ? discountPrice
                                : null,
                            stock: stock,
                            stockThreshold: stockThreshold,
                            unit: selectedUnit,
                            categoryId: selectedCategoryId,
                            barcode: barcodeValue.isEmpty ? null : barcodeValue,
                            isActive: isActive,
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

    barcodeController.dispose();
    nameController.dispose();
    newNameController.dispose();
    priceController.dispose();
    purchasePriceController.dispose();
    discountPriceController.dispose();
    stockController.dispose();
    stockThresholdController.dispose();

    if (productData == null || !mounted) return;

    final data = <String, dynamic>{
      'name': productData.name,
      'unit': productData.unit,
      'price': productData.price,
      'purchase_price': productData.purchasePrice,
      'stock': productData.stock,
      'stock_threshold': productData.stockThreshold,
      'is_active': productData.isActive,
    };

    if (productData.newName != null && productData.newName!.isNotEmpty) {
      data['new_name'] = productData.newName;
    }
    if (productData.discountPrice != null && productData.discountPrice! > 0) {
      data['discount_price'] = productData.discountPrice;
    }
    if (productData.categoryId != null) {
      data['category_id'] = productData.categoryId;
    }
    if (productData.barcode != null && productData.barcode!.isNotEmpty) {
      data['barcode'] = productData.barcode;
    }

    try {
      final product = await widget.apiService.createProduct(data);
      if (!mounted) return;
      _addProduct(product);
      showToast(context, 'Товар «${product.name}» создан и добавлен в корзину');
    } catch (_) {
      if (mounted) {
        showToast(context, 'Не удалось создать товар');
      }
    }
    if (mounted) {
      // Восстанавливаем фокус после закрытия диалога создания товара
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _barcodeFocusNode.canRequestFocus) {
          _barcodeFocusNode.requestFocus();
        }
      });
    }
  }

  Future<void> _sell() async {
    final state = CashierStateScope.of(context);
    if (state.cart.isEmpty) {
      showToast(context, 'Корзина пуста');
      _refocusBarcodeField();
      return;
    }
    final shift = _currentOpenShift;
    if (shift == null) {
      showToast(context, 'Смена не открыта');
      _refocusBarcodeField();
      return;
    }

    setState(() {
      _isSelling = true;
      _error = null;
    });
    try {
      final saleId = await _ensureSaleSaved();
      if (saleId == null) {
        throw Exception('Не удалось сохранить продажу');
      }
      if (!mounted) return;
      state.clearCart();
      setState(() => _isSelling = false);
      if (mounted) {
        showToast(context, 'Продажа оформлена');
        _refocusBarcodeField();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось оформить продажу';
        _isSelling = false;
      });
      _refocusBarcodeField();
    }
  }

  Future<void> _sellOnCredit() async {
    final state = CashierStateScope.of(context);
    if (state.cart.isEmpty) {
      showToast(context, 'Корзина пуста');
      _refocusBarcodeField();
      return;
    }
    final shift = _currentOpenShift;
    if (shift == null) {
      showToast(context, 'Смена не открыта');
      _refocusBarcodeField();
      return;
    }

    // Show credit sale dialog
    final creditResult = await showDialog<CreditSaleResult>(
      context: context,
      builder: (ctx) => CreditSaleDialog(apiService: widget.apiService),
    );

    if (creditResult == null) return; // User cancelled

    if (!creditResult.isOnCredit || creditResult.counterpartyId == null) {
      showToast(context, 'Для продажи в долг необходимо выбрать покупателя');
      return;
    }

    setState(() {
      _isSelling = true;
      _error = null;
    });
    try {
      final items = state.cart.map((c) => c.toJson()).toList();
      if (state.lastSavedSaleId == null) {
        final sale = await widget.apiService.createSale(
          shiftId: shift.id,
          items: items,
          counterpartyId: creditResult.counterpartyId,
          isOnCredit: true,
        );
        if (!mounted) return;
        state.setLastSavedSaleId(sale.id);
      } else {
        await widget.apiService.updateSale(
          state.lastSavedSaleId!,
          shiftId: shift.id,
          items: items,
          counterpartyId: creditResult.counterpartyId,
          isOnCredit: true,
        );
      }
      if (!mounted) return;
      state.clearCart();
      setState(() => _isSelling = false);
      if (mounted) {
        showToast(context, 'Продажа в долг оформлена');
        _refocusBarcodeField();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось оформить продажу в долг';
        _isSelling = false;
      });
      _refocusBarcodeField();
    }
  }

  Future<void> _resetCart() async {
    final state = CashierStateScope.of(context);
    if (state.cart.isEmpty) return;
    if (state.isReturnMode) {
      state.clearCart();
      if (mounted) {
        showToast(context, 'Корзина очищена');
        _refocusBarcodeField();
      }
      return;
    }
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
        showToast(
          context,
          hadSavedSale
              ? 'Продажа отменена, корзина очищена'
              : 'Корзина очищена',
        );
        _refocusBarcodeField();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isResetting = false);
      showToast(
        context,
        'Ошибка сброса: ${e.toString().replaceFirst('Exception: ', '')}',
      );
      _refocusBarcodeField();
    }
  }

  Future<void> _acceptReturn() async {
    final state = CashierStateScope.of(context);
    if (state.cart.isEmpty) return;
    setState(() {
      _isAcceptingReturn = true;
      _error = null;
    });
    try {
      final items = state.cart.map((c) => c.toJson()).toList();
      final shift = _currentOpenShift;
      await widget.apiService.acceptReturn(
        items: items,
        shiftId: shift?.id,
        cashierId: null,
      );
      if (!mounted) return;
      state.clearCart();
      setState(() => _isAcceptingReturn = false);
      if (mounted) {
        showToast(context, 'Возврат принят');
        _refocusBarcodeField();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAcceptingReturn = false;
        _error = 'Не удалось принять возврат';
      });
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

  /// Восстанавливает фокус на скрытом поле ввода штрихкода.
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

  /// Сохраняет текущую корзину как продажу (если ещё не сохранена) и возвращает id чека.
  Future<int?> _ensureSaleSaved() async {
    final state = CashierStateScope.of(context);
    final shift = _currentOpenShift;
    if (shift == null || state.cart.isEmpty) return null;
    if (state.lastSavedSaleId != null && !state.saleNeedsSync) {
      return state.lastSavedSaleId;
    }
    try {
      final items = state.cart.map((c) => c.toJson()).toList();
      final sale = state.lastSavedSaleId == null
          ? await widget.apiService.createSale(shiftId: shift.id, items: items)
          : await widget.apiService.updateSale(
              state.lastSavedSaleId!,
              shiftId: shift.id,
              items: items,
            );
      if (!mounted) return null;
      state.setLastSavedSaleId(sale.id);
      return sale.id;
    } catch (_) {
      if (mounted) {
        showToast(context, 'Не удалось сохранить продажу');
      }
      return null;
    }
  }

  Future<void> _printReceipt() async {
    final state = CashierStateScope.of(context);
    if (state.cart.isEmpty) {
      _refocusBarcodeField();
      return;
    }
    final printMode = widget.storage.receiptPrintMode;
    if (printMode == 'raw' && !Platform.isWindows) {
      showToast(context, 'RAW печать доступна только на Windows');
      _refocusBarcodeField();
      return;
    }
    try {
      final saleId = await _ensureSaleSaved();
      if (saleId == null && state.lastSavedSaleId == null) {
        if (mounted) {
          showToast(context, 'Не удалось сохранить продажу для чека');
          _refocusBarcodeField();
        }
        return;
      }
      final id = saleId ?? state.lastSavedSaleId!;
      final dateTime = TimeUtil.nowUtcPlus5Wall();
      final totalQty =
          state.cart.fold<double>(0, (sum, item) => sum + item.quantity);
      final bytes = ReceiptPrinterService.buildReceipt(
        saleId: id,
        cashierName: _cashierName,
        items: state.cart,
        total: state.cartTotal,
        totalQty: totalQty,
        dateTime: dateTime,
      );
      await ReceiptPrinterService.printReceipt(
        printerName: widget.storage.receiptPrinterName,
        bytes: bytes,
        printMode: printMode,
        saleId: id,
        cashierName: _cashierName,
        items: state.cart,
        total: state.cartTotal,
        totalQty: totalQty,
        dateTime: dateTime,
      );
      if (!mounted) return;
      showToast(
        context,
        printMode == 'pdf'
            ? 'Открыт диалог печати'
            : printMode == 'pdf_direct'
            ? 'PDF отправлен на печать'
            : 'Чек отправлен на печать',
      );
      _refocusBarcodeField();
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        'Ошибка печати: ${e.toString().replaceFirst('Exception: ', '')}',
      );
      _refocusBarcodeField();
    }
  }

  Future<void> _saveReceiptPdf() async {
    final state = CashierStateScope.of(context);
    if (state.cart.isEmpty) {
      _refocusBarcodeField();
      return;
    }
    try {
      final saleId = await _ensureSaleSaved();
      if (saleId == null && state.lastSavedSaleId == null) {
        if (mounted) {
          showToast(context, 'Не удалось сохранить продажу для чека');
          _refocusBarcodeField();
        }
        return;
      }
      final id = saleId ?? state.lastSavedSaleId!;
      final totalQty =
          state.cart.fold<double>(0, (sum, item) => sum + item.quantity);
      final pdfBytes = await ReceiptPdfService.buildReceiptPdf(
        saleId: id,
        cashierName: _cashierName,
        items: state.cart,
        total: state.cartTotal,
        totalQty: totalQty,
        dateTime: TimeUtil.nowUtcPlus5Wall(),
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
        showToast(context, 'Чек сохранён: $savePath');
      }
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        'Ошибка: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    }
    _refocusBarcodeField();
  }

  String _formatDate(DateTime dt) {
    final t = TimeUtil.toUtcPlus5Wall(dt);
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
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
                _buildRegisterTabs(context),
                _buildShiftBlock(context),
                if (_currentOpenShift != null) _buildTopActions(context),
                if (state.isReturnMode) _buildReturnModeBanner(context),
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
                  keyboardType: TextInputType.number,
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

  /// Вкладки переключения между параллельными кассами.
  ///
  /// На каждой вкладке: номер кассы, бейдж с количеством позиций в её корзине
  /// и маленькая иконка, если в этой кассе сейчас режим возврата. Если у
  /// приложения всего один регистр — блок просто не показывается.
  Widget _buildRegisterTabs(BuildContext context) {
    final state = CashierStateScope.of(context);
    if (state.registerCount <= 1) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.muted.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          for (int i = 0; i < state.registerCount; i++)
            Expanded(child: _buildRegisterTab(state, i)),
        ],
      ),
    );
  }

  Widget _buildRegisterTab(CashierState state, int index) {
    final isActive = index == state.activeIndex;
    final itemCount = state.cartLengthAt(index);
    final inReturn = state.registerIsReturnMode(index);
    final activeColor = inReturn ? AppColors.accent : AppColors.primary;

    return InkWell(
      onTap: () => _switchRegister(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryLight.withValues(alpha: 0.5)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? activeColor : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.point_of_sale,
              size: 18,
              color: isActive ? activeColor : AppColors.muted,
            ),
            const SizedBox(width: 8),
            Text(
              'Касса ${index + 1}',
              style: TextStyle(
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? activeColor : AppColors.surface,
              ),
            ),
            if (itemCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isActive ? activeColor : AppColors.muted)
                      .withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$itemCount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive ? activeColor : AppColors.surface,
                  ),
                ),
              ),
            ],
            if (inReturn) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Режим возврата',
                child: Icon(
                  Icons.keyboard_return,
                  size: 16,
                  color: AppColors.accent,
                ),
              ),
            ],
          ],
        ),
      ),
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
    final state = CashierStateScope.of(context);
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
          if (state.isReturnMode)
            OutlinedButton.icon(
              onPressed: _isAcceptingReturn
                  ? null
                  : () {
                      // clearCart() сам сбрасывает isReturnMode в false.
                      state.clearCart();
                      _refocusBarcodeField();
                    },
              icon: const Icon(Icons.point_of_sale, size: 20),
              label: const Text('Продажа'),
            ),
          if (state.isReturnMode) const SizedBox(width: 12),
          if (!state.isReturnMode)
            OutlinedButton.icon(
              onPressed: _isSelling
                  ? null
                  : () {
                      state.clearCart();
                      state.setReturnMode(true);
                      _refocusBarcodeField();
                    },
              icon: const Icon(Icons.keyboard_return, size: 20),
              label: const Text('Принять возврат'),
            ),
          if (!state.isReturnMode) const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: !_isSelling && !_isAcceptingReturn
                ? _showAddProductDialog
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Добавить вручную'),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: !_isSelling && !_isAcceptingReturn
                ? _showBarcodeTestDialog
                : null,
            icon: const Icon(Icons.qr_code_scanner, size: 20),
            label: const Text('Тест сканера'),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnModeBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.accent.withValues(alpha: 0.15),
      child: Row(
        children: [
          Icon(Icons.keyboard_return, color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          Text(
            'Режим возврата — товары пополнят остатки',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: AppColors.accent,
            ),
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
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${item.orderIndex}',
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
                              // Редактирование названия по клику
                              (_editingNameIndex == index &&
                                      _nameEditController != null)
                                  ? TextField(
                                      controller: _nameEditController,
                                      focusNode: _nameEditFocusNode,
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
                                      onEditingComplete: () =>
                                          _finishEditName(),
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
                                        focusNode: _priceEditFocusNode,
                                        autofocus: true,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(
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
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                        decoration: TextDecoration.underline,
                                        color: AppColors.primary,
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
    final state = CashierStateScope.of(context);
    final cartNotEmpty = state.cart.isNotEmpty;
    final showPrintPdf = cartNotEmpty && !state.isReturnMode;
    final isAcceptReturnEnabled =
        state.isReturnMode && cartNotEmpty && !_isAcceptingReturn;
    final isSellEnabled =
        !state.isReturnMode &&
        _currentOpenShift != null &&
        cartNotEmpty &&
        !_isSelling;

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
          if (cartNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                'Итого: ${state.cartTotal.toStringAsFixed(2)} ₸',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          const Spacer(),
          if (showPrintPdf) ...[
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _saveReceiptPdf,
              icon: const Icon(Icons.picture_as_pdf, size: 20),
              label: const Text('В PDF'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => showInvoiceDialog(
                context: context,
                apiService: widget.apiService,
                items: List.from(state.cart),
                storage: widget.storage,
              ),
              icon: const Icon(Icons.description, size: 20),
              label: const Text('Накладная'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: isSellEnabled ? _sellOnCredit : null,
              icon: const Icon(Icons.credit_card, size: 20),
              label: const Text('Продать в долг'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: !_isResetting && !_isAcceptingReturn
                  ? _resetCart
                  : null,
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
            OutlinedButton.icon(
              onPressed: _printReceipt,
              icon: const Icon(Icons.print, size: 20),
              label: const Text('Печать чека'),
            ),
            const SizedBox(width: 12),
          ],
          if (cartNotEmpty) ...[],
          if (state.isReturnMode)
            FilledButton.icon(
              onPressed: isAcceptReturnEnabled ? _acceptReturn : null,
              icon: _isAcceptingReturn
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.keyboard_return),
              label: Text(_isAcceptingReturn ? 'Приём...' : 'Принять возврат'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            )
          else ...[
            FilledButton.icon(
              onPressed: isSellEnabled ? _sell : null,
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
        ],
      ),
    );
  }
}
