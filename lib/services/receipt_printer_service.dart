import 'dart:typed_data';

import 'package:printing/printing.dart';
import 'package:windows_printer/windows_printer.dart';

import '../models/cart_item.dart';
import '../models/webkassa_print_line.dart';
import '../utils/webkassa_receipt_layout.dart';
import '../services/receipt_pdf_service.dart';
import 'pdf_printer_plugin.dart';
import 'webkassa_receipt_pdf_service.dart';

/// Печать товарного чека на термопринтер 80мм в формате Almaty Foods.
///
/// Текст кодируется в CP866 или Windows-1251; кодовая страница — ESC t n.
/// Для Xprinter XP-*/китайских ESC/POS при «иероглифах» вместо кириллицы
/// включите в настройках преамбулу Xprinter (последовательность из документации):
/// иначе байты CP866 воспринимаются как GBK-пары.
class ReceiptPrinterService {
  static const int _lineWidth = 48; // 80мм ~ 48 символов
  static const String _companyName = 'Almaty Foods';

  /// Sumatra `-print-settings` для товарного чека в режиме pdf_direct.
  /// `fit` вписывает 80 мм PDF в печатную область драйвера (без обрезания справа).
  static const String _receiptPdfDirectPrintSettings = 'fit,monochrome';

  // ── ESC/POS константы ──────────────────────────────────────────────────────
  static const int _ESC = 0x1B;
  static const int _GS = 0x1D;
  static const int _FS = 0x1C;

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

  // ── Windows-1251 кодирование ────────────────────────────────────────────────

  /// Конвертирует один Unicode code point в байт Windows-1251.
  /// Неизвестные символы заменяются на '?' (0x3F).
  static int _charToCP1251(int cp) {
    // ASCII (0x00–0x7F) — без изменений
    if (cp < 0x80) return cp;

    // Кириллица заглавная А–Я  (U+0410–U+042F) → 0xC0–0xDF
    if (cp >= 0x0410 && cp <= 0x042F) return cp - 0x0410 + 0xC0;

    // Кириллица строчная а–я   (U+0430–U+044F) → 0xE0–0xFF
    if (cp >= 0x0430 && cp <= 0x044F) return cp - 0x0430 + 0xE0;

    // Ё (U+0401) → 0xA8,  ё (U+0451) → 0xB8
    if (cp == 0x0401) return 0xA8;
    if (cp == 0x0451) return 0xB8;

    // № (U+2116) → 0xB9
    if (cp == 0x2116) return 0xB9;

    // Всё остальное → '?'
    return 0x3F;
  }

  /// Кодирует строку Dart в байты Windows-1251.
  static List<int> _encodeCP1251(String text) {
    final out = <int>[];
    for (final cp in text.runes) {
      out.add(_charToCP1251(cp));
    }
    return out;
  }

  /// Кодирует строку в байты согласно выбранной кодировке принтера.
  /// [rawEncoding] — идентификатор из Storage.receiptRawEncoding.
  static List<int> _encodeText(String text, String rawEncoding) {
    if (rawEncoding.startsWith('cp1251')) return _encodeCP1251(text);
    return _encodeCP866(text);
  }

  // ── Низкоуровневые ESC/POS команды ─────────────────────────────────────────

  /// ESC @ — инициализация принтера
  static List<int> _cmdInit() => [_ESC, 0x40];

  /// FS . — отмена режима китайских (Kanji/GBK) двухбайтовых символов.
  ///
  /// Без этой команды многие китайские термопринтеры (Xprinter XP-58/XP-80,
  /// HPRT, Rongta, ZJ и клоны) по умолчанию интерпретируют байты ≥ 0x80 как
  /// первый байт пары CJK, из-за чего CP866/CP1251 кириллица печатается
  /// иероглифами. ESC @ (init) у этих прошивок Kanji-режим НЕ сбрасывает.
  /// Команда безопасна для всех ESC/POS принтеров — если Kanji не
  /// поддерживается, она просто игнорируется.
  static List<int> _cmdCancelKanjiMode() => [_FS, 0x2E];

