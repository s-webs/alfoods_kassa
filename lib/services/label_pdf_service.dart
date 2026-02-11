import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/product.dart';
import '../utils/barcode_image_helper.dart';

/// Тип блока на этикетке/ценнике.
enum LabelBlockType {
  name,
  barcode,
  price,
}

extension LabelBlockTypeX on LabelBlockType {
  String get title {
    switch (this) {
      case LabelBlockType.name:
        return 'Название';
      case LabelBlockType.barcode:
        return 'Штрихкод';
      case LabelBlockType.price:
        return 'Цена';
    }
  }
}

/// Расположение одного блока на холсте (x, y — доли 0..1 от размера стикера).
class LabelBlockLayout {
  const LabelBlockLayout({
    required this.type,
    required this.x,
    required this.y,
  });
  final LabelBlockType type;
  final double x;
  final double y;

  LabelBlockLayout copyWith({double? x, double? y}) =>
      LabelBlockLayout(type: type, x: x ?? this.x, y: y ?? this.y);

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'x': x,
        'y': y,
      };

  static LabelBlockLayout fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String?;
    LabelBlockType t;
    switch (typeStr) {
      case 'name':
        t = LabelBlockType.name;
        break;
      case 'barcode':
        t = LabelBlockType.barcode;
        break;
      case 'price':
        t = LabelBlockType.price;
        break;
      default:
        t = LabelBlockType.name;
    }
    return LabelBlockLayout(
      type: t,
      x: (json['x'] as num?)?.toDouble() ?? 0.05,
      y: (json['y'] as num?)?.toDouble() ?? 0.05,
    );
  }

  static List<LabelBlockLayout> get defaultLayout => [
        const LabelBlockLayout(type: LabelBlockType.name, x: 0.05, y: 0.05),
        const LabelBlockLayout(type: LabelBlockType.barcode, x: 0.05, y: 0.35),
        const LabelBlockLayout(type: LabelBlockType.price, x: 0.05, y: 0.78),
      ];
}

/// Настройки оформления этикетки: размеры шрифтов и штрихкода.
class LabelStyle {
  const LabelStyle({
    this.nameFontSize = 8,
    this.priceFontSize = 10,
    this.barcodeWidthFactor = 0.95,
    this.barcodeHeightFactor = 0.35,
  });

  /// Размер шрифта названия (pt).
  final double nameFontSize;

  /// Размер шрифта цены (pt).
  final double priceFontSize;

  /// Ширина штрихкода — доля от ширины стикера (0..1).
  final double barcodeWidthFactor;

  /// Высота штрихкода — доля от высоты стикера (0..1).
  final double barcodeHeightFactor;

  LabelStyle copyWith({
    double? nameFontSize,
    double? priceFontSize,
    double? barcodeWidthFactor,
    double? barcodeHeightFactor,
  }) =>
      LabelStyle(
        nameFontSize: nameFontSize ?? this.nameFontSize,
        priceFontSize: priceFontSize ?? this.priceFontSize,
        barcodeWidthFactor: barcodeWidthFactor ?? this.barcodeWidthFactor,
        barcodeHeightFactor: barcodeHeightFactor ?? this.barcodeHeightFactor,
      );

  static const double minFontSize = 4;
  static const double maxFontSize = 36;
  static const double minBarcodeFactor = 0.15;
  static const double maxBarcodeFactor = 1.0;

  Map<String, dynamic> toJson() => {
        'nameFontSize': nameFontSize,
        'priceFontSize': priceFontSize,
        'barcodeWidthFactor': barcodeWidthFactor,
        'barcodeHeightFactor': barcodeHeightFactor,
      };

  static LabelStyle fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LabelStyle();
    return LabelStyle(
      nameFontSize: (json['nameFontSize'] as num?)?.toDouble() ?? 8,
      priceFontSize: (json['priceFontSize'] as num?)?.toDouble() ?? 10,
      barcodeWidthFactor:
          (json['barcodeWidthFactor'] as num?)?.toDouble() ?? 0.95,
      barcodeHeightFactor:
          (json['barcodeHeightFactor'] as num?)?.toDouble() ?? 0.35,
    );
  }
}

/// Макет этикетки/ценника: блоки, стиль, размеры.
class LabelTemplate {
  const LabelTemplate({
    required this.blockLayout,
    required this.style,
    required this.widthMm,
    required this.heightMm,
  });

  final List<LabelBlockLayout> blockLayout;
  final LabelStyle style;
  final double widthMm;
  final double heightMm;

  Map<String, dynamic> toJson() => {
        'blockLayout': blockLayout.map((e) => e.toJson()).toList(),
        'style': style.toJson(),
        'widthMm': widthMm,
        'heightMm': heightMm,
      };

