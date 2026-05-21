import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Просмотр Z-отчёта WebKassa (ответ POST /api/v4/ZReport — без ссылки, только Data).
class ZReportDialog extends StatelessWidget {
  const ZReportDialog({
    super.key,
    required this.zReport,
    this.zReportAt,
  });

  final Map<String, dynamic> zReport;
  final DateTime? zReportAt;

  static bool hasViewableData(Map<String, dynamic>? zReport) {
    return zReport != null && zReport.isNotEmpty;
  }

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> zReport,
    DateTime? zReportAt,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ZReportDialog(zReport: zReport, zReportAt: zReportAt),
    );
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String? _money(dynamic v) {
    if (v == null) return null;
    if (v is num) {
      return '${v.toStringAsFixed(v is int || v == v.roundToDouble() ? 0 : 2)} ₸';
    }
    return _str(v);
  }

  List<({String label, String value})> _rows() {
    final rows = <({String label, String value})>[];

    void add(String label, dynamic value, {bool money = false}) {
      final v = money ? _money(value) : _str(value);
      if (v != null) {
        rows.add((label: label, value: v));
      }
    }

    add('№ Z-отчёта', zReport['ReportNumber']);
    add('№ смены WebKassa', zReport['ShiftNumber']);
    add('Начало смены', zReport['StartOn']);
    add('Закрытие смены', zReport['CloseOn']);
    add('Дата отчёта', zReport['ReportOn']);
    add('Организация', zReport['TaxPayerName']);
    add('ИИН/БИН', zReport['TaxPayerIN']);
    add('ЗНК', zReport['CashboxSN']);
    add('РНК', zReport['CashboxRN']);
    add('Кассир', zReport['CashierName']);
    add('Документов за смену', zReport['DocumentCount']);
    add('Наличных в кассе', zReport['SumInCashbox'], money: true);
    add('Внесения', zReport['PutMoneySum'], money: true);
    add('Изъятия', zReport['TakeMoneySum'], money: true);

    final sell = zReport['Sell'];
    if (sell is Map) {
      add('Продажи (сумма)', sell['Taken'], money: true);
      add('Продажи (операций)', sell['Count']);
      add('НДС продаж', sell['VAT'], money: true);
    }

    final returnSell = zReport['ReturnSell'];
    if (returnSell is Map && (returnSell['Count'] as num? ?? 0) > 0) {
      add('Возвраты (сумма)', returnSell['Taken'], money: true);
      add('Возвраты (операций)', returnSell['Count']);
    }

    if (zReport['OfflineMode'] == true) {
      rows.add((
        label: 'Режим',
        value: 'Автономный (offline)',
      ));
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();

    return AlertDialog(
      title: const Text('Z-отчёт WebKassa'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (zReportAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Сформирован: ${zReportAt!.toLocal().toString().substring(0, 16)}',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              ...rows.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 150,
                        child: Text(
                          r.label,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          r.value,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
