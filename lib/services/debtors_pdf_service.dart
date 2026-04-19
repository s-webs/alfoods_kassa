import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class DebtorsPdfService {
  static Future<pw.ThemeData?> _loadCyrillicTheme() async {
    if (!Platform.isWindows) return null;
    try {
      final fontPath = r'C:\Windows\Fonts\arial.ttf';
      final file = File(fontPath);
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

  static String _formatPrice(double v) {
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    return s.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
  }

  static Future<Uint8List> buildDebtorsPdf(
    List<Map<String, dynamic>> debtors,
  ) async {
    final theme = await _loadCyrillicTheme();
    final pdf = pw.Document(theme: theme);

    final totalDebt = debtors.fold<double>(
      0,
      (sum, debtor) => sum + (debtor['total_debt'] as num).toDouble(),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'Список должников',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  'На ${DateTime.now().day.toString().padLeft(2, '0')}.${DateTime.now().month.toString().padLeft(2, '0')}.${DateTime.now().year}',
                  style: pw.TextStyle(fontSize: 12),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FixedColumnWidth(100),
                  2: const pw.FixedColumnWidth(100),
                  3: const pw.FixedColumnWidth(120),
                },
                border: pw.TableBorder.all(width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children: [
                      _headerCell('Покупатель', 10),
                      _headerCell('Сумма долга, ₸', 10),
                      _headerCell('Кол-во продаж', 10),
                      _headerCell('Последняя продажа', 10),
                    ],
                  ),
                  ...debtors.map((debtor) {
                    final lastSaleDate = debtor['last_sale_date'] as String?;
                    final dateStr = lastSaleDate != null
                        ? DateTime.parse(lastSaleDate)
                            .toString()
                            .substring(0, 10)
                            .replaceAll('-', '.')
                        : '—';
                    return pw.TableRow(
                      children: [
                        _cell(debtor['name'] as String, 9),
                        _cellRight(
                          _formatPrice(
                            (debtor['total_debt'] as num).toDouble(),
                          ),
                          9,
                        ),
                        _cellRight(
                          (debtor['unpaid_sales_count'] as int).toString(),
                          9,
                        ),
                        _cell(dateStr, 9),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Итого долг:',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '${_formatPrice(totalDebt)} ₸',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 30),
              // Детализация по каждому контрагенту
              ...debtors.map((debtor) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey200,
                        border: pw.Border.all(width: 0.5),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              debtor['name'] as String,
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Text(
                            'Долг: ${_formatPrice((debtor['total_debt'] as num).toDouble())} ₸',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Table(
                      columnWidths: {
                        0: const pw.FixedColumnWidth(60),
                        1: const pw.FlexColumnWidth(2),
                        2: const pw.FixedColumnWidth(80),
                        3: const pw.FixedColumnWidth(80),
                        4: const pw.FixedColumnWidth(80),
                      },
                      border: pw.TableBorder.all(width: 0.5),
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.grey200,
                          ),
                          children: [
                            _headerCell('№', 8),
                            _headerCell('Товары', 8),
                            _headerCell('Сумма, ₸', 8),
                            _headerCell('Оплачено, ₸', 8),
                            _headerCell('Остаток, ₸', 8),
                          ],
                        ),
                        ...((debtor['unpaid_sales'] as List).map((sale) {
                          final items = sale['items'] as List;
                          final itemsText = items
                              .map((item) =>
                                  '${item['name']} - ${(item['quantity'] as num).toStringAsFixed(item['unit'] == 'pcs' ? 0 : 2)} ${item['unit'] == 'pcs' ? 'шт' : 'г'} × ${(item['price'] as num).toStringAsFixed(2)} ₸')
                              .join(', ');
                          return pw.TableRow(
                            children: [
                              _cellRight('${sale['id']}', 8),
                              _cell(itemsText, 7),
                              _cellRight(
                                _formatPrice(
                                  (sale['total_price'] as num).toDouble(),
                                ),
                                8,
                              ),
                              _cellRight(
                                _formatPrice(
                                  (sale['paid_amount'] as num).toDouble(),
                                ),
                                8,
                              ),
                              _cellRight(
                                _formatPrice(
                                  (sale['remaining_debt'] as num).toDouble(),
                                ),
                                8,
                                bold: true,
                              ),
                            ],
                          );
                        })),
                      ],
                    ),
                    pw.SizedBox(height: 20),
                  ],
                );
              }).toList(),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _cell(String text, double fontSize, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        maxLines: 5,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  static pw.Widget _cellRight(
    String text,
    double fontSize, {
    bool bold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: pw.TextAlign.right,
        maxLines: 5,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  static pw.Widget _headerCell(String text, double fontSize) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: fontSize),
        textAlign: pw.TextAlign.center,
        maxLines: 3,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }
}
