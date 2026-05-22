/// Текстовые строки Z-отчёта WebKassa для экрана и печати.
class ZReportFormatter {
  ZReportFormatter._();

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String? _money(dynamic v) {
    if (v == null) return null;
    if (v is num) {
      final fixed = v is int || v == v.roundToDouble()
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(2);
      return '$fixed ₸';
    }
    return _str(v);
  }

  static void _addLine(List<String> out, String line) {
    if (line.isNotEmpty) {
      out.add(line);
    }
  }

  static void _addPair(List<String> out, String label, dynamic value, {bool money = false}) {
    final v = money ? _money(value) : _str(value);
    if (v != null) {
      _addLine(out, '$label: $v');
    }
  }

  /// Строки для печати / просмотра (первая строка — заголовок).
  static List<String> formatLines(
    Map<String, dynamic> zReport, {
    DateTime? zReportAt,
  }) {
    final lines = <String>['Z-ОТЧЁТ WEBKASSA'];

    if (zReportAt != null) {
      _addLine(
        lines,
        'Сформирован: ${zReportAt.toLocal().toString().substring(0, 16)}',
      );
    }

    _addPair(lines, '№ Z-отчёта', zReport['ReportNumber']);
    _addPair(lines, '№ смены', zReport['ShiftNumber']);
    _addPair(lines, 'Начало смены', zReport['StartOn']);
    _addPair(lines, 'Закрытие смены', zReport['CloseOn']);
    _addPair(lines, 'Дата отчёта', zReport['ReportOn']);
    _addPair(lines, 'Организация', zReport['TaxPayerName']);
    _addPair(lines, 'ИИН/БИН', zReport['TaxPayerIN']);
    _addPair(lines, 'ЗНК', zReport['CashboxSN']);
    _addPair(lines, 'РНК', zReport['CashboxRN']);
    _addPair(lines, 'Кассир', zReport['CashierName']);
    _addPair(lines, 'Документов', zReport['DocumentCount']);
    _addPair(lines, 'Наличных в кассе', zReport['SumInCashbox'], money: true);
    _addPair(lines, 'Внесения', zReport['PutMoneySum'], money: true);
    _addPair(lines, 'Изъятия', zReport['TakeMoneySum'], money: true);

    final sell = zReport['Sell'];
    if (sell is Map) {
      lines.add('--- Продажи ---');
      _addPair(lines, '  Сумма', sell['Taken'], money: true);
      _addPair(lines, '  Операций', sell['Count']);
      _addPair(lines, '  НДС', sell['VAT'], money: true);
    }

    final returnSell = zReport['ReturnSell'];
    if (returnSell is Map && (returnSell['Count'] as num? ?? 0) > 0) {
      lines.add('--- Возвраты ---');
      _addPair(lines, '  Сумма', returnSell['Taken'], money: true);
      _addPair(lines, '  Операций', returnSell['Count']);
    }

    if (zReport['OfflineMode'] == true) {
      _addLine(lines, 'Режим: автономный (offline)');
    }

    return lines;
  }
}
