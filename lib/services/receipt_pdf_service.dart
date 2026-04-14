import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/cart_item.dart';

/// Формирует чек в формате PDF (80мм по ширине) для сохранения в файл.
class ReceiptPdfService {
  static const String _companyName = 'Almaty Foods';

  /// Высота страницы (полная, pt→мм ниже): должна быть близка к реальному Column,
  /// иначе под «Спасибо» остаётся пустой хвост.
  static double _estimateReceiptHeightMm(List<CartItem> items) {
    // Верх: логотип-текст, кассир, № чека, разделитель (см. build ниже).
    const topBlockMm = 34.0;
    const tableHeaderRowMm = 5.5;
    // Низ: разделитель, таблица итогов, ИТОГО, отступ, дата, «Спасибо» + крошечный запас.
    const bottomBlockMm = 23.0;
    const safetyMm = 1.0;
    // Колонка названия шире № — больше символов в строке, чем в старых 11.
    const charsPerLine = 13;
    const mmPerNameLine = 3.0;
    const minNameBlockMm = 3.8;
    // Соответствует padding vertical: 6 у ячеек строк (~4.2 мм на строку позиций).
    const rowVerticalPadMm = 4.3;

    var rowsMm = 0.0;
    for (final item in items) {
      final nameLen = item.name.trim().length;
      final lines = nameLen == 0
          ? 1
          : math.min(14, (nameLen / charsPerLine).ceil());
      final nameH = math.max(minNameBlockMm, lines * mmPerNameLine);
      rowsMm += nameH + rowVerticalPadMm;
    }
    if (items.isEmpty) {
      rowsMm = minNameBlockMm + rowVerticalPadMm;
    }

    // Поля pw.Page vertical 8+8 pt — вычитаются из высоты листа, иначе обрежется низ.
    const pageVerticalMarginMm = 16.0 * 25.4 / 72.0;

    final h = topBlockMm +
        tableHeaderRowMm +
        rowsMm +
        bottomBlockMm +
        safetyMm +
        pageVerticalMarginMm;
    return h.clamp(88.0, 2000.0);
  }

  static String _formatSum(double v) {
    final s = v.toStringAsFixed(0);
    return s.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
  }

  static String _formatQty(double qty) {
    final rounded = qty.roundToDouble();
    if ((qty - rounded).abs() < 1e-9) return rounded.toInt().toString();
    final s = qty.toStringAsFixed(2);
    return s.replaceAll(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
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

  /// Формирует PDF чек и возвращает байты (формат 80мм).
  static Future<Uint8List> buildReceiptPdf({
    required int saleId,
    required String cashierName,
    required List<CartItem> items,
    required double total,
    required double totalQty,
    required DateTime dateTime,
  }) async {
    final theme = await _loadCyrillicTheme();
    final pdf = pw.Document(theme: theme);
    final dtStr =
        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';

    final pageFormat = PdfPageFormat(
      PdfPageFormat.roll80.width,
      _estimateReceiptHeightMm(items) * PdfPageFormat.mm,
    );
    const margin =
        pw.EdgeInsets.only(left: 6, right: 13, top: 8, bottom: 8);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: margin,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                _companyName,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Кассир: $cashierName',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Товарный чек № $saleId',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 4),
              pw.Table(
                columnWidths: {
                  0: const pw.FixedColumnWidth(20), // №
                  1: const pw.FlexColumnWidth(3), // Наименование — единственная колонка с переносами
                  2: const pw.FixedColumnWidth(24), // К-во
                  3: const pw.FixedColumnWidth(26), // Цена
                  4: const pw.FixedColumnWidth(40), // Сумма (приоритет по ширине)
                },
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 2, bottom: 2),
                        child: pw.Text(
                          '№',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.left,
                          maxLines: 1,
                          softWrap: false,
                          overflow: pw.TextOverflow.clip,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: pw.Text(
                          'Наименование',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.left,
                          maxLines: 1,
                          softWrap: false,
                          overflow: pw.TextOverflow.clip,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: pw.Text(
                          'К-во',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.right,
                          maxLines: 1,
                          softWrap: false,
                          overflow: pw.TextOverflow.clip,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: pw.Text(
                          'Цена',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.right,
                          maxLines: 1,
                          softWrap: false,
                          overflow: pw.TextOverflow.clip,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(left: 2, bottom: 2),
                        child: pw.Text(
                          'Сумма',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.right,
                          maxLines: 1,
                          softWrap: false,
                          overflow: pw.TextOverflow.clip,
                        ),
                      ),
                    ],
                  ),
                  ...items.asMap().entries.map((e) {
                    final i = e.key + 1;
                    final item = e.value;
                    final qty = item.unit == 'pcs'
                        ? item.quantity.toInt().toString()
                        : item.quantity.toStringAsFixed(2);
                    const cellPad = pw.EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 6,
                    );
                    final numStyle = pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    );
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: cellPad.copyWith(right: 2),
                          child: pw.Text(
                            '$i',
                            style: numStyle,
                            textAlign: pw.TextAlign.left,
                            maxLines: 1,
                            softWrap: false,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: cellPad,
                          child: pw.Text(
                            item.name,
                            style: numStyle,
                            textAlign: pw.TextAlign.left,
                            maxLines: null,
                            softWrap: true,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: cellPad,
                          child: pw.Text(
                            qty,
                            style: numStyle,
                            textAlign: pw.TextAlign.right,
                            maxLines: 1,
                            softWrap: false,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: cellPad,
                          child: pw.Text(
                            _formatSum(item.price),
                            style: numStyle,
                            textAlign: pw.TextAlign.right,
                            maxLines: 1,
                            softWrap: false,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: cellPad,
                          child: pw.Text(
                            _formatSum(item.total),
                            style: numStyle,
                            textAlign: pw.TextAlign.right,
                            maxLines: 1,
                            softWrap: false,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1),
              // После линии: строка "К-ВО", число в колонке количества.
              pw.Table(
                columnWidths: {
                  0: const pw.FixedColumnWidth(0),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FixedColumnWidth(24),
                  3: const pw.FixedColumnWidth(26),
                  4: const pw.FixedColumnWidth(40),
                },
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 2),
                        child: pw.Text(
                          '',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.left,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 2),
                        child: pw.Text(
                          'ОБЩЕЕ КОЛИЧЕСТВО',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.left,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 2),
                        child: pw.Text(
                          _formatQty(totalQty),
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 2),
                        child: pw.Text(
                          '',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 2),
                        child: pw.Text(
                          '',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'ИТОГО',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _formatSum(total),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Text(
                dtStr,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Спасибо за покупку!',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
