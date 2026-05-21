import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/waybill_analysis.dart';
import '../services/api_service.dart';

/// Модалка быстрого создания товара в каталоге.
class QuickCreateProductDialog extends StatefulWidget {
  const QuickCreateProductDialog({
    super.key,
    required this.apiService,
    this.initialName,
    this.initialBarcode,
    this.initialPurchasePrice,
    this.initialSalePrice,
    this.initialUnit,
  });

  final ApiService apiService;
  final String? initialName;
  final String? initialBarcode;
  final double? initialPurchasePrice;
  final double? initialSalePrice;
  final String? initialUnit;

  factory QuickCreateProductDialog.fromAiItem({
    required ApiService apiService,
    required WaybillAnalysisItem aiItem,
  }) {
    return QuickCreateProductDialog(
      apiService: apiService,
      initialName: aiItem.name,
      initialBarcode: aiItem.barcode,
      initialPurchasePrice: aiItem.price,
      initialSalePrice: aiItem.price,
      initialUnit: unitFromLabel(aiItem.unit),
    );
  }

  static String unitFromLabel(String? unitLabel) {
    if (unitLabel == null) return 'pcs';
    final u = unitLabel.toLowerCase();
    if (u.contains('кг') ||
        u.contains('kg') ||
        u.contains('л') ||
        u.startsWith('l')) {
      return 'kg';
    }
    return 'pcs';
  }

  @override
  State<QuickCreateProductDialog> createState() =>
      _QuickCreateProductDialogState();
}

class _QuickCreateProductDialogState extends State<QuickCreateProductDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _purchasePriceCtrl;
  late final TextEditingController _salePriceCtrl;
  late String _unit;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final priceStr = widget.initialPurchasePrice != null
        ? widget.initialPurchasePrice!.toStringAsFixed(2)
        : '';
    final saleStr = widget.initialSalePrice != null
        ? widget.initialSalePrice!.toStringAsFixed(2)
        : priceStr;

    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _barcodeCtrl = TextEditingController(text: widget.initialBarcode ?? '');
    _purchasePriceCtrl = TextEditingController(text: priceStr);
    _salePriceCtrl = TextEditingController(text: saleStr);
    _unit = widget.initialUnit ?? 'pcs';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _salePriceCtrl.dispose();
    super.dispose();
  }

  String _generateEan13() {
    final rnd = Random();
    final digits = List<int>.generate(12, (_) => rnd.nextInt(10));
    final sumOdd = digits
        .asMap()
        .entries
        .where((e) => e.key.isEven)
        .fold<int>(0, (s, e) => s + e.value);
    final sumEven = digits
        .asMap()
        .entries
        .where((e) => e.key.isOdd)
        .fold<int>(0, (s, e) => s + e.value);
    final check = (10 - ((sumOdd + sumEven * 3) % 10)) % 10;
    return '${digits.join()}$check';
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите название товара');
      return;
    }
    final pp = double.tryParse(
          _purchasePriceCtrl.text.replaceAll(',', '.').trim(),
        ) ??
        0.0;
    final sp = double.tryParse(
          _salePriceCtrl.text.replaceAll(',', '.').trim(),
        ) ??
        0.0;
    final barcode = _barcodeCtrl.text.trim();

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final product = await widget.apiService.createProduct({
        'name': name,
        'barcode': barcode.isEmpty ? null : barcode,
        'price': sp,
        'purchase_price': pp,
        'unit': _unit,
        'is_active': true,
      });
      if (mounted) Navigator.of(context).pop(product);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = 'Ошибка создания: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const dialogWidth = 560.0;

    return AlertDialog(
      constraints: const BoxConstraints(minWidth: dialogWidth, maxWidth: 640),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      title: const Text('Создать новый товар'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                  ),
                ),
              ),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _barcodeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Штрихкод',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    setState(() {
                      _barcodeCtrl.text = _generateEan13();
                    });
                  },
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: const Text('Сгенерировать'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _purchasePriceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Закупочная',
                      suffixText: '₸',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _salePriceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Цена продажи',
                      suffixText: '₸',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _unit,
              decoration: const InputDecoration(
                labelText: 'Единица',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'pcs', child: Text('шт')),
                DropdownMenuItem(value: 'kg', child: Text('кг')),
              ],
              onChanged: (v) => setState(() => _unit = v!),
            ),
          ],
        ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(null),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Создать'),
        ),
      ],
    );
  }
}