  static LabelTemplate fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return LabelTemplate(
        blockLayout: LabelBlockLayout.defaultLayout,
        style: const LabelStyle(),
        widthMm: 40,
        heightMm: 30,
      );
    }
    final layoutList = json['blockLayout'] as List<dynamic>?;
    final blockLayout = layoutList != null
        ? layoutList
            .map((e) => LabelBlockLayout.fromJson(e as Map<String, dynamic>))
            .toList()
        : LabelBlockLayout.defaultLayout;
    return LabelTemplate(
      blockLayout: blockLayout,
      style: LabelStyle.fromJson(json['style'] as Map<String, dynamic>?),
      widthMm: (json['widthMm'] as num?)?.toDouble() ?? 40,
      heightMm: (json['heightMm'] as num?)?.toDouble() ?? 30,
    );
  }

  static LabelTemplate defaultLabel() => LabelTemplate(
        blockLayout: LabelBlockLayout.defaultLayout,
        style: const LabelStyle(),
        widthMm: 40,
        heightMm: 30,
      );

  static LabelTemplate defaultPriceTag() => LabelTemplate(
        blockLayout: LabelBlockLayout.defaultLayout,
        style: const LabelStyle(),
        widthMm: 58,
        heightMm: 30,
      );
}

/// Пресет размера стикера (ширина x высота в мм).
class LabelPreset {
  const LabelPreset(this.name, this.widthMm, this.heightMm);
  final String name;
  final double widthMm;
  final double heightMm;

  static const LabelPreset label = LabelPreset('Этикетка', 40, 30);
  static const LabelPreset priceTag = LabelPreset('Ценник', 58, 30);
}

/// Формирует PDF с этикетками/ценниками: сетка стикеров на A4.
class LabelPdfService {
  static const double _mmToPt = 72 / 25.4; // ~2.835

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

