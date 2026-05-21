import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/fiscal_receipt.dart';

class FiscalReceiptDialog extends StatelessWidget {
  const FiscalReceiptDialog({
    super.key,
    required this.fiscal,
  });

  final FiscalReceipt fiscal;

  static Future<void> show(
    BuildContext context, {
    required FiscalReceipt fiscal,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => FiscalReceiptDialog(fiscal: fiscal),
    );
  }


  static Future<void> openTicketUrl(
    BuildContext context,
    String? url,
  ) async {
    if (url == null || url.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть ссылку на чек')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Фискальный чек'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fiscal.offlineMode)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Касса работала в автономном режиме. Чек будет передан в ОФД при восстановлении связи.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            if (fiscal.checkNumber != null && fiscal.checkNumber!.isNotEmpty)
              Text('Номер чека: ${fiscal.checkNumber}'),
            if (fiscal.externalCheckNumber != null &&
                fiscal.externalCheckNumber!.isNotEmpty)
              _copyableRow(
                context,
                'ExternalCheckNumber',
                fiscal.externalCheckNumber!,
              ),
            if (fiscal.shiftNumber != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Смена WebKassa: ${fiscal.shiftNumber}'),
              ),
          ],
        ),
      ),
      actions: [
        if (fiscal.ticketPrintUrl != null &&
            fiscal.ticketPrintUrl!.isNotEmpty)
          TextButton(
            onPressed: () =>
                openTicketUrl(context, fiscal.ticketPrintUrl),
            child: const Text('Печать (WebKassa)'),
          ),
        FilledButton(
          onPressed: fiscal.ticketUrl != null && fiscal.ticketUrl!.isNotEmpty
              ? () => openTicketUrl(context, fiscal.ticketUrl)
              : null,
          child: const Text('Открыть чек'),
        ),
      ],
    );
  }

  static Widget _copyableRow(
    BuildContext context,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12)),
                SelectableText(
                  value,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Копировать',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label скопирован')),
              );
            },
          ),
        ],
      ),
    );
  }
}
