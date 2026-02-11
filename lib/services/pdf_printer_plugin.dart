import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Прямая печать PDF на Windows без диалогового окна через SumatraPDF.
///
/// SumatraPDF-3.5.2-64.exe лежит в `assets/` и при первом вызове
/// извлекается во временную директорию, откуда и запускается.
class PdfPrinterPlugin {
  static const String _sumatraAssetPath = 'assets/SumatraPDF-3.5.2-64.exe';
  static String? _cachedExePath;

  /// Печатает PDF напрямую на указанный принтер без диалогового окна.
  ///
  /// [pdfBytes] - байты PDF файла.
  /// [printerName] - имя принтера (null = принтер по умолчанию).
  ///
  /// Возвращает true если команда на печать успешно отправлена.
  static Future<bool> printPdf({
    required Uint8List pdfBytes,
    String? printerName,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Прямая печать PDF через Sumatra доступна только на Windows');
    }

    final exePath = await _ensureSumatraExtracted();

    // Временный PDF-файл для печати
    final tempDir = Directory.systemTemp;
    final pdfFile = File(
      '${tempDir.path}${Platform.pathSeparator}alfoods_receipt_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await pdfFile.writeAsBytes(pdfBytes, flush: true);

    final args = <String>[
      '-silent',
      '-exit-on-print',
      if (printerName != null && printerName.isNotEmpty) ...[
        '-print-to',
        printerName,
      ] else
        '-print-to-default',
      pdfFile.path,
    ];

    try {
      // Запускаем Sumatra в отдельном процессе без ожидания.
      await Process.start(
        exePath,
        args,
        mode: ProcessStartMode.detached,
      );

      // Отложенно удаляем временный PDF (после того как Sumatra успеет его прочитать).
      Future<void>.delayed(const Duration(seconds: 15), () {
        if (pdfFile.existsSync()) {
          pdfFile.deleteSync();
        }
      });

      return true;
    } catch (e) {
      // При ошибке сразу пытаемся удалить временный файл.
      if (pdfFile.existsSync()) {
        pdfFile.deleteSync();
      }
      throw Exception('Ошибка печати PDF через Sumatra: $e');
    }
  }

  /// Извлекает SumatraPDF.exe из assets во временную директорию (один раз)
  /// и возвращает путь к исполняемому файлу.
  static Future<String> _ensureSumatraExtracted() async {
    if (_cachedExePath != null && File(_cachedExePath!).existsSync()) {
      return _cachedExePath!;
    }

    final data = await rootBundle.load(_sumatraAssetPath);
    final bytes = data.buffer.asUint8List();

    final baseDir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}alfoods_sumatra',
    );
    if (!baseDir.existsSync()) {
      baseDir.createSync(recursive: true);
    }

    final exeFile = File(
      '${baseDir.path}${Platform.pathSeparator}SumatraPDF.exe',
    );
    if (!exeFile.existsSync()) {
      exeFile.writeAsBytesSync(bytes, flush: true);
    }

    _cachedExePath = exeFile.path;
    return _cachedExePath!;
  }
}
