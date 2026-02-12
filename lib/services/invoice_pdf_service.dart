import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/cart_item.dart';
import '../utils/amount_in_words.dart';

/// Данные для накладной форма 3-2.
class InvoiceData {
  final String senderName;
  final String senderIinBin;
  final String documentNumber;
  final DateTime documentDate;
  final String receiverName;
  final String? receiverIin;
  final String? receiverAddress;
  final String? responsiblePerson;
  final String? transportOrg;
  final String? ttnNumber;
  final String? ttnDate;
  final String? approvedBy;
  final String? warrantNumber;
  final String? warrantIssuedBy;
  final String? chiefAccountant;
  final String? releasedBy;
  final List<InvoiceLineItem> items;

  const InvoiceData({
    required this.senderName,
    required this.senderIinBin,
    required this.documentNumber,
    required this.documentDate,
    required this.receiverName,
    this.receiverIin,
    this.receiverAddress,
    this.responsiblePerson,
    this.transportOrg,
    this.ttnNumber,
    this.ttnDate,
    this.approvedBy,
    this.warrantNumber,
    this.warrantIssuedBy,
    this.chiefAccountant,
    this.releasedBy,
    required this.items,
  });
}

/// Позиция накладной (наименование, номенклатурный номер, кол-во, цена, сумма).
class InvoiceLineItem {
  final String name;
  final String nomenclatureNumber;
  final String unit;
  final double quantityToRelease;
  final double quantityReleased;
  final double pricePerUnit;
  final double totalWithoutVat;
  final double totalWithVat;

  const InvoiceLineItem({
    required this.name,
    required this.nomenclatureNumber,
    required this.unit,
    required this.quantityToRelease,
    required this.quantityReleased,
    required this.pricePerUnit,
    required this.totalWithoutVat,
    required this.totalWithVat,
  });

  static InvoiceLineItem fromCartItem(
    CartItem item, {
    String? nomenclatureNumber,
  }) {
    final nom = nomenclatureNumber ?? item.productId.toString();
    final total = item.total;
    return InvoiceLineItem(
      name: item.name,
      nomenclatureNumber: nom,
      unit: item.unit == 'pcs' ? 'шт' : 'кг',
      quantityToRelease: item.quantity,
      quantityReleased: item.quantity,
      pricePerUnit: item.price,
      totalWithoutVat: total,
      totalWithVat: total,
    );
  }
}

/// Генерация PDF накладной по форме 3-2 (приложение 26 к приказу МФ РК № 562).
class InvoicePdfService {
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

  static String _formatQty(double qty, String unit) {
    if (unit == 'шт') return qty.toInt().toString();
    return qty.toStringAsFixed(2);
  }