  /// Преамбула из инструкций Xprinter (xprinter-dv.ru и аналоги): перед выбором
  /// кодовой страницы переводит прошивку из режима двухбайтового текста.
  static List<int> _cmdXprinterCyrillicPreamble() => [
    0x1F,
    0x1B,
    0x1F,
    0xFE,
    0x01,
    0x1F,
    0x1B,
    0x1F,
    0xFE,
    0x11,
  ];

  /// ESC t n — выбор кодовой страницы по номеру
  static List<int> _cmdCodePage(int n) => [_ESC, 0x74, n];

  /// ESC a n — выравнивание: 0=левое, 1=центр, 2=правое
  static List<int> _cmdAlign(int n) => [_ESC, 0x61, n & 0x03];

  /// ESC E n — жирный шрифт: 1=вкл, 0=выкл
  static List<int> _cmdBold(bool on) => [_ESC, 0x45, on ? 1 : 0];

  /// GS V 0 — полная отрезка бумаги
  static List<int> _cmdCut() => [_GS, 0x56, 0x00];

  /// GS ( k — печать QR-кода (модель 2).
  static void _appendQrCode(
    List<int> buf,
    String data, {
    String rawEncoding = 'cp866_17',
  }) {
    final encoded = _encodeText(data, rawEncoding);
    final storeLen = encoded.length + 3;
    final pL = storeLen & 0xFF;
    final pH = (storeLen >> 8) & 0xFF;

    buf.addAll(_cmdAlign(1));
    buf.addAll([
      _GS, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00,
      _GS, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x06,
      _GS, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31,
      _GS, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30,
      ...encoded,
      _GS, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30,
      0x0A,
    ]);
  }

  // ── Строки чека ─────────────────────────────────────────────────────────────

  /// Добавляет строку текста с выравниванием и жирностью, заканчивает LF.
  static void _addLine(
    List<int> buf,
    String text, {
    bool bold = false,
    int align = 0, // 0=left, 1=center, 2=right
    String rawEncoding = 'cp866_17',
  }) {
    buf.addAll(_cmdAlign(align));
    buf.addAll(_cmdBold(bold));
    buf.addAll(_encodeText(text, rawEncoding));
    buf.add(0x0A); // LF
  }

  /// Добавляет разделительную линию.
  static void _addSeparator(List<int> buf) {
    _addLine(buf, '-' * _lineWidth);
  }

  // ── Публичный API ────────────────────────────────────────────────────────────

  /// Извлекает номер кодовой страницы ESC/POS из идентификатора кодировки.
  /// Формат идентификатора: '<enc>_<n>', например 'cp866_17', 'cp1251_22'.
  static int _codePageNumber(String rawEncoding) {
    final parts = rawEncoding.split('_');
    if (parts.length >= 2) {
      return int.tryParse(parts.last) ?? 17;
    }
    return 17;
  }

