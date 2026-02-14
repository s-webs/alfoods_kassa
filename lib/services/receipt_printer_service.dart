import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:windows_printer/windows_printer.dart';

import '../models/cart_item.dart';
import '../services/receipt_pdf_service.dart';
import 'pdf_printer_plugin.dart';

/// Печать товарного чека на термопринтер 80мм в формате Almaty Foods.
class ReceiptPrinterService {
  static const int _lineWidth = 48; // 80мм ~ 48 символов
  static const String _companyName = 'Almaty Foods';

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

  static String _formatSum(double v) {
    final s = v.toStringAsFixed(0);
    return s.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
  }

  /// Формирует ESC/POS байты чека для печати на 80мм.
  static List<int> buildReceipt({
    required int saleId,
    required String cashierName,
    required List<CartItem> items,
    required double total,
    required DateTime dateTime,
  }) {
    final generator = WPESCPOSGenerator(paperSize: WPPaperSize.mm80);

    generator.text(
      _center(_companyName, _lineWidth),
      style: const WPTextStyle(bold: true, align: WPTextAlign.center),
    );
    generator.text(
      'Кассир: $cashierName',
      style: const WPTextStyle(bold: true, align: WPTextAlign.left),
    );
    generator.text(
      'Товарный чек № $saleId',
      style: const WPTextStyle(bold: true, align: WPTextAlign.left),
    );
    generator.separator();

    // Заголовок таблицы
    const colNo = 3;
    const colName = 20;
    const colQty = 5;
    const colPrice = 8;
    const colSum = 8;
    generator.text(
      _padRight('№', colNo) +
          _padRight('Наименование', colName) +
          _padRight('К-во', colQty) +
          _padRight('Цена', colPrice) +
          _padRight('Сумма', colSum),
      style: const WPTextStyle(bold: true, align: WPTextAlign.left),
    );
    generator.separator();

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final no = '${i + 1}';
      final name = item.name.length > colName
          ? '${item.name.substring(0, colName - 1)}…'
          : item.name;
      final qty = item.unit == 'pcs'
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(2);
      final priceStr = _formatSum(item.price);
      final sumStr = _formatSum(item.total);
      generator.text(
        _padRight(no, colNo) +
            _padRight(name, colName) +
            _padRight(qty, colQty) +
            _padRight(priceStr, colPrice) +
            _padRight(sumStr, colSum),
        style: const WPTextStyle(bold: true, align: WPTextAlign.left),
      );
    }

    generator.separator();
    final totalStr = _formatSum(total);
    generator.text(
      'ИТОГО' + _padLeft(totalStr, _lineWidth - 5),
      style: const WPTextStyle(bold: true, align: WPTextAlign.left),
    );
    final dtStr =
        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
    generator.text(dtStr, style: const WPTextStyle(bold: true, align: WPTextAlign.left));
    generator.text(
      _center('Спасибо за покупку!', _lineWidth),
      style: const WPTextStyle(bold: true, align: WPTextAlign.center),
    );
    generator.cut();

    return generator.getBytes();
  }

  /// Печатает чек на выбранном принтере (Windows).
  /// [printMode] может быть:
  ///   - 'raw' (RAW печать на термопринтер)
  ///   - 'pdf' (обычная печать через системный диалог)
  ///   - 'pdf_direct' (прямая печать PDF без диалога)
  static Future<void> printReceipt({
    required String? printerName,
    required List<int> bytes,
    required String printMode,
    required int saleId,
    required String cashierName,
    required List<CartItem> items,
    required double total,
    required DateTime dateTime,
  }) async {
    if (printMode == 'pdf_direct') {
      // Прямая печать PDF без диалогового окна
      final pdfBytes = await ReceiptPdfService.buildReceiptPdf(
        saleId: saleId,
        cashierName: cashierName,
        items: items,
        total: total,
        dateTime: dateTime,
      );
      final success = await PdfPrinterPlugin.printPdf(
        pdfBytes: pdfBytes,
        printerName: printerName,
      );
      if (!success) {
        throw Exception('Не удалось отправить PDF на печать');
      }
    } else if (printMode == 'pdf') {
      // Печать через системный диалог печати PDF
      final pdfBytes = await ReceiptPdfService.buildReceiptPdf(
        saleId: saleId,
        cashierName: cashierName,
        items: items,
        total: total,
        dateTime: dateTime,
      );
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
      );
    } else {
      // RAW печать (по умолчанию)
      final printers = await WindowsPrinter.getAvailablePrinters();
      final name = printerName != null &&
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