  static Future<Uint8List> buildPdf(InvoiceData data) async {
    final theme = await _loadCyrillicTheme();
    final pdf = pw.Document(theme: theme);
    final dateStr =
        '${data.documentDate.day.toString().padLeft(2, '0')}.${data.documentDate.month.toString().padLeft(2, '0')}.${data.documentDate.year}';

    final totalSum = data.items.fold<double>(0, (s, e) => s + e.totalWithVat);
    final totalQty = data.items.fold<double>(
      0,
      (s, e) => s + e.quantityReleased,
    );
    final totalQtyInt = totalQty.round();
    final qtyWords = quantityInWords(totalQtyInt);
    final sumWords = amountInWordsWithTiyn(totalSum);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Приложение 26', style: pw.TextStyle(fontSize: 8)),
                    pw.Text(
                      'к приказу Министра финансов Республики Казахстан от',
                      style: pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      '20 декабря 2012 года № 562',
                      style: pw.TextStyle(fontSize: 8),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Форма 3-2',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 15),
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FixedColumnWidth(70),
                  2: const pw.FixedColumnWidth(100),
                },
                // border: pw.TableBorder.all(width: 0.5),
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: pw.Row(
                          children: [
                            pw.Text(
                              'Организация (индивидуальный предприниматель) ',
                              style: pw.TextStyle(fontSize: 8),
                            ),
                            pw.Expanded(
                              child: pw.Container(
                                decoration: pw.BoxDecoration(
                                  border: pw.Border(
                                    bottom: pw.BorderSide(width: 0.5),
                                  ),
                                ),
                                child: pw.Text(
                                  data.senderName,
                                  style: const pw.TextStyle(fontSize: 8),
                                  maxLines: 1,
                                  overflow: pw.TextOverflow.clip,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _borderedCell('ИИН/БИН', 8),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(width: 0.5),
                        ),
                        child: pw.Text(
                          data.senderIinBin,
                          style: const pw.TextStyle(fontSize: 8),
                          maxLines: 4,
                          overflow: pw.TextOverflow.clip,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 180,
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Table(
                      columnWidths: {
                        0: const pw.FixedColumnWidth(90),
                        1: const pw.FixedColumnWidth(90),
                      },
                      border: pw.TableBorder.all(width: 0.5),
                      children: [
                        pw.TableRow(
                          children: [
                            _borderedCell('Номер документа', 7),
                            _borderedCell('Дата составления', 7),
                          ],
                        ),
                        pw.TableRow(
                          children: [
                            _borderedCell(data.documentNumber, 8),
                            _borderedCell(dateStr, 8),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.SizedBox(height: 15),
              pw.Center(
                child: pw.Text(
                  'Накладная  на отпуск запасов  на сторону',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FlexColumnWidth(1),
                },
                border: pw.TableBorder.all(width: 0.5),
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    children: [
                      _borderedCell(
                        'Организация (индивидуальный предприниматель) - отправитель',
                        7,
                      ),
                      _borderedCell(
                        'Организация (индивидуальный предприниматель)- получатель',
                        7,
                      ),
                      _borderedCell('Ответственный за поставку (Ф.И.О.)', 7),
                      _borderedCell('Транспортная организация', 7),
                      _borderedCell(
                        'Товарно - транспортная накладная (номер, дата)',
                        7,
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _borderedCell(data.senderName, 8),
                      _borderedCell(data.receiverName, 8),
                      _borderedCell(data.responsiblePerson ?? '', 8),
                      _borderedCell(data.transportOrg ?? '', 8),
                      _borderedCell(
                        _ttnString(data.ttnNumber, data.ttnDate),
                        8,
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              // Первая строка заголовка: одна ячейка «Количество» над двумя подколонками (8 колонок)
              pw.Table(
                columnWidths: {
                  0: const pw.FixedColumnWidth(44),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FixedColumnWidth(50),
                  3: const pw.FixedColumnWidth(26),
                  4: const pw.FixedColumnWidth(
                    80,
                  ), // 42+38 — объединённая ячейка Количество
                  5: const pw.FixedColumnWidth(46),
                  6: const pw.FixedColumnWidth(52),
                  7: const pw.FixedColumnWidth(44),
                },
                border: pw.TableBorder(
                  left: const pw.BorderSide(width: 0.5),
                  top: const pw.BorderSide(width: 0.5),
                  right: const pw.BorderSide(width: 0.5),
                  bottom: pw.BorderSide.none,
                  horizontalInside: const pw.BorderSide(width: 0.5),
                  verticalInside: const pw.BorderSide(width: 0.5),
                ),
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children: [
                      _headerCell('Номер по порядку', 7),
                      _headerCell('Наименование, характеристика', 7),
                      _headerCell('Номенклатурный номер', 7),
                      _headerCell('Единица измерения', 7),
                      _headerCell('Количество', 7),
                      _headerCell('Цена за единицу, в KZT', 7),
                      _headerCell('Сумма с НДС, в KZT', 7),
                      _headerCell('Сумма НДС, в KZT', 7),
                    ],
                  ),
                ],
              ),
              // Вторая строка заголовка + данные + итого: 9 колонок (подлежит отпуску | отпущено)
              pw.Table(
                columnWidths: {
                  0: const pw.FixedColumnWidth(44),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FixedColumnWidth(50),
                  3: const pw.FixedColumnWidth(26),
                  4: const pw.FixedColumnWidth(42),
                  5: const pw.FixedColumnWidth(38),
                  6: const pw.FixedColumnWidth(46),
                  7: const pw.FixedColumnWidth(52),
                  8: const pw.FixedColumnWidth(44),
                },
                border: pw.TableBorder.all(width: 0.5),
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children: [
                      _headerCell('', 7),
                      _headerCell('', 7),
                      _headerCell('', 7),
                      _headerCell('', 7),
                      _headerCell('подлежит отпуску', 7),
                      _headerCell('отпущено', 7),
                      _headerCell('', 7),
                      _headerCell('', 7),
                      _headerCell('', 7),
                    ],
                  ),
                  ...data.items.asMap().entries.map((e) {
                    final i = e.key + 1;
                    final item = e.value;
                    return pw.TableRow(
                      children: [
                        _cellRight('$i', 8),
                        _cell(item.name, 8),
                        _cell(item.nomenclatureNumber, 8),
                        _headerCell(item.unit, 8),
                        _cellRight(
                          _formatQty(item.quantityToRelease, item.unit),
                          8,
                        ),
                        _cellRight(
                          _formatQty(item.quantityReleased, item.unit),
                          8,
                        ),
                        _cellRight(_formatPrice(item.pricePerUnit), 8),
                        _cellRight(_formatPrice(item.totalWithVat), 8),
                        _cellRight('0.00', 8),
                      ],
                    );
                  }),
                  pw.TableRow(
                    children: [
                      _cell('Итого', 8, bold: true),
                      _cell('', 8),
                      _cell('', 8),
                      _cell('', 8),
                      _cellRight(
                        totalQty == totalQty.round()
                            ? totalQtyInt.toString()
                            : totalQty.toStringAsFixed(2),
                        8,
                        bold: true,
                      ),
                      _cellRight(
                        totalQty == totalQty.round()
                            ? totalQtyInt.toString()
                            : totalQty.toStringAsFixed(2),
                        8,
                        bold: true,
                      ),
                      _cellRight('x', 8, bold: true),
                      _cellRight(_formatPrice(totalSum), 8, bold: true),
                      _cellRight('0.00', 8, bold: true),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Всего отпущено количество запасов (прописью) $qtyWords  на сумму (прописью), в тенге $sumWords',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 14),
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(1),
                },
                border: pw.TableBorder(
                  left: const pw.BorderSide(width: 0.5),
                  right: const pw.BorderSide(width: 0.5),
                  verticalInside: const pw.BorderSide(width: 0.5),
                ),
                children: [
                  pw.TableRow(
                    verticalAlignment: pw.TableCellVerticalAlignment.top,
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Отпуск разрешил    ____________/  ${data.approvedBy ?? "______________________"}',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                            pw.SizedBox(height: 12),
                            pw.Text(
                              'Главный бухгалтер    ____________________/  ${data.chiefAccountant ?? "__________________________"}',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                            pw.SizedBox(height: 12),
                            pw.Text(
                              'Отпустил    ____________________/  ${data.releasedBy ?? "__________________________"}',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'По доверенности №${data.warrantNumber ?? "___________"} от «____»_______________20_____года',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              'выданной ${data.warrantIssuedBy ?? "                                                             "}',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                            pw.Container(height: 1, color: PdfColors.black),
                            pw.SizedBox(height: 8),
                            pw.Text(
                              'Запасы  получил ____________________/    ${data.receiverName}',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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

  static pw.Widget _borderedCell(String text, double fontSize) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: fontSize),
        maxLines: 4,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  static String _ttnString(String? number, String? date) {
    final parts = <String>[];
    if (number != null && number.isNotEmpty) parts.add(number);
    if (date != null && date.isNotEmpty) parts.add(date);
    return parts.isEmpty ? '________________________' : parts.join(', ');
  }
}
