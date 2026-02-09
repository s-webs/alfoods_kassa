import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
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
  List<Cashier> _cashiers = [];
  List<Shift> _shifts = [];
  int? _selectedCashierId;
  int? _selectedShiftId;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

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
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.apiService.updateSale(
        widget.saleId,
        cashierId: _selectedCashierId,
        shiftId: _selectedShiftId,
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

  Future<void> _delete() async {
    if (_sale == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить продажу?'),
        content: Text(
          'Продажа #${_sale!.id} на сумму ${_sale!.totalPrice.toStringAsFixed(2)} ₽ будет удалена.',
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
                    ...sale.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name),
                                  Text(
                                    '${item.quantity} ${item.unit} × ${item.price.toStringAsFixed(2)} ₽',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${item.total.toStringAsFixed(2)} ₽',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Итого',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${sale.totalPrice.toStringAsFixed(2)} ₽',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                        ),
                      ],
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
                  (c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name),
                  ),
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
