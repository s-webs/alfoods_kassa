import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/sale.dart';
import '../models/shift.dart';
import '../services/api_service.dart';

class ShiftSalesScreen extends StatefulWidget {
  const ShiftSalesScreen({
    super.key,
    required this.apiService,
    required this.shiftId,
  });

  final ApiService apiService;
  final int shiftId;

  @override
  State<ShiftSalesScreen> createState() => _ShiftSalesScreenState();
}

class _ShiftSalesScreenState extends State<ShiftSalesScreen> {
  List<Sale> _sales = [];
  Shift? _shift;
  bool _isLoading = true;
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
      final sales = await widget.apiService.getSales();
      final shifts = await widget.apiService.getShifts();
      if (!mounted) return;
      final shift = shifts.where((s) => s.id == widget.shiftId).firstOrNull;
      final filtered = sales.where((s) => s.shiftId == widget.shiftId).toList();
      setState(() {
        _sales = filtered;
        _shift = shift;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить продажи';
        _isLoading = false;
      });
    }
  }

  String _formatShiftTitle(Shift s) {
    final opened =
        '${s.openedAt.day.toString().padLeft(2, '0')}.${s.openedAt.month.toString().padLeft(2, '0')}.${s.openedAt.year} '
        '${s.openedAt.hour.toString().padLeft(2, '0')}:${s.openedAt.minute.toString().padLeft(2, '0')}';
    if (s.closedAt != null) {
      final closed =
          '${s.closedAt!.hour.toString().padLeft(2, '0')}:${s.closedAt!.minute.toString().padLeft(2, '0')}';
      return '$opened – $closed';
    }
    return '$opened (открыта)';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: AppColors.muted.withValues(alpha: 0.5)),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  _shift != null
                      ? 'Смена от ${_formatShiftTitle(_shift!)}'
                      : 'Смена #${widget.shiftId}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              size: 48, color: AppColors.danger),
                          const SizedBox(height: 16),
                          Text(_error!),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    )
                  : _sales.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined,
                                  size: 64, color: AppColors.muted),
                              const SizedBox(height: 16),
                              Text(
                                'Нет продаж в этой смене',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _sales.length,
                            itemBuilder: (context, index) {
                              final sale = _sales[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primaryLight,
                                    child: Icon(
                                      Icons.receipt,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  title: Text(
                                    '${sale.totalPrice.toStringAsFixed(2)} ₽',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${sale.totalQty} шт. • #${sale.id}',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () async {
                                    final result = await context.push<bool>(
                                      '/sales/sale/${sale.id}',
                                    );
                                    if (result == true && mounted) _load();
                                  },
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
