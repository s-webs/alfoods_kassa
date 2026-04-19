import 'dart:typed_data';

import 'package:printing/printing.dart';
import 'package:windows_printer/windows_printer.dart';

import '../models/cart_item.dart';
import '../services/receipt_pdf_service.dart';
import 'pdf_printer_plugin.dart';

/// Печать товарного чека на термопринтер 80мм в формате Almaty Foods.
///
/// Текст кодируется в CP866 (DOS Cyrillic), кодовая страница устанавливается
/// командой ESC t 17 в начале документа — это обеспечивает корректное
/// отображение кириллицы при RAW-печати без сторонних утилит.
class ReceiptPrinterService {
  static const int _lineWidth = 48; // 80мм ~ 48 символов
  static const String _companyName = 'Almaty Foods';

  // ── ESC/POS константы ──────────────────────────────────────────────────────
  static const int _ESC = 0x1B;
  static const int _GS = 0x1D;

  // ── Вспомогательные строковые методы ───────────────────────────────────────

  static String _padRight(String s, int width) {
    if (s.length >= width) return s.substring(0, width);
    return s.padRight(width);
  }

  static String _padLeft(String s, int width) {
    if (s.length >= width) return s.substring(0, width);
    return s.padLeft(width);
  }

  static String _center(String s, int width) {
    if (s.length >= width) return s.substring(0, width);
    final pad = width - s.length;
    final left = pad ~/ 2;
    return ' ' * left + s + ' ' * (pad - left);
  }

  static List<String> _wrapText(String text, int maxWidth) {
    if (text.isEmpty) return [''];
    if (text.length <= maxWidth) return [text];
    final lines = <String>[];
    var remaining = text;
    while (remaining.isNotEmpty) {
      if (remaining.length <= maxWidth) {
        lines.add(remaining);
        break;
      }
      var splitAt = maxWidth;
      final chunk = remaining.substring(0, maxWidth);
      final lastSpace = chunk.lastIndexOf(' ');
      if (lastSpace > maxWidth ~/ 2) {
        splitAt = lastSpace + 1;
      }
      lines.add(remaining.substring(0, splitAt).trim());
      remaining = remaining.substring(splitAt).trimLeft();
    }
    return lines;
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

  // ── CP866 кодирование ───────────────────────────────────────────────────────

  /// Конвертирует один Unicode code point в байт CP866.
  /// Неизвестные символы заменяются на '?' (0x3F).
  static int _charToCP866(int cp) {
    // ASCII (0x00–0x7F) — без изменений
    if (cp < 0x80) return cp;

    // Кириллица заглавная А–П  (U+0410–U+041F) → 0x80–0x8F
    if (cp >= 0x0410 && cp <= 0x041F) return cp - 0x0410 + 0x80;

    // Кириллица заглавная Р–Я  (U+0420–U+042F) → 0x90–0x9F
    if (cp >= 0x0420 && cp <= 0x042F) return cp - 0x0420 + 0x90;

    // Кириллица строчная а–п   (U+0430–U+043F) → 0xA0–0xAF
    if (cp >= 0x0430 && cp <= 0x043F) return cp - 0x0430 + 0xA0;

    // Кириллица строчная р–я   (U+0440–U+044F) → 0xE0–0xEF
    if (cp >= 0x0440 && cp <= 0x044F) return cp - 0x0440 + 0xE0;

    // Ё (U+0401) → 0xF0,  ё (U+0451) → 0xF1
    if (cp == 0x0401) return 0xF0;
    if (cp == 0x0451) return 0xF1;

    // № (U+2116) → 0xFC
    if (cp == 0x2116) return 0xFC;

    // Всё остальное → '?'
    return 0x3F;
  }

  /// Кодирует строку Dart в байты CP866.
  static List<int> _encodeCP866(String text) {
    final out = <int>[];
    for (final cp in text.runes) {
      out.add(_charToCP866(cp));
    }
    return out;
  }

  // ── Низкоуровневые ESC/POS команды ─────────────────────────────────────────

  /// ESC @ — инициализация принтера
  static List<int> _cmdInit() => [_ESC, 0x40];

  /// ESC t 17 — выбор кодовой страницы PC866 (DOS Cyrillic)
  static List<int> _cmdCodePageCP866() => [_ESC, 0x74, 17];

  /// ESC a n — выравнивание: 0=левое, 1=центр, 2=правое
  static List<int> _cmdAlign(int n) => [_ESC, 0x61, n & 0x03];

  /// ESC E n — жирный шрифт: 1=вкл, 0=выкл
  static List<int> _cmdBold(bool on) => [_ESC, 0x45, on ? 1 : 0];

  /// GS V 0 — полная отрезка бумаги
  static List<int> _cmdCut() => [_GS, 0x56, 0x00];

  // ── Строки чека ─────────────────────────────────────────────────────────────

  /// Добавляет строку текста с выравниванием и жирностью, заканчивает LF.
  static void _addLine(
    List<int> buf,
    String text, {
    bool bold = false,
    int align = 0, // 0=left, 1=center, 2=right
  }) {
    buf.addAll(_cmdAlign(align));
    buf.addAll(_cmdBold(bold));
    buf.addAll(_encodeCP866(text));
    buf.add(0x0A); // LF
  }

  /// Добавляет разделительную линию.
  static void _addSeparator(List<int> buf) {
    _addLine(buf, '-' * _lineWidth);
  }

  // ── Публичный API ────────────────────────────────────────────────────────────

  /// Формирует ESC/POS байты чека для печати на 80мм термопринтере.
  /// Кириллица кодируется в CP866, кодовая страница задаётся ESC t 17.
  static List<int> buildReceipt({
    required int saleId,
    required String cashierName,
    required List<CartItem> items,
    required double total,
    required double totalQty,
    required DateTime dateTime,
  }) {
    final buf = <int>[];

    // Инициализация + кодовая страница CP866
    buf.addAll(_cmdInit());
    buf.addAll(_cmdCodePageCP866());

    // Шапка
    _addLine(buf, _center(_companyName, _lineWidth), bold: true, align: 1);
    _addLine(buf, 'Кассир: $cashierName', bold: true);
    _addLine(buf, 'Товарный чек № $saleId', bold: true);
    _addSeparator(buf);

    // Заголовок таблицы
    const colNo = 3;
    const colName = 20;
    const colQty = 5;
    const colPrice = 8;
    const colSum = 8;

    _addLine(
      buf,
      _padRight('№', colNo) +
          _padRight('Наименование', colName) +
          _padRight('К-во', colQty) +
          _padRight('Цена', colPrice) +
          _padRight('Сумма', colSum),
      bold: true,
    );
    _addSeparator(buf);

    // Строки товаров
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final no = '${i + 1}';
      final nameLines = _wrapText(item.name, colName);
      final qty = item.unit == 'pcs'
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(2);
      final priceStr = _formatSum(item.price);
      final sumStr = _formatSum(item.total);

      for (var li = 0; li < nameLines.length; li++) {
        final namePart = _padRight(nameLines[li], colName);
        if (li == 0) {
          _addLine(
            buf,
            _padRight(no, colNo) +
                namePart +
                _padRight(qty, colQty) +
                _padRight(priceStr, colPrice) +
                _padRight(sumStr, colSum),
            bold: true,
          );
        } else {
          _addLine(
            buf,
            _padRight('', colNo) +
                namePart +
                _padRight('', colQty) +
                _padRight('', colPrice) +
                _padRight('', colSum),
          );
        }
      }
    }

    _addSeparator(buf);

    // Итого по количеству
    final totalQtyStr = _formatQty(totalQty);
    _addLine(
      buf,
      _padRight('', colNo) +
          _padRight('ОБЩЕЕ КОЛИЧЕСТВО', colName) +
          _padRight(totalQtyStr, colQty) +
          _padRight('', colPrice) +
          _padRight('', colSum),
      bold: true,
    );

    // Итоговая сумма
    final totalStr = _formatSum(total);
    _addLine(buf, 'ИТОГО' + _padLeft(totalStr, _lineWidth - 5), bold: true);

    // Дата и время
    final dtStr =
        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
    _addLine(buf, dtStr, bold: true);

    // Подпись
    _addLine(buf, _center('Спасибо за покупку!', _lineWidth), bold: true, align: 1);

    // Подача и отрезка
    buf.add(0x0A);
    buf.add(0x0A);
    buf.add(0x0A);
    buf.addAll(_cmdCut());

    return buf;
  }

