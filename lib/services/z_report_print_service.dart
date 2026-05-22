import 'dart:io';

import 'package:flutter/material.dart';

import '../core/storage.dart';
import '../models/webkassa_print_line.dart';
import '../utils/toast.dart';
import 'receipt_printer_service.dart';
import 'z_report_formatter.dart';

/// Печать Z-отчёта на принтер из настроек кассы.
class ZReportPrintService {
  ZReportPrintService(this._storage);

  final Storage _storage;

  Future<void> print(
    BuildContext context, {
    required Map<String, dynamic> zReport,
    DateTime? zReportAt,
  }) async {
    if (!Platform.isWindows) {
      showToast(context, 'Печать Z-отчёта доступна на Windows');
      return;
    }

    final textLines = ZReportFormatter.formatLines(zReport, zReportAt: zReportAt);
    if (textLines.length <= 1) {
      showToast(context, 'Нет данных Z-отчёта для печати');
      return;
    }

    final printLines = <WebkassaPrintLine>[];
    for (var i = 0; i < textLines.length; i++) {
      final line = textLines[i];
      final isSeparator = line.startsWith('---');
      printLines.add(
        WebkassaPrintLine(
          order: i + 1,
          type: 0,
          value: line,
          style: (i == 0 || isSeparator) ? 1 : 0,
        ),
      );
    }

    try {
      await ReceiptPrinterService.printWebkassaReceipt(
        lines: printLines,
        printerName: _storage.receiptPrinterName,
        printMode: _storage.receiptPrintMode,
        rawEncoding: _storage.receiptRawEncoding,
        xprinterCyrillicPreamble: _storage.receiptRawXprinterPreamble,
      );
      if (context.mounted) {
        final printer = _storage.receiptPrinterName?.trim();
        showToast(
          context,
          printer != null && printer.isNotEmpty
              ? 'Z-отчёт отправлен на «$printer»'
              : 'Z-отчёт отправлен на печать',
        );
      }
    } catch (e) {
      if (context.mounted) {
        showToast(
          context,
          'Печать Z-отчёта: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }
  }
}
