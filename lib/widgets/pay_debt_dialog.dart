import 'package:flutter/material.dart';

import '../utils/toast.dart';

class PayDebtDialog extends StatefulWidget {
  const PayDebtDialog({
    super.key,
    required this.remainingDebt,
  });

  final double remainingDebt;

  @override
  State<PayDebtDialog> createState() => _PayDebtDialogState();
}

class _PayDebtDialogState extends State<PayDebtDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late TextEditingController _notesController;
  DateTime _paymentDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.remainingDebt.toStringAsFixed(2),
    );
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _paymentDate = picked);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(
      _amountController.text.replaceFirst(',', '.').trim(),
    );

    if (amount == null || amount <= 0) {
      showToast(context, 'Введите корректную сумму');
      return;
    }

    if (amount > widget.remainingDebt) {
      showToast(context, 'Сумма не может превышать остаток долга (${widget.remainingDebt.toStringAsFixed(2)} ₸)');
      return;
    }

    Navigator.of(context).pop(
      PayDebtResult(
        amount: amount,
        paymentDate: _paymentDate,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Оплата долга'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Остаток долга: ${widget.remainingDebt.toStringAsFixed(2)} ₸',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'Сумма оплаты *',
                    border: OutlineInputBorder(),
                    prefixText: '₸ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Введите сумму';
                    }
                    final amount = double.tryParse(
                      v.replaceFirst(',', '.').trim(),
                    );
                    if (amount == null || amount <= 0) {
                      return 'Введите корректную сумму';
                    }
                    if (amount > widget.remainingDebt) {
                      return 'Сумма не может превышать остаток долга';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Дата оплаты *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(
                      '${_paymentDate.day.toString().padLeft(2, '0')}.${_paymentDate.month.toString().padLeft(2, '0')}.${_paymentDate.year}',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Примечания',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Оплатить'),
        ),
      ],
    );
  }
}

class PayDebtResult {
  final double amount;
  final DateTime paymentDate;
  final String? notes;

  PayDebtResult({
    required this.amount,
    required this.paymentDate,
    this.notes,
  });
}
