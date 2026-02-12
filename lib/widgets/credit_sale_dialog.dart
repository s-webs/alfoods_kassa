import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/counterparty.dart';
import '../services/api_service.dart';

class CreditSaleDialog extends StatefulWidget {
  const CreditSaleDialog({
    super.key,
    required this.apiService,
  });

  final ApiService apiService;

  @override
  State<CreditSaleDialog> createState() => _CreditSaleDialogState();
}

class _CreditSaleDialogState extends State<CreditSaleDialog> {
  List<Counterparty> _counterparties = [];
  bool _loadingCounterparties = true;
  String? _counterpartyError;
  Counterparty? _selectedCounterparty;
  bool _isOnCredit = false;

  @override
  void initState() {
    super.initState();
    _isOnCredit = true; // Always true for credit sale dialog
    _loadCounterparties();
  }

  Future<void> _loadCounterparties() async {
    setState(() {
      _loadingCounterparties = true;
      _counterpartyError = null;
    });
    try {
      final list = await widget.apiService.getCounterparties();
      if (!mounted) return;
      setState(() {
        _counterparties = list;
        _loadingCounterparties = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _counterpartyError = 'Не удалось загрузить контрагентов';
        _loadingCounterparties = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Продажа в долг'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Выберите контрагента для продажи в долг',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            if (_isOnCredit) ...[
              const SizedBox(height: 8),
              if (_loadingCounterparties)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    height: 24,
                    child: LinearProgressIndicator(),
                  ),
                )
              else if (_counterpartyError != null)
                Text(
                  _counterpartyError!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                  ),
                )
              else
                DropdownButtonFormField<Counterparty?>(
                  value: _selectedCounterparty,
                  decoration: const InputDecoration(
                    labelText: 'Контрагент *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('— Выберите контрагента —'),
                    ),
                    ..._counterparties.map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedCounterparty = value);
                  },
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _selectedCounterparty == null
              ? null
              : () => Navigator.of(context).pop(
                    CreditSaleResult(
                      isOnCredit: true,
                      counterpartyId: _selectedCounterparty!.id,
                    ),
                  ),
          child: const Text('Продолжить'),
        ),
      ],
    );
  }
}

class CreditSaleResult {
  final bool isOnCredit;
  final int? counterpartyId;

  CreditSaleResult({
    required this.isOnCredit,
    this.counterpartyId,
  });
}