  /// Строит PDF: список товаров, расположение блоков на холсте, размер стикера.
  /// Если заданы widthMm и heightMm (положительные), они имеют приоритет над размерами из preset.
  static Future<Uint8List> buildLabelPdf({
    required List<Product> products,
    required List<LabelBlockLayout> blockLayout,
    required LabelPreset preset,
    double? widthMm,
    double? heightMm,
    LabelStyle style = const LabelStyle(),
  }) async {
    final theme = await _loadCyrillicTheme();
    final pdf = pw.Document(theme: theme);

    final wMm = (widthMm != null && widthMm > 0 && heightMm != null && heightMm > 0)
        ? widthMm
        : preset.widthMm;
    final hMm = (widthMm != null && widthMm > 0 && heightMm != null && heightMm > 0)
        ? heightMm
        : preset.heightMm;
    final widthPt = wMm * _mmToPt;
    final heightPt = hMm * _mmToPt;

    // A4: 595 x 842 pt. Сетка с отступами.
    const marginPt = 20.0;
    const gapPt = 4.0;
    final usableW = PdfPageFormat.a4.width - 2 * marginPt;
    final usableH = PdfPageFormat.a4.height - 2 * marginPt;
    final perRow = ((usableW + gapPt) / (widthPt + gapPt)).floor();
    final perCol = ((usableH + gapPt) / (heightPt + gapPt)).floor();
    final perPage = perRow * perCol;

    if (perPage < 1) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) => pw.Center(
            child: pw.Text('Слишком большой размер стикера'),
          ),
        ),
      );
      return pdf.save();
    }

    for (var pageStart = 0; pageStart < products.length; pageStart += perPage) {
      final pageProducts = products
          .skip(pageStart)
          .take(perPage)
          .toList();

      final children = <pw.Widget>[];
      for (var i = 0; i < pageProducts.length; i++) {
        final col = i % perRow;
        final row = i ~/ perRow;
        final left = marginPt + col * (widthPt + gapPt);
        final top = marginPt + row * (heightPt + gapPt);
        final product = pageProducts[i];
        final sticker = await _buildSticker(
          product: product,
          blockLayout: blockLayout,
          widthPt: widthPt,
          heightPt: heightPt,
          style: style,
        );
        children.add(
          pw.Positioned(
            left: left,
            top: top,
            child: pw.SizedBox(
              width: widthPt,
              height: heightPt,
              child: sticker,
            ),
          ),
        );
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) => pw.Stack(
            children: children,
          ),
        ),
      );
    }

    return pdf.save();
  }

  /// Формирует имя файла этикетки: название_штрихкод.jpg
  static String labelFileName(Product product) {
    final safe = (String s) => s.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();
    final name = safe(product.name)
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final barcode = product.barcode?.trim() ?? '';
    final base = barcode.isNotEmpty ? '${name}_$barcode' : name;
    return (base.isEmpty ? 'etiketka' : base) + '.jpg';
  }

  /// Строит одну этикетку как JPG.
  static Future<Uint8List> buildLabelJpg({
    required Product product,
    required List<LabelBlockLayout> blockLayout,
    required double widthMm,
    required double heightMm,
    LabelStyle style = const LabelStyle(),
    int jpgQuality = 95,
    double dpi = 150,
  }) async {
    final theme = await _loadCyrillicTheme();
    final widthPt = widthMm * _mmToPt;
    final heightPt = heightMm * _mmToPt;
    final pageFormat = PdfPageFormat(widthPt, heightPt, marginAll: 0);

    final pdf = pw.Document(theme: theme);
    final sticker = await _buildSticker(
      product: product,
      blockLayout: blockLayout,
      widthPt: widthPt,
      heightPt: heightPt,
      style: style,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (_) => sticker,
      ),
    );

    final pdfBytes = await pdf.save();
    PdfRaster? raster;
    await for (final page in Printing.raster(
      pdfBytes,
      pages: [0],
      dpi: dpi,
    )) {
      raster = page;
      break;
    }

    if (raster == null) throw Exception('Не удалось преобразовать этикетку в изображение');

    final pngBytes = await raster.toPng();
    final image = img.decodeImage(pngBytes);
    if (image == null) throw Exception('Не удалось декодировать изображение');

    return Uint8List.fromList(img.encodeJpg(image, quality: jpgQuality));
  }

  static Future<pw.Widget> _buildSticker({
    required Product product,
    required List<LabelBlockLayout> blockLayout,
    required double widthPt,
    required double heightPt,
    required LabelStyle style,
  }) async {
    final positioned = <pw.Widget>[];
    for (final layout in blockLayout) {
      final left = layout.x * widthPt;
      final top = layout.y * heightPt;
      pw.Widget? content;
      switch (layout.type) {
        case LabelBlockType.name:
          content = pw.Padding(
            padding: const pw.EdgeInsets.all(2),
            child: pw.SizedBox(
              width: widthPt * 0.9,
              child: pw.Text(
                product.name,
                style: pw.TextStyle(fontSize: style.nameFontSize),
                maxLines: 2,
                overflow: pw.TextOverflow.clip,
              ),
            ),
          );
          break;
        case LabelBlockType.barcode:
          final barcodeStr = product.barcode?.trim() ?? '';
          if (barcodeStr.isNotEmpty) {
            final bcW = (widthPt * style.barcodeWidthFactor * 2).round().clamp(50, 800);
            final bcH = (heightPt * style.barcodeHeightFactor * 2).round().clamp(20, 400);
            final pngBytes = await barcodeToPngBytes(
              barcodeStr,
              width: bcW,
              height: bcH,
            );
            if (pngBytes != null) {
              content = pw.SizedBox(
                width: widthPt * style.barcodeWidthFactor,
                height: heightPt * style.barcodeHeightFactor,
                child: pw.Image(
                  pw.MemoryImage(pngBytes),
                  fit: pw.BoxFit.contain,
                ),
              );
            }
          }
          break;
        case LabelBlockType.price:
          content = pw.Padding(
            padding: const pw.EdgeInsets.all(2),
            child: pw.Text(
              product.effectivePrice.toStringAsFixed(2),
              style: pw.TextStyle(
                fontSize: style.priceFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          );
          break;
      }
      if (content != null) {
        positioned.add(
          pw.Positioned(
            left: left,
            top: top,
            child: content,
          ),
        );
      }
    }

    return pw.Container(
      width: widthPt,
      height: heightPt,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.5),
      ),
      child: pw.Stack(
        children: positioned.isEmpty
            ? [pw.SizedBox(width: widthPt, height: heightPt)]
            : positioned,
      ),
    );
  }

  static String _formatStock(double value, String unit) {
    if (unit == 'pcs') return value.toStringAsFixed(0);
    if (value == value.roundToDouble()) return value.toInt().toString();
    final s = value.toStringAsFixed(2);
    if (s.contains('.')) {
      final trimmed = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      return trimmed;
    }
    return s;
  }

  /// PDF-отчёт со списком заканчивающихся товаров (stock <= stock_threshold).
  static Future<Uint8List> buildLowStockReportPdf(List<Product> products) async {
    final theme = await _loadCyrillicTheme();
    final pdf = pw.Document(theme: theme);

    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

    const rowsPerPage = 25;
    for (var pageStart = 0; pageStart < products.length; pageStart += rowsPerPage) {
      final pageProducts = products.skip(pageStart).take(rowsPerPage).toList();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Заканчивающиеся товары',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Дата: $dateStr', style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(0.8),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FlexColumnWidth(0.8),
                  5: const pw.FlexColumnWidth(1.2),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('ID', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Название', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Остаток', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Порог', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Ед.', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Цена', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                  ...pageProducts.map(
                    (p) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('${p.id}', style: const pw.TextStyle(fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(p.name, style: const pw.TextStyle(fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(_formatStock(p.stock, p.unit), style: const pw.TextStyle(fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(_formatStock(p.stockThreshold, p.unit), style: const pw.TextStyle(fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(p.unit == 'pcs' ? 'шт.' : 'г', style: const pw.TextStyle(fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(p.effectivePrice.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (products.isEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Заканчивающиеся товары',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Дата: $dateStr', style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 12),
              pw.Text('Нет заканчивающихся товаров', style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ),
      );
    }

    return pdf.save();
  }
}
