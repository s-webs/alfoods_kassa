import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/cart_item.dart';

/// Формирует чек в формате PDF (80мм по ширине) для сохранения в файл.
class ReceiptPdfService {
  static const String _companyName = 'Almaty Foods';

  static String _formatSum(double v) {
    final s = v.toStringAsFixed(0);
    return s.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
  }

  /// Загружает шрифт с поддержкой кириллицы (Windows Arial).
  static Future<pw.ThemeData?> _loadCyrillicTheme() async {
    if (!Platform.isWindows) return null;
    try {
      final fontPath = r'C:\Windows\Fonts\arial.ttf';
      final file = File(fontPath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final font = pw.Font.ttf(bytes.buffer.asByteData());
      return pw.ThemeData.withFont(base: font, bold: font, italic: font, boldItalic: font);
    } catch (_) {
      return null;
    }
  }

  /// Формирует PDF чек и возвращает байты (формат 80мм).
  static Future<Uint8List> buildReceiptPdf({
    required int saleId,
    required String cashierName,
    required List<CartItem> items,
    required double total,
    required DateTime dateTime,
  }) async {
    final theme = await _loadCyrillicTheme();
    final pdf = pw.Document(theme: theme);
    final dtStr =
        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(12),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                _companyName,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text('Кассир: $cashierName', style: const pw.TextStyle(fontSize: 10)),
              ),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text('Товарный чек № $saleId', style: const pw.TextStyle(fontSize: 10)),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 4),
              pw.Table(
                columnWidths: {
                  0: const pw.FixedColumnWidth(16), // №
                  1: const pw.FlexColumnWidth(3), // Наименование
                  2: const pw.FixedColumnWidth(30), // К-во
                  3: const pw.FixedColumnWidth(32), // Цена
                  4: const pw.FixedColumnWidth(36), // Сумма
                },
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 2),
                        child: pw.Text(
                          '№',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.left,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                        child: pw.Text(
                          'Наименование',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.left,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                        child: pw.Text(
                          'К-во',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                        child: pw.Text(
                          'Цена',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(left: 2),
                        child: pw.Text(
                          'Сумма',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  ...items.asMap().entries.map((e) {
                    final i = e.key + 1;
                    final item = e.value;
                    final name = item.name.length > 22 ? '${item.name.substring(0, 21)}…' : item.name;
                    final qty = item.unit == 'pcs'
                        ? item.quantity.toInt().toString()
                        : item.quantity.toStringAsFixed(2);
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(right: 2, top: 2, bottom: 2),
                          child: pw.Text(
                            '$i',
                            style: const pw.TextStyle(fontSize: 9),
                            textAlign: pw.TextAlign.left,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                          child: pw.Text(
                            name,
                            style: const pw.TextStyle(fontSize: 9),
                            textAlign: pw.TextAlign.left,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                          child: pw.Text(
                            qty,
                            style: const pw.TextStyle(fontSize: 9),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                          child: pw.Text(
                            _formatSum(item.price),
                            style: const pw.TextStyle(fontSize: 9),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                          child: pw.Text(
                            _formatSum(item.total),
                            style: const pw.TextStyle(fontSize: 9),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('ИТОГО', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.Text(_formatSum(total), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Text(dtStr, style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 8),
              pw.Text(
                'Спасибо за покупку!',
                style: pw.TextStyle(fontSize: 10),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