  /// Печатает чек на выбранном принтере (Windows).
  /// [printMode]:
  ///   - 'raw'        — RAW-печать ESC/POS на термопринтер
  ///   - 'pdf'        — печать через системный диалог
  ///   - 'pdf_direct' — прямая печать PDF без диалога
  static Future<void> printReceipt({
    required String? printerName,
    required List<int> bytes,
    required String printMode,
    required int saleId,
    required String cashierName,
    required List<CartItem> items,
    required double total,
    required double totalQty,
    required DateTime dateTime,
  }) async {
    if (printMode == 'pdf_direct') {
      final pdfBytes = await ReceiptPdfService.buildReceiptPdf(
        saleId: saleId,
        cashierName: cashierName,
        items: items,
        total: total,
        totalQty: totalQty,
        dateTime: dateTime,
      );
      final success = await PdfPrinterPlugin.printPdf(
        pdfBytes: pdfBytes,
        printerName: printerName,
        printSettings: 'noscale,monochrome',
      );
      if (!success) {
        throw Exception('Не удалось отправить PDF на печать');
      }
    } else if (printMode == 'pdf') {
      final pdfBytes = await ReceiptPdfService.buildReceiptPdf(
        saleId: saleId,
        cashierName: cashierName,
        items: items,
        total: total,
        totalQty: totalQty,
        dateTime: dateTime,
      );
      await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
    } else {
      // RAW-печать (по умолчанию)
      final printers = await WindowsPrinter.getAvailablePrinters();
      final name =
          printerName != null &&
              printerName.isNotEmpty &&
              printers.contains(printerName)
          ? printerName
          : (printers.isNotEmpty ? printers.first : null);
      if (name == null) {
        throw Exception('Нет доступных принтеров');
      }
      await WindowsPrinter.printRawData(
        printerName: name,
        data: Uint8List.fromList(bytes),
        useRawDatatype: true,
      );
    }
  }

  /// Возвращает список имён принтеров (Windows).
  static Future<List<String>> getAvailablePrinters() async {
    return WindowsPrinter.getAvailablePrinters();
  }
}
