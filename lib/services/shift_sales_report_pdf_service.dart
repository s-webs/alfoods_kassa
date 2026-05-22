import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/sale.dart';
import '../models/sale_payment_method.dart';
import '../utils/time_util.dart';

/// PDF-отчёт по продажам смены.
class ShiftSalesReportPdfService {
  static Future<Uint8List> build({
    int? shiftId,
    required String periodLabel,
    required String filterLabel,
    required List<Sale> sales,
  }) async {
    final theme = await _loadCyrillicTheme();
    final pdf = pw.Document(theme: theme);

    final sorted = List<Sale>.from(sales)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final totalAmount = sorted.fold<double>(
      0,
      (s, sale) => s + _reportAmount(sale),
    );
    final totalQty = sorted.fold<int>(0, (s, sale) => s + sale.totalQty);
    final now = TimeUtil.toUtcPlus5Wall(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              shiftId != null ? 'Отчёт по смене №$shiftId' : 'Отчёт по продажам',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              periodLabel,
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              'Фильтр: $filterLabel',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              'Сформирован: ${_formatDateTime(now)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            columnWidths: {
              0: const pw.FixedColumnWidth(42),
              1: const pw.FixedColumnWidth(88),
              2: const pw.FixedColumnWidth(72),
              3: const pw.FixedColumnWidth(40),
              4: const pw.FlexColumnWidth(2),
              5: const pw.FlexColumnWidth(1.5),
            },
            border: pw.TableBorder.all(width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _headerCell('№'),
                  _headerCell('Дата'),
                  _headerCell('Сумма, ₸'),
                  _headerCell('Кол-во'),
                  _headerCell('Оплата'),
                  _headerCell('Статус'),
                ],
              ),
              ...sorted.map(
                (sale) => pw.TableRow(
                  children: [
                    _cell('${sale.id}', alignRight: true),
                    _cell(
                      _formatDateTime(TimeUtil.toUtcPlus5Wall(sale.createdAt)),
                    ),
                    _cell(_formatPrice(_reportAmount(sale)), alignRight: true),
                    _cell('${sale.totalQty}', alignRight: true),
                    _cell(_paymentLabel(sale)),
                    _cell(_statusLabel(sale)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Продаж: ${sorted.length}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Кол-во позиций: $totalQty',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Итого: ${_formatPrice(totalAmount)} ₸',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static double _reportAmount(Sale sale) {
    if (sale.isPartiallyReturned) {
      return sale.remainingTotalAfterReturns;
    }
    return sale.totalPrice;
  }

  static String _paymentLabel(Sale sale) {
    return SalePaymentMethod.tryParse(sale.paymentMethod)?.label ??
        (sale.paymentMethod ?? '—');
  }

  static String _statusLabel(Sale sale) {
    if (sale.isReturnRecord) return 'Возврат';
    return switch (sale.status) {
      Sale.statusReturned => 'Полный возврат',
      Sale.statusPartiallyReturned => 'Частичный возврат',
      _ => 'Продажа',
    };
  }

  static String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _formatPrice(double v) {
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    return s.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
  }

  static pw.Widget _headerCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _cell(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 8),
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      ),
    );
  }

  static Future<pw.ThemeData?> _loadCyrillicTheme() async {
    if (!Platform.isWindows) return null;
    try {
      final file = File(r'C:\Windows\Fonts\arial.ttf');
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final font = pw.Font.ttf(bytes.buffer.asByteData());
      return pw.ThemeData.withFont(
        base: font,
        bold: font,
        italic: font,
        boldItalic: font,
      );
    } catch (_) {
      return null;
    }
  }
}
