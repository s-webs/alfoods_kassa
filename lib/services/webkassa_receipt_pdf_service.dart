import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:barcode_image/barcode_image.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/webkassa_print_line.dart';
import '../utils/webkassa_receipt_layout.dart';

/// PDF фискального чека WebKassa (80 мм) для режима pdf_direct.
class WebkassaReceiptPdfService {
  static Future<Uint8List> buildPdf(List<WebkassaPrintLine> lines) async {
    final sorted = List<WebkassaPrintLine>.from(lines)
      ..sort((a, b) => a.order.compareTo(b.order));

    final theme = await _loadCyrillicTheme();
    final pdf = pw.Document(theme: theme);
    final widgets = <pw.Widget>[];
    final leftFlags = WebkassaReceiptLayout.leftAlignFlags(sorted);

    for (var i = 0; i < sorted.length; i++) {
      final line = sorted[i];
      final alignLeft = WebkassaReceiptLayout.isLeftAligned(i, leftFlags);

      switch (line.type) {
        case 2:
          if (line.value.isNotEmpty) {
            final qr = await _qrImage(line.value);
            if (qr != null) {
              widgets.add(
                _wrapAligned(
                  alignLeft: false,
                  child: pw.Image(qr, width: 120, height: 120),
                ),
              );
              widgets.add(pw.SizedBox(height: 6));
            }
          }
          break;
        case 1:
          final decoded = await _decodeBase64Image(line.value);
          if (decoded != null) {
            widgets.add(
              _wrapAligned(
                alignLeft: alignLeft,
                child: pw.Image(decoded, width: 160),
              ),
            );
            widgets.add(pw.SizedBox(height: 6));
          }
          break;
        default:
          final text = line.value;
          if (text.trim().isEmpty) break;
          widgets.add(
            _wrapAligned(
              alignLeft: alignLeft,
              child: pw.Text(
                text,
                textAlign:
                    alignLeft ? pw.TextAlign.left : pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: line.style == 1
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ),
          );
      }
    }

    if (widgets.isEmpty) {
      throw Exception('Нет данных для PDF чека WebKassa');
    }

    final heightMm = _estimateHeightMm(sorted);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          PdfPageFormat.roll80.width,
          heightMm * PdfPageFormat.mm,
        ),
        margin: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: widgets,
        ),
      ),
    );

    return pdf.save();
  }

  static double _estimateHeightMm(List<WebkassaPrintLine> lines) {
    var mm = 16.0;
    for (final line in lines) {
      if (line.value.trim().isEmpty) continue;
      switch (line.type) {
        case 2:
          mm += 34.0;
          break;
        case 1:
          mm += 28.0;
          break;
        default:
          final len = line.value.length;
          final wrapped = len == 0 ? 1 : math.min(20, (len / 32).ceil());
          mm += wrapped * 3.6;
      }
    }
    return mm.clamp(60.0, 2000.0);
  }

  static Future<pw.MemoryImage?> _qrImage(String data) async {
    try {
      final bc = Barcode.qrCode();
      const size = 200;
      final image = img.Image(width: size, height: size);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      drawBarcode(image, bc, data, width: size, height: size);
      return pw.MemoryImage(Uint8List.fromList(img.encodePng(image)));
    } catch (_) {
      return null;
    }
  }

  static Future<pw.MemoryImage?> _decodeBase64Image(String value) async {
    try {
      var payload = value.trim();
      final comma = payload.indexOf(',');
      if (comma >= 0 && payload.toLowerCase().startsWith('data:')) {
        payload = payload.substring(comma + 1);
      }
      final bytes = base64Decode(payload);
      if (bytes.isEmpty) return null;
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  static pw.Widget _wrapAligned({
    required bool alignLeft,
    required pw.Widget child,
  }) {
    if (alignLeft) {
      return pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: child,
      );
    }
    return pw.Center(child: child);
  }

  static Future<pw.ThemeData?> _loadCyrillicTheme() async {
    if (!Platform.isWindows) return null;
    try {
      final file = File(r'C:\Windows\Fonts\arial.ttf');
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
}
