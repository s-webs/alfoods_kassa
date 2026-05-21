import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomerXinDialogResult {
  const CustomerXinDialogResult({
    this.customerXin,
    this.rememberForShift = false,
  });

  final String? customerXin;
  final bool rememberForShift;
}

/// Опциональный ввод ИИН/БИН покупателя перед фискальной оплатой.
class CustomerXinDialog extends StatefulWidget {
  const CustomerXinDialog({
    super.key,
    this.initialValue,
  });

  final String? initialValue;

  static Future<CustomerXinDialogResult?> show(
    BuildContext context, {
    String? initialValue,
  }) {
    return showDialog<CustomerXinDialogResult>(
      context: context,
      builder: (ctx) => CustomerXinDialog(initialValue: initialValue),
    );
  }

  @override
  State<CustomerXinDialog> createState() => _CustomerXinDialogState();
}

class _CustomerXinDialogState extends State<CustomerXinDialog> {
  late final TextEditingController _controller;
  bool _remember = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit({bool skip = false}) {
    if (skip) {
      Navigator.pop(
        context,
        CustomerXinDialogResult(
          rememberForShift: _remember,
        ),
      );
      return;
    }

    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      Navigator.pop(
        context,
        CustomerXinDialogResult(rememberForShift: _remember),
      );
      return;
    }

    if (!RegExp(r'^\d{12}$').hasMatch(raw)) {
      setState(() => _error = 'ИИН/БИН: ровно 12 цифр');
      return;
    }

    Navigator.pop(
      context,
      CustomerXinDialogResult(
        customerXin: raw,
        rememberForShift: _remember,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ИИН/БИН покупателя'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Для фискального чека (если требуется законом). '
              'На ККМ WebKassa должна быть включена печать ИИН/БИН.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'ИИН или БИН (12 цифр)',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(12),
              ],
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Запомнить на эту смену', style: TextStyle(fontSize: 13)),
              value: _remember,
              onChanged: (v) => setState(() => _remember = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => _submit(skip: true),
          child: const Text('Пропустить'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Продолжить'),
        ),
      ],
    );
  }
}
