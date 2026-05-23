import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/cart_item.dart';

/// Формирует чек в формате PDF (80мм по ширине) для сохранения в файл.
class ReceiptPdfService {
  static const String _companyName = 'Almaty Foods';

  /// Ширина листа 80 мм (pt).
  static final double _pageWidthPt = PdfPageFormat.roll80.width;

  /// Горизонтальные поля страницы (pt), симметрично.
  static const double _horizontalMarginPt = 6;

  // Доли как в RAW-чеке (~48 символов): 3+20+5+8+8, с запасом под «9 999 999».
  // Сумма фиксированных колонок + flex «Наименование» укладывается в
  // _pageWidthPt - 2 * _horizontalMarginPt.
  static const double _colNoPt = 14;
  static const double _colQtyPt = 22;
  static const double _colPricePt = 46;
  static const double _colSumPt = 50;

  static Map<int, pw.TableColumnWidth> get _receiptColumnWidths => {
        0: const pw.FixedColumnWidth(_colNoPt),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FixedColumnWidth(_colQtyPt),
        3: const pw.FixedColumnWidth(_colPricePt),
        4: const pw.FixedColumnWidth(_colSumPt),
      };

  static const pw.EdgeInsets _nameCellPad =
      pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2);
  static const pw.EdgeInsets _numCellPad =
      pw.EdgeInsets.symmetric(horizontal: 1, vertical: 2);
  static const pw.EdgeInsets _itemNamePad =
      pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4);
  static const pw.EdgeInsets _itemNumPad =
      pw.EdgeInsets.symmetric(horizontal: 1, vertical: 4);
  static const pw.EdgeInsets _itemNoPad =
      pw.EdgeInsets.only(left: 0, right: 1, top: 4, bottom: 4);

  static pw.TextStyle get _headerStyle => pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
      );

  static pw.TextStyle get _rowStyle => pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
      );

  static pw.TextStyle get _footerStyle => pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
      );

  static pw.TextStyle get _footerTotalStyle => pw.TextStyle(
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
      );

  static pw.EdgeInsets get _footerPadNo =>
      _itemNoPad.copyWith(top: 0, bottom: 0);

  static pw.EdgeInsets get _footerValuePad =>
      _itemNumPad.copyWith(top: 0, bottom: 0);

  /// Итоги: отдельная таблица key | value (левый край как у колонки «№»).
  static pw.Widget _footerTable({
    required double totalQty,
    required double total,
  }) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(2),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          children: [
            pw.Padding(
              padding: _footerPadNo,
              child: pw.Text(
                'Общее количество товаров',
                style: _footerStyle,
                textAlign: pw.TextAlign.left,
              ),
            ),
            pw.Padding(
              padding: _footerValuePad,
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  _formatQty(totalQty),
                  style: _footerStyle,
                  textAlign: pw.TextAlign.right,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
          ],
        ),
        pw.TableRow(
          children: [
            pw.Padding(
              padding: _footerPadNo,
              child: pw.Text(
                'Итоговая сумма',
                style: _footerTotalStyle,
                textAlign: pw.TextAlign.left,
              ),
            ),
            pw.Padding(
              padding: _footerValuePad,
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  _formatSum(total),
                  style: _footerTotalStyle,
                  textAlign: pw.TextAlign.right,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Правый столбец с числом: при нехватке места уменьшает шрифт, не обрезает.
  static pw.Widget _fittedRightText(
    String text, {
    required pw.TextStyle style,
    pw.TextAlign textAlign = pw.TextAlign.right,
  }) {
    return pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      alignment: textAlign == pw.TextAlign.right
          ? pw.Alignment.centerRight
          : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: 1,
        softWrap: false,
      ),
    );
  }

  /// Высота страницы (мм): должна быть **не меньше** реального Column.
  /// При занижении pdf обрезает низ (итоги, дата, «Спасибо») — остаётся белое поле.
  static double _estimateReceiptHeightMm(List<CartItem> items) {
    // Шапка + заголовок таблицы + низ чека + поля страницы.
    const fixedMm = 36.0 + 7.0 + 36.0 + (16.0 * 25.4 / 72.0);
    // Каждая позиция: padding ячеек + FittedBox в числовых колонках.
    const mmPerItemRow = 8.0;
    const charsPerLine = 12;
    const mmPerExtraNameLine = 3.5;

    var rowsMm = items.isEmpty ? mmPerItemRow : 0.0;
    for (final item in items) {
      final nameLen = item.name.trim().length;
      final lines = nameLen == 0
          ? 1
          : math.min(14, (nameLen / charsPerLine).ceil());
      rowsMm += mmPerItemRow + math.max(0, lines - 1) * mmPerExtraNameLine;
    }

    // Запас на погрешность вёрстки таблицы (лучше чуть длиннее лист, чем обрезка).
    const safetyMm = 12.0;
    return (fixedMm + rowsMm + safetyMm).clamp(115.0, 2000.0);
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
      _pageWidthPt,
      _estimateReceiptHeightMm(items) * PdfPageFormat.mm,
    );
    const margin = pw.EdgeInsets.symmetric(
      horizontal: _horizontalMarginPt,
      vertical: 8,
    );

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
                columnWidths: _receiptColumnWidths,
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: _itemNoPad.copyWith(
                          top: 2,
                          bottom: 2,
                          right: 1,
                        ),
                        child: pw.Text(
                          '№',
                          style: _headerStyle,
                          textAlign: pw.TextAlign.left,
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                      pw.Padding(
                        padding: _nameCellPad,
                        child: pw.Text(
                          'Наименование',
                          style: _headerStyle,
                          textAlign: pw.TextAlign.left,
                          maxLines: 1,
                          softWrap: false,
                          overflow: pw.TextOverflow.clip,
                        ),
                      ),
                      pw.Padding(
                        padding: _numCellPad,
                        child: _fittedRightText('К-во', style: _headerStyle),
                      ),
                      pw.Padding(
                        padding: _numCellPad,
                        child: _fittedRightText('Цена', style: _headerStyle),
                      ),
                      pw.Padding(
                        padding: _numCellPad,
                        child: _fittedRightText('Сумма', style: _headerStyle),
                      ),
                    ],
                  ),
                  ...items.asMap().entries.map((e) {
                    final i = e.key + 1;
                    final item = e.value;
                    final qty = item.unit == 'pcs'
                        ? item.quantity.toInt().toString()
                        : item.quantity.toStringAsFixed(2);
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: _itemNoPad,
                          child: pw.Text(
                            '$i',
                            style: _rowStyle,
                            textAlign: pw.TextAlign.left,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                        pw.Padding(
                          padding: _itemNamePad,
                          child: pw.Text(
                            item.name,
                            style: _rowStyle,
                            textAlign: pw.TextAlign.left,
                            maxLines: null,
                            softWrap: true,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: _itemNumPad,
                          child: _fittedRightText(qty, style: _rowStyle),
                        ),
                        pw.Padding(
                          padding: _itemNumPad,
                          child: _fittedRightText(
                            _formatSum(item.price),
                            style: _rowStyle,
                          ),
                        ),
                        pw.Padding(
                          padding: _itemNumPad,
                          child: _fittedRightText(
                            _formatSum(item.total),
                            style: _rowStyle,
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 4),
              _footerTable(totalQty: totalQty, total: total),
              pw.SizedBox(height: 10),
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
