import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../utils/toast.dart';
import '../services/debtors_pdf_service.dart';
import '../widgets/pay_debt_bulk_dialog.dart';

class DebtorsScreen extends StatefulWidget {
  const DebtorsScreen({
    super.key,
    required this.storage,
    required this.apiService,
  });

  final Storage storage;
  final ApiService apiService;

  @override
  State<DebtorsScreen> createState() => _DebtorsScreenState();
}

class _DebtorsScreenState extends State<DebtorsScreen> {
  List<Map<String, dynamic>> _debtors = [];
  bool _isLoading = true;
  String? _error;
  bool _isGeneratingPdf = false;
  int? _payingDebtCounterpartyId;

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
      final debtors = await widget.apiService.getDebtors();
      if (!mounted) return;
      setState(() {
        _debtors = debtors;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить список должников';
        _isLoading = false;
      });
    }
  }

  Future<void> _generatePdf() async {
    if (_debtors.isEmpty) {
      showToast(context, 'Нет должников для формирования отчета');
      return;
    }

    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      final pdfBytes = await DebtorsPdfService.buildDebtorsPdf(_debtors);
      if (!mounted) return;

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить список должников',
        fileName: 'Список_должников_${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (!mounted) return;
      if (path != null && path.isNotEmpty) {
        final savePath = path.endsWith('.pdf') ? path : '$path.pdf';
        await File(savePath).writeAsBytes(pdfBytes);
        if (mounted) {
          showToast(context, 'PDF сохранен: $savePath');
        }
      }
    } catch (e) {
      if (!mounted) return;
      showToast(context, 'Ошибка генерации PDF: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Должники'),
        actions: [
          if (_debtors.isNotEmpty)
            IconButton(
              icon: _isGeneratingPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf),
              onPressed: _isGeneratingPdf ? null : _generatePdf,
              tooltip: 'Сформировать PDF',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: AppColors.danger,
                      ),
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
              : _debtors.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 64,
                            color: AppColors.muted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Нет должников',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _debtors.length,
                        itemBuilder: (context, index) {
                          final debtor = _debtors[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.danger.withValues(alpha: 0.2),
                                child: Icon(
                                  Icons.person,
                                  color: AppColors.danger,
                                ),
                              ),
                              title: Text(
                                debtor['name'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    'Долг: ${(debtor['total_debt'] as num).toStringAsFixed(2)} ₸',
                                    style: TextStyle(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Неоплаченных продаж: ${debtor['unpaid_sales_count'] as int}',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (debtor['iin'] != null)
                                        Text(
                                          'ИИН/БИН: ${debtor['iin']}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      if (debtor['address'] != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Адрес: ${debtor['address']}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                      if (debtor['phone'] != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Телефон: ${debtor['phone']}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                      if (debtor['last_sale_date'] != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Последняя продажа: ${debtor['last_sale_date']}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 16),
                                      FilledButton.icon(
                                        onPressed: (debtor['unpaid_sales'] as List).isEmpty
                                            ? null
                                            : () async {
                                                final totalDebt = debtor['total_debt'] as num;
                                                final result = await showDialog<PayDebtBulkResult>(
                                                  context: context,
                                                  builder: (ctx) => PayDebtBulkDialog(
                                                    totalDebt: totalDebt.toDouble(),
                                                    counterpartyName: debtor['name'] as String,
                                                  ),
                                                );
                                                if (result == null || !mounted) return;
                                                setState(() => _payingDebtCounterpartyId = debtor['id'] as int);
                                                try {
                                                  await widget.apiService.payDebtBulk(
                                                    debtor['id'] as int,
                                                    amount: result.amount,
                                                    paymentDate: result.paymentDate,
                                                    notes: result.notes,
                                                  );
                                                  if (!mounted) return;
                                                  showToast(context, 'Оплачено ${result.amount.toStringAsFixed(2)} ₸. Долги обновлены.');
                                                  _load();
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  showToast(context, 'Ошибка: $e');
                                                } finally {
                                                  if (mounted) setState(() => _payingDebtCounterpartyId = null);
                                                }
                                              },
                                        icon: _payingDebtCounterpartyId == debtor['id']
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(Icons.payment, size: 20),
                                        label: const Text('Общая оплата долгов'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Divider(),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Неоплаченные продажи:',
                                        style: Theme.of(context).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 8),
                                      ...((debtor['unpaid_sales'] as List).map((sale) {
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: Card(
                                            color: Colors.grey.shade50,
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(
                                                        'Продажа #${sale['id']}',
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                      Text(
                                                        '${(sale['remaining_debt'] as num).toStringAsFixed(2)} ₸',
                                                        style: TextStyle(
                                                          color: AppColors.danger,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Сумма: ${(sale['total_price'] as num).toStringAsFixed(2)} ₸ | Оплачено: ${(sale['paid_amount'] as num).toStringAsFixed(2)} ₸',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: AppColors.muted,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Дата: ${sale['created_at']}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: AppColors.muted,
                                                    ),
                                                  ),
                                                  if ((sale['items'] as List).isNotEmpty) ...[
                                                    const SizedBox(height: 8),
                                                    const Divider(),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Товары:',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    ...((sale['items'] as List).map((item) {
                                                      return Padding(
                                                        padding: const EdgeInsets.only(
                                                          left: 8,
                                                          top: 2,
                                                        ),
                                                        child: Text(
                                                          '• ${item['name']} - ${(item['quantity'] as num).toStringAsFixed(item['unit'] == 'pcs' ? 0 : 2)} ${item['unit'] == 'pcs' ? 'шт' : 'г'} × ${(item['price'] as num).toStringAsFixed(2)} ₸',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: AppColors.muted,
                                                          ),
                                                        ),
                                                      );
                                                    })),
                                                  ],
                                                  const SizedBox(height: 12),
                                                  SizedBox(
                                                    width: double.infinity,
                                                    child: OutlinedButton.icon(
                                                      onPressed: () {
                                                        context.push('/sales/sale/${sale['id']}');
                                                      },
                                                      icon: const Icon(Icons.open_in_new, size: 18),
                                                      label: const Text('Открыть продажу'),
                                                      style: OutlinedButton.styleFrom(
                                                        foregroundColor: AppColors.primary,
                                                        side: const BorderSide(color: AppColors.primary),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      })),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