  /// Формирует ESC/POS байты чека для печати на 80мм термопринтере.
  /// [rawEncoding] задаёт пару (кодировка текста + номер кодовой страницы ESC/POS),
  /// например 'cp866_17' (стандарт) или 'cp1251_22' (для принтеров, не реагирующих на CP866).
  static List<int> buildReceipt({
    required int saleId,
    required String cashierName,
    required List<CartItem> items,
    required double total,
    required double totalQty,
    required DateTime dateTime,
    String rawEncoding = 'cp866_17',
    bool xprinterCyrillicPreamble = false,
  }) {
    final buf = <int>[];

    // Инициализация + отмена Kanji-режима + (опц.) Xprinter-преамбула + кодовая страница.
    // Порядок важен: FS . должен идти после ESC @ и ДО ESC t n, иначе прошивка
    // успеет интерпретировать первый же байт ≥ 0x80 как начало CJK-пары.
    buf.addAll(_cmdInit());
    buf.addAll(_cmdCancelKanjiMode());
    if (xprinterCyrillicPreamble) {
      buf.addAll(_cmdXprinterCyrillicPreamble());
    }
    buf.addAll(_cmdCodePage(_codePageNumber(rawEncoding)));

    // Шапка
    _addLine(buf, _center(_companyName, _lineWidth), bold: true, align: 1, rawEncoding: rawEncoding);
    _addLine(buf, 'Кассир: $cashierName', bold: true, rawEncoding: rawEncoding);
    _addLine(buf, 'Товарный чек № $saleId', bold: true, rawEncoding: rawEncoding);
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
      rawEncoding: rawEncoding,
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
            rawEncoding: rawEncoding,
          );
        } else {
          _addLine(
            buf,
            _padRight('', colNo) +
                namePart +
                _padRight('', colQty) +
                _padRight('', colPrice) +
                _padRight('', colSum),
            rawEncoding: rawEncoding,
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
      rawEncoding: rawEncoding,
    );

    // Итоговая сумма
    final totalStr = _formatSum(total);
    _addLine(buf, 'ИТОГО' + _padLeft(totalStr, _lineWidth - 5), bold: true, rawEncoding: rawEncoding);

    // Дата и время
    final dtStr =
        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
    _addLine(buf, dtStr, bold: true, rawEncoding: rawEncoding);

    // Подпись
    _addLine(buf, _center('Спасибо за покупку!', _lineWidth), bold: true, align: 1, rawEncoding: rawEncoding);

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
        printSettings: _receiptPdfDirectPrintSettings,
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

  // ── Тестовая печать ─────────────────────────────────────────────────────────

  /// Формирует короткий тестовый ESC/POS-чек для проверки кодировки и
  /// настроек принтера. Печатает кириллицу разного регистра, цифры, знак №
  /// и краткую сводку по применённым настройкам.
  static List<int> buildTestReceipt({
    String rawEncoding = 'cp866_17',
    bool xprinterCyrillicPreamble = false,
  }) {
    final buf = <int>[];

    buf.addAll(_cmdInit());
    buf.addAll(_cmdCancelKanjiMode());
    if (xprinterCyrillicPreamble) {
      buf.addAll(_cmdXprinterCyrillicPreamble());
    }
    buf.addAll(_cmdCodePage(_codePageNumber(rawEncoding)));

    _addLine(
      buf,
      _center('ТЕСТ ПЕЧАТИ', _lineWidth),
      bold: true,
      align: 1,
      rawEncoding: rawEncoding,
    );
    _addSeparator(buf);
    _addLine(
      buf,
      'Кириллица: АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ',
      rawEncoding: rawEncoding,
    );
    _addLine(
      buf,
      'строчная:  абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
      rawEncoding: rawEncoding,
    );
    _addLine(buf, 'Цифры: 0123456789  №  —', rawEncoding: rawEncoding);
    _addLine(buf, 'ASCII: The quick brown fox 1234567890', rawEncoding: rawEncoding);
    _addSeparator(buf);

    // Сводка настроек
    final codePage = _codePageNumber(rawEncoding);
    final encName = rawEncoding.startsWith('cp1251') ? 'Windows-1251' : 'CP866';
    _addLine(buf, 'Кодировка: $encName', rawEncoding: rawEncoding);
    _addLine(buf, 'Код. страница (ESC t): $codePage', rawEncoding: rawEncoding);
    _addLine(
      buf,
      'Xprinter-преамбула: ${xprinterCyrillicPreamble ? "вкл" : "выкл"}',
      rawEncoding: rawEncoding,
    );
    _addLine(buf, 'FS . (отмена Kanji): вкл', rawEncoding: rawEncoding);

    _addSeparator(buf);
    _addLine(
      buf,
      _center('Если видите кириллицу — OK', _lineWidth),
      bold: true,
      align: 1,
      rawEncoding: rawEncoding,
    );

    buf.add(0x0A);
    buf.add(0x0A);
    buf.add(0x0A);
    buf.addAll(_cmdCut());
    return buf;
  }

  /// Формирует ESC/POS байты фискального чека WebKassa из [print_lines] API.
  static List<int> buildWebkassaReceipt({
    required List<WebkassaPrintLine> lines,
    String rawEncoding = 'cp866_17',
    bool xprinterCyrillicPreamble = false,
  }) {
    final sorted = List<WebkassaPrintLine>.from(lines)
      ..sort((a, b) => a.order.compareTo(b.order));
    final leftFlags = WebkassaReceiptLayout.leftAlignFlags(sorted);

    final buf = <int>[];
    buf.addAll(_cmdInit());
    buf.addAll(_cmdCancelKanjiMode());
    if (xprinterCyrillicPreamble) {
      buf.addAll(_cmdXprinterCyrillicPreamble());
    }
    buf.addAll(_cmdCodePage(_codePageNumber(rawEncoding)));

    for (var i = 0; i < sorted.length; i++) {
      final line = sorted[i];
      final alignLeft = WebkassaReceiptLayout.isLeftAligned(i, leftFlags);

      switch (line.type) {
        case 2:
          if (line.value.isNotEmpty) {
            _appendQrCode(buf, line.value, rawEncoding: rawEncoding);
          }
          break;
        case 1:
          // Изображения (логотип) пока пропускаем — текстовые строки и QR покрывают чек.
          break;
        default:
          _addLine(
            buf,
            line.value,
            bold: line.style == 1,
            align: alignLeft ? 0 : 1,
            rawEncoding: rawEncoding,
          );
      }
    }

    buf.add(0x0A);
    buf.add(0x0A);
    buf.addAll(_cmdCut());
    return buf;
  }

  /// Есть ли в [lines] хотя бы одна печатаемая строка (текст, QR или картинка).
  static bool hasPrintableWebkassaLines(List<WebkassaPrintLine> lines) {
    for (final line in lines) {
      if (line.value.trim().isEmpty) continue;
      if (line.type == 0 || line.type == 1 || line.type == 2) {
        return true;
      }
    }
    return false;
  }

  static Future<String> _resolveWindowsPrinter(String? printerName) async {
    final printers = await WindowsPrinter.getAvailablePrinters();
    if (printerName != null && printerName.isNotEmpty) {
      if (!printers.contains(printerName)) {
        throw Exception(
          'Принтер «$printerName» не найден. Выберите принтер в настройках.',
        );
      }
      return printerName;
    }
    if (printers.isEmpty) {
      throw Exception('Нет доступных принтеров');
    }
    return printers.first;
  }

  /// Печатает фискальный чек WebKassa (тот же режим, что и товарный чек в настройках).
  static Future<void> printWebkassaReceipt({
    required List<WebkassaPrintLine> lines,
    required String? printerName,
    required String printMode,
    String rawEncoding = 'cp866_17',
    bool xprinterCyrillicPreamble = false,
  }) async {
    if (lines.isEmpty) {
      throw Exception('Нет данных чека WebKassa для печати');
    }
    if (!hasPrintableWebkassaLines(lines)) {
      throw Exception('Чек WebKassa не содержит текста для печати');
    }

    final name = await _resolveWindowsPrinter(printerName);

    if (printMode == 'pdf_direct' || printMode == 'pdf') {
      final pdfBytes = await WebkassaReceiptPdfService.buildPdf(lines);
      if (printMode == 'pdf') {
        await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
        return;
      }
      final success = await PdfPrinterPlugin.printPdf(
        pdfBytes: pdfBytes,
        printerName: name,
        printSettings: 'noscale,monochrome',
      );
      if (!success) {
        throw Exception('Не удалось отправить фискальный чек на печать (PDF)');
      }
      return;
    }

    final bytes = buildWebkassaReceipt(
      lines: lines,
      rawEncoding: rawEncoding,
      xprinterCyrillicPreamble: xprinterCyrillicPreamble,
    );

    await WindowsPrinter.printRawData(
      printerName: name,
      data: Uint8List.fromList(bytes),
      useRawDatatype: true,
    );
  }

  /// Отправляет тестовый чек RAW-печатью на указанный принтер.
  /// Если [printerName] пуст или не найден — берёт первый доступный.
  static Future<void> printTest({
    required String? printerName,
    String rawEncoding = 'cp866_17',
    bool xprinterCyrillicPreamble = false,
  }) async {
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
    final bytes = buildTestReceipt(
      rawEncoding: rawEncoding,
      xprinterCyrillicPreamble: xprinterCyrillicPreamble,
    );
    await WindowsPrinter.printRawData(
      printerName: name,
      data: Uint8List.fromList(bytes),
      useRawDatatype: true,
    );
  }
}
