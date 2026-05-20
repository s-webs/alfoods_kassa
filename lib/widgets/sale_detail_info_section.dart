import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../models/sale.dart';
import '../models/sale_payment_method.dart';
import 'sale_payment_chip.dart';

class SaleDetailInfoSection extends StatelessWidget {
  const SaleDetailInfoSection({
    super.key,
    required this.sale,
  });

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final method = SalePaymentMethod.tryParse(sale.paymentMethod);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SaleStatusChip(sale: sale),
                const SizedBox(width: 8),
                Expanded(child: SalePaymentChip(sale: sale)),
              ],
            ),
            const SizedBox(height: 12),
            _row('Внутренний №', '#${sale.id}'),
            if (sale.webkassaCheckNumber != null &&
                sale.webkassaCheckNumber!.isNotEmpty)
              _row('Чек WebKassa', sale.webkassaCheckNumber!),
            if (sale.fiscalStatus != null && sale.fiscalStatus!.isNotEmpty)
              _row('Фискализация', sale.fiscalStatus!),
            if (method != null) _row('Способ оплаты', method.label),
            if (sale.offlineMode) _row('Режим', 'Автономный (ОФД позже)'),
            if (sale.isReturnRecord && sale.originalSaleId != null)
              InkWell(
                onTap: () => context.push('/sales/sale/${sale.originalSaleId}'),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Исходная продажа №${sale.originalSaleId}',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            if (sale.returnSales.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Возвраты',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ...sale.returnSales.map(
                (r) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Возврат №${r.id} — ${r.totalPrice.toStringAsFixed(2)} ₸',
                  ),
                  subtitle: r.webkassaCheckNumber != null
                      ? Text('Фиск. ${r.webkassaCheckNumber}')
                      : null,
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push('/sales/sale/${r.id}'),
                ),
              ),
            ],
            if (sale.ticketUrl != null && sale.ticketUrl!.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _openUrl(sale.ticketUrl!),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Открыть чек WebKassa'),
              ),
            ],
            if (sale.posTransaction != null) ...[
              const Divider(),
              _row(
                'Kaspi POS',
                '${sale.posTransaction!.method} • ${sale.posTransaction!.amount} ₸',
              ),
              _row('Транзакция', sale.posTransaction!.transactionId),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
