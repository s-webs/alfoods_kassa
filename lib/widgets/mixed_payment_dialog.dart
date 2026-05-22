import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../models/payment_split_line.dart';
import '../models/sale_payment_method.dart';

class MixedPaymentDialog extends StatefulWidget {
  const MixedPaymentDialog({
    super.key,
    required this.totalAmount,
    required this.kaspiEnabled,
  });

  final double totalAmount;
  final bool kaspiEnabled;

  static Future<List<PaymentSplitLine>?> show(
    BuildContext context, {
    required double totalAmount,
    required bool kaspiEnabled,
  }) {
    return showDialog<List<PaymentSplitLine>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => MixedPaymentDialog(
        totalAmount: totalAmount,
        kaspiEnabled: kaspiEnabled,
      ),
    );
  }

  @override
  State<MixedPaymentDialog> createState() => _MixedPaymentDialogState();
}

class _MixedPaymentDialogState extends State<MixedPaymentDialog> {
  final List<_SplitRowState> _rows = [];

  @override
  void initState() {
    super.initState();
    _rows.add(_SplitRowState(method: SalePaymentMethod.cashOfd));
    _rows.add(_SplitRowState(method: SalePaymentMethod.mobileOfd));
    for (final row in _rows) {
      row.amountController.addListener(_onAmountChanged);
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.amountController.removeListener(_onAmountChanged);
      row.amountController.dispose();
    }
    super.dispose();
  }

  void _onAmountChanged() => setState(() {});

  double get _enteredTotal => _rows.fold(
        0,
        (sum, row) => sum + row.parsedAmount,
      );

  double get _remainder =>
      (widget.totalAmount - _enteredTotal).clamp(0, double.infinity);

  double get _change =>
      (_enteredTotal - widget.totalAmount).clamp(0, double.infinity);

  bool get _canAccept {
    if (_remainder > 0.009) return false;
    if (_rows.length < 2) return false;
    for (final row in _rows) {
      if (row.parsedAmount <= 0) return false;
      if (row.method.requiresKaspiTerminal && !widget.kaspiEnabled) {
        return false;
      }
    }
    return true;
  }

  void _addRow() {
    setState(() {
      final used = _rows.map((r) => r.method).toSet();
      SalePaymentMethod next = SalePaymentMethod.cashOfd;
      for (final m in SalePaymentMethod.ofdCheckoutMethods) {
        if (!used.contains(m) && (!m.requiresKaspiTerminal || widget.kaspiEnabled)) {
          next = m;
          break;
        }
      }
      final row = _SplitRowState(method: next);
      row.amountController.addListener(_onAmountChanged);
      _rows.add(row);
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 2) return;
    setState(() {
      final row = _rows.removeAt(index);
      row.amountController.removeListener(_onAmountChanged);
      row.amountController.dispose();
    });
  }

  void _accept() {
    if (!_canAccept) return;
    final lines = _rows
        .map(
          (r) => PaymentSplitLine(
            method: r.method,
            amount: double.parse(r.parsedAmount.toStringAsFixed(2)),
          ),
        )
        .toList();
    Navigator.pop(context, lines);
  }

  static String _ordinalLabel(int index) {
    const labels = [
      'Первый способ оплаты',
      'Второй способ оплаты',
      'Третий способ оплаты',
      'Четвёртый способ оплаты',
      'Пятый способ оплаты',
    ];
    if (index < labels.length) return labels[index];
    return 'Способ оплаты ${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width.clamp(560.0, 920.0) * 0.85;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'Смешанная оплата',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Подтвердите платеж, нажав на кнопку «Принять оплату»',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                    ),
              ),
              const SizedBox(height: 16),
              _SummaryBar(
                label: 'Итого к оплате',
                value: widget.totalAmount,
                highlighted: true,
              ),
              const SizedBox(height: 8),
              _SummaryBar(
                label: 'Внесено',
                value: _enteredTotal,
                highlighted: true,
              ),
              const SizedBox(height: 8),
              _SummaryBar(
                label: 'Остаток',
                value: _remainder,
                highlighted: _remainder > 0.009,
              ),
              const SizedBox(height: 8),
              _SummaryBar(
                label: 'Сдача',
                value: _change,
                highlighted: false,
              ),
              const SizedBox(height: 20),
              ...List.generate(_rows.length, (index) {
                final row = _rows[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _SplitRowEditor(
                    label: _ordinalLabel(index),
                    row: row,
                    kaspiEnabled: widget.kaspiEnabled,
                    canRemove: _rows.length > 2,
                    onRemove: () => _removeRow(index),
                    onMethodChanged: () => setState(() {}),
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed:
                      _rows.length < SalePaymentMethod.ofdCheckoutMethods.length
                          ? _addRow
                          : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Способ оплаты'),
                ),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _canAccept ? _accept : null,
          icon: const Icon(Icons.check),
          label: const Text('Принять оплату'),
        ),
      ],
    );
  }
}

class _SplitRowState {
  _SplitRowState({required this.method});

  SalePaymentMethod method;
  final TextEditingController amountController = TextEditingController();

  double get parsedAmount {
    final raw = amountController.text.replaceAll(' ', '').replaceAll(',', '.');
    return double.tryParse(raw) ?? 0;
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.label,
    required this.value,
    required this.highlighted,
  });

  final String label;
  final double value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final bg = highlighted ? AppColors.primary : AppColors.muted.withValues(alpha: 0.35);
    final fg = highlighted ? Colors.white : AppColors.surface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '${value.toStringAsFixed(2)} ₸',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _SplitRowEditor extends StatelessWidget {
  const _SplitRowEditor({
    required this.label,
    required this.row,
    required this.kaspiEnabled,
    required this.canRemove,
    required this.onRemove,
    required this.onMethodChanged,
  });

  final String label;
  final _SplitRowState row;
  final bool kaspiEnabled;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onMethodChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (canRemove)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                tooltip: 'Удалить способ',
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<SalePaymentMethod>(
                value: row.method,
                decoration: const InputDecoration(
                  labelText: 'Способ оплаты',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  for (final method in SalePaymentMethod.ofdCheckoutMethods)
                    DropdownMenuItem(
                      value: method,
                      enabled:
                          !method.requiresKaspiTerminal || kaspiEnabled,
                      child: Row(
                        children: [
                          if (method.paymentIconAsset != null)
                            Image.asset(
                              method.paymentIconAsset!,
                              width: 28,
                              height: 28,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                width: 28,
                                height: 28,
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(method.label),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  row.method = value;
                  onMethodChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: row.amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,\s]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Сумма',
                  suffixText: '₸',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
