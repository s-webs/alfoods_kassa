import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/cart_item.dart';
import '../models/cashier.dart';
import '../models/sale.dart';
import '../models/shift.dart';
import '../services/api_service.dart';

class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({
    super.key,
    required this.apiService,
    required this.saleId,
  });

  final ApiService apiService;
  final int saleId;

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  Sale? _sale;
  List<CartItem> _items = [];
  List<Cashier> _cashiers = [];
  List<Shift> _shifts = [];
  int? _selectedCashierId;
  int? _selectedShiftId;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  int? _editingNameIndex;
  int? _editingPriceIndex;
  TextEditingController? _nameEditController;
  TextEditingController? _priceEditController;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameEditController?.dispose();
    _priceEditController?.dispose();
    super.dispose();
  }

  static double _quantityStep(String unit) =>
      unit == 'pcs' ? 1.0 : 0.1;

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final sale = await widget.apiService.getSale(widget.saleId);
      final cashiers = await widget.apiService.getCashiers();
      final shifts = await widget.apiService.getShifts();
      if (!mounted) return;
      setState(() {
        _sale = sale;
        _items = sale.items
            .map(
              (e) => CartItem(
                productId: e.productId,
                name: e.name,
                price: e.price,
                quantity: e.quantity,
                unit: e.unit,
              ),
            )
            .toList();
        _cashiers = cashiers;
        _shifts = shifts;
        _selectedCashierId = sale.cashierId;
        _selectedShiftId = sale.shiftId;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить продажу';
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_sale == null) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы одну позицию')),
      );
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.apiService.updateSale(
        widget.saleId,
        cashierId: _selectedCashierId,
        shiftId: _selectedShiftId,
        items: _items.map((e) => e.toJson()).toList(),
      );
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Не удалось сохранить';
      });
    }
  }

  double get _itemsTotal =>
      _items.fold(0, (sum, item) => sum + item.total);

  void _updateQuantity(int index, double delta) {
    setState(() {
      final item = _items[index];
      final step = _quantityStep(item.unit);
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
      return v;
    }
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
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
      ),
    );
    if (result != null && result > 0 && mounted) {
      setState(() => _items[index].quantity = result);
    }
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _startEditName(int index) {
    if (index < 0 || index >= _items.length) return;
    setState(() {
      _editingNameIndex = index;
      _nameEditController?.dispose();
      _nameEditController = TextEditingController(text: _items[index].name);
    });
  }

  void _finishEditName({bool save = true}) {
    final index = _editingNameIndex;
    if (index == null || index < 0 || index >= _items.length) return;
    final controller = _nameEditController;
    if (controller != null && save) {
      final text = controller.text.trim();
      if (text.isNotEmpty) {
        setState(() => _items[index].name = text);
      }
    }
    _nameEditController?.dispose();
    _nameEditController = null;
    setState(() => _editingNameIndex = null);
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
        setState(() => _items[index].price = value);
      }
    }
    _priceEditController?.dispose();
    _priceEditController = null;
    setState(() => _editingPriceIndex = null);
  }

  Future<void> _addItem() async {
    final nameController = TextEditingController(text: '');
    final priceController = TextEditingController(text: '0');
    String unit = 'pcs';
    final quantityController = TextEditingController(text: '1');
    final result = await showDialog<({String name, double price, String unit, double quantity})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Добавить позицию'),
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
      setState(() {
        _items.add(
          CartItem(
            productId: 0,
            name: result.name,
            price: result.price,
            quantity: result.quantity,
            unit: result.unit,
          ),
        );
      });
    }
  }

  Future<void> _delete() async {
    if (_sale == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить продажу?'),
        content: Text(
          'Продажа #${_sale!.id} на сумму ${_itemsTotal.toStringAsFixed(2)} ₸ будет удалена.',
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
      await widget.apiService.deleteSale(widget.saleId);
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось удалить');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Продажа'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _sale == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Продажа'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.danger),
              const SizedBox(height: 16),
              Text(_error!),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Назад'),
              ),
            ],
          ),
        ),
      );
    }

    final sale = _sale!;
    return Scaffold(
      appBar: AppBar(
        title: Text('Продажа #${sale.id}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
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
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${sale.createdAt.day.toString().padLeft(2, '0')}.${sale.createdAt.month.toString().padLeft(2, '0')}.${sale.createdAt.year} '
                      '${sale.createdAt.hour.toString().padLeft(2, '0')}:${sale.createdAt.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const Divider(),
                    ...List.generate(_items.length, (index) {
                      final item = _items[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _editingNameIndex == index &&
                                          _nameEditController != null
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
                                        )
                                      : GestureDetector(
                                          onDoubleTap: () =>
                                              _startEditName(index),
                                          child: Text(
                                            item.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                  const SizedBox(height: 4),
                                  _editingPriceIndex == index &&
                                          _priceEditController != null
                                      ? SizedBox(
                                          width: 140,
                                          child: TextField(
                                            controller: _priceEditController,
                                            autofocus: true,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
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
                                            onSubmitted: (_) =>
                                                _finishEditPrice(),
                                          ),
                                        )
                                      : GestureDetector(
                                          onDoubleTap: () =>
                                              _startEditPrice(index),
                                          child: Text(
                                            '${item.price.toStringAsFixed(2)} ₸ × ${item.quantity} ${item.unit}',
                                            style: TextStyle(
                                              fontSize: 12,
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
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        item.quantity.toStringAsFixed(
                                          item.unit == 'pcs' ? 0 : 2,
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () =>
                                      _updateQuantity(index, 1),
                                  iconSize: 22,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${item.total.toStringAsFixed(2)} ₸',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: AppColors.danger,
                                    size: 22,
                                  ),
                                  onPressed: () => _removeItem(index),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Итого',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${_itemsTotal.toStringAsFixed(2)} ₸',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isSaving ? null : _addItem,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Добавить позицию'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Редактирование',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _selectedCashierId,
              decoration: const InputDecoration(labelText: 'Кассир'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Не выбран')),
                ..._cashiers.map(
                  (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                ),
              ],
              onChanged: (v) => setState(() => _selectedCashierId = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              initialValue: _selectedShiftId,
              decoration: const InputDecoration(labelText: 'Смена'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Не выбрана')),
                ..._shifts.map(
                  (s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      '${s.openedAt.day.toString().padLeft(2, '0')}.${s.openedAt.month.toString().padLeft(2, '0')} '
                      '${s.openedAt.hour.toString().padLeft(2, '0')}:${s.openedAt.minute.toString().padLeft(2, '0')}'
                      '${s.closedAt != null ? ' (закрыта)' : ' (открыта)'}',
                    ),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _selectedShiftId = v),
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
    );
  }
}
