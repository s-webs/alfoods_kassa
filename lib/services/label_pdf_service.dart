import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/product.dart';
import '../utils/barcode_image_helper.dart';

/// Тип блока на этикетке/ценнике.
enum LabelBlockType { name, barcode, price, description }

extension LabelBlockTypeX on LabelBlockType {
  String get title {
    switch (this) {
      case LabelBlockType.name:
        return 'Название';
      case LabelBlockType.barcode:
        return 'Штрихкод';
      case LabelBlockType.price:
        return 'Цена';
      case LabelBlockType.description:
        return 'Описание';
    }
  }
}

/// Расположение одного блока на холсте (x, y — доли 0..1 от размера стикера).
class LabelBlockLayout {
  const LabelBlockLayout({
    required this.type,
    required this.x,
    required this.y,
    this.visible = true,
  });
  final LabelBlockType type;
  final double x;
  final double y;

  /// Показывать ли блок на этикетке/ценнике.
  final bool visible;

  LabelBlockLayout copyWith({double? x, double? y, bool? visible}) =>
      LabelBlockLayout(
        type: type,
        x: x ?? this.x,
        y: y ?? this.y,
        visible: visible ?? this.visible,
      );

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'x': x,
    'y': y,
    'visible': visible,
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
      case 'description':
        t = LabelBlockType.description;
        break;
      default:
        t = LabelBlockType.name;
    }
    return LabelBlockLayout(
      type: t,
      x: (json['x'] as num?)?.toDouble() ?? 0.05,
      y: (json['y'] as num?)?.toDouble() ?? 0.05,
      visible: json['visible'] as bool? ?? true,
    );
  }

  static List<LabelBlockLayout> get defaultLayout => [
    const LabelBlockLayout(type: LabelBlockType.name, x: 0.05, y: 0.05),
    const LabelBlockLayout(type: LabelBlockType.barcode, x: 0.05, y: 0.35),
    const LabelBlockLayout(type: LabelBlockType.price, x: 0.05, y: 0.78),
  ];
}

/// Соотношение сторон штрихкода как в превью (ширина : высота = 2.5 : 1).
const double _barcodeAspectRatio = 2.5;

/// Настройки оформления этикетки: размеры шрифтов и штрихкода.
class LabelStyle {
  const LabelStyle({
    this.nameFontSize = 8,
    this.priceFontSize = 10,
    this.descriptionFontSize = 7,
    this.barcodeScaleFactor = 0.95,
    this.barcodeHeightScaleFactor = 1.0,
    this.showBorder = true,
  });

  /// Размер шрифта названия (pt).
  final double nameFontSize;

  /// Размер шрифта цены (pt).
  final double priceFontSize;

  /// Размер шрифта описания (pt).
  final double descriptionFontSize;

  /// Масштаб штрихкода — доля ширины холста (0.15..1). Высота = ширина / 2.5.
  final double barcodeScaleFactor;

  /// Масштаб высоты штрихкода относительно вычисленной из ширины высоты.
  /// Позволяет менять высоту независимо от ширины.
  final double barcodeHeightScaleFactor;

  /// Показывать ли границу вокруг этикетки/ценника.
  final bool showBorder;

  LabelStyle copyWith({
    double? nameFontSize,
    double? priceFontSize,
    double? descriptionFontSize,
    double? barcodeScaleFactor,
    double? barcodeHeightScaleFactor,
    bool? showBorder,
  }) => LabelStyle(
    nameFontSize: nameFontSize ?? this.nameFontSize,
    priceFontSize: priceFontSize ?? this.priceFontSize,
    descriptionFontSize: descriptionFontSize ?? this.descriptionFontSize,
    barcodeScaleFactor: barcodeScaleFactor ?? this.barcodeScaleFactor,
    barcodeHeightScaleFactor:
        barcodeHeightScaleFactor ?? this.barcodeHeightScaleFactor,
    showBorder: showBorder ?? this.showBorder,
  );

  static const double minFontSize = 4;
  static const double maxFontSize = 36;
  static const double minBarcodeFactor = 0.15;
  static const double maxBarcodeFactor = 1.0;
  static const double minBarcodeHeightFactor = 0.5;
  static const double maxBarcodeHeightFactor = 1.5;

  Map<String, dynamic> toJson() => {
    'nameFontSize': nameFontSize,
    'priceFontSize': priceFontSize,
    'descriptionFontSize': descriptionFontSize,
    'barcodeScaleFactor': barcodeScaleFactor,
    'barcodeHeightScaleFactor': barcodeHeightScaleFactor,
    'showBorder': showBorder,
  };

  static LabelStyle fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LabelStyle();
    final scale = (json['barcodeScaleFactor'] as num?)?.toDouble() ??
        (json['barcodeWidthFactor'] as num?)?.toDouble() ??
        0.95;
    final heightScale = (json['barcodeHeightScaleFactor'] as num?)?.toDouble() ??
        1.0;
    return LabelStyle(
      nameFontSize: (json['nameFontSize'] as num?)?.toDouble() ?? 8,
      priceFontSize: (json['priceFontSize'] as num?)?.toDouble() ?? 10,
      descriptionFontSize:
          (json['descriptionFontSize'] as num?)?.toDouble() ?? 7,
      barcodeScaleFactor: scale,
      barcodeHeightScaleFactor: heightScale,
      showBorder: json['showBorder'] as bool? ?? true,
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

    final wMm =
        (widthMm != null && widthMm > 0 && heightMm != null && heightMm > 0)
        ? widthMm
        : preset.widthMm;
    final hMm =
        (widthMm != null && widthMm > 0 && heightMm != null && heightMm > 0)
        ? heightMm
        : preset.heightMm;
    final widthPt = wMm * _mmToPt;
    final heightPt = hMm * _mmToPt;

    // A4: 595 x 842 pt. Сетка с отступами (уменьшенный отступ для печати).
    const marginLeftPt = 0.0;
    const marginRightPt = 0.0;
    const marginTopPt = 0.0;
    const marginBottomPt = 0.0;
    const gapPt = 4.0;
    final usableW = PdfPageFormat.a4.width - marginLeftPt - marginRightPt;
    final usableH = PdfPageFormat.a4.height - marginTopPt - marginBottomPt;
    final perRow = ((usableW + gapPt) / (widthPt + gapPt)).floor();
    final perCol = ((usableH + gapPt) / (heightPt + gapPt)).floor();
    final perPage = perRow * perCol;

    if (perPage < 1) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) =>
              pw.Center(child: pw.Text('Слишком большой размер стикера')),
        ),
      );
      return pdf.save();
    }

    for (var pageStart = 0; pageStart < products.length; pageStart += perPage) {
      final pageProducts = products.skip(pageStart).take(perPage).toList();

      final children = <pw.Widget>[];
      for (var i = 0; i < pageProducts.length; i++) {
        final col = i % perRow;
        final row = i ~/ perRow;
        final left = marginLeftPt + col * (widthPt + gapPt);
        final top = marginTopPt + row * (heightPt + gapPt);
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
          build: (pw.Context context) => pw.Stack(children: children),
        ),
      );
    }

    return pdf.save();
  }

  /// Формирует имя файла этикетки: название_штрихкод.jpg
  static String labelFileName(Product product) {
    final safe = (String s) =>
        s.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();
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
    await for (final page in Printing.raster(pdfBytes, pages: [0], dpi: dpi)) {
      raster = page;
      break;
    }

    if (raster == null)
      throw Exception('Не удалось преобразовать этикетку в изображение');

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
      if (!layout.visible) continue;
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
            final bcW = (widthPt * style.barcodeScaleFactor * 2).round().clamp(
              50,
              800,
            );
            final bcH = (bcW / _barcodeAspectRatio * style.barcodeHeightScaleFactor)
                .round()
                .clamp(20, 400);
            final pngBytes = await barcodeToPngBytes(
              barcodeStr,
              width: bcW,
              height: bcH,
            );
            if (pngBytes != null) {
              final w = widthPt * style.barcodeScaleFactor;
              final h =
                  (w / _barcodeAspectRatio) * style.barcodeHeightScaleFactor;
              content = pw.SizedBox(
                width: w,
                height: h,
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
        case LabelBlockType.description:
          final desc = product.meta?['description']?.toString() ?? '';
          if (desc.isNotEmpty) {
            content = pw.Padding(
              padding: const pw.EdgeInsets.all(2),
              child: pw.SizedBox(
                width: widthPt * 0.9,
                child: pw.Text(
                  desc,
                  style: pw.TextStyle(fontSize: style.descriptionFontSize),
                  maxLines: null,
                  overflow: pw.TextOverflow.visible,
                ),
              ),
            );
          }
          break;
      }
      if (content != null) {
        positioned.add(pw.Positioned(left: left, top: top, child: content));
      }
    }

    return pw.Container(
      width: widthPt,
      height: heightPt,
      decoration: pw.BoxDecoration(
        border: style.showBorder ? pw.Border.all(width: 0.5) : null,
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
      final trimmed = s
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.$'), '');
      return trimmed;
    }
    return s;
  }

  /// PDF-отчёт со списком заканчивающихся товаров (stock <= stock_threshold).
  static Future<Uint8List> buildLowStockReportPdf(
    List<Product> products,
  ) async {
    final theme = await _loadCyrillicTheme();
    final pdf = pw.Document(theme: theme);

    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

    const rowsPerPage = 25;
    for (
      var pageStart = 0;
      pageStart < products.length;
      pageStart += rowsPerPage
    ) {
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
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
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
                        child: pw.Text(
                          'ID',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          'Название',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          'Остаток',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          'Порог',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          'Ед.',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          'Цена',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ...pageProducts.map(
                    (p) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            '${p.id}',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            p.name,
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            _formatStock(p.stock, p.unit),
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            _formatStock(p.stockThreshold, p.unit),
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            p.unit == 'pcs' ? 'шт.' : 'г',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            p.effectivePrice.toStringAsFixed(2),
                            style: const pw.TextStyle(fontSize: 8),
                          ),
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
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Дата: $dateStr', style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 12),
              pw.Text(
                'Нет заканчивающихся товаров',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      );
    }

    return pdf.save();
  }

  /// Печать: Название / Штрихкод / остаток. Для системного диалога печати.
  static Future<Uint8List> buildProductsPrintNameBarcodeStock(
    List<Product> products,
  ) async {
    final theme = await _loadCyrillicTheme();
    final pdf = pw.Document(theme: theme);
    const rowsPerPage = 30;
    for (
      var pageStart = 0;
      pageStart < products.length;
      pageStart += rowsPerPage
    ) {
      final pageProducts = products.skip(pageStart).take(rowsPerPage).toList();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Товары: Название / Штрихкод / Остаток',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(0.8),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      _cell('Название', bold: true),
                      _cell('Штрихкод', bold: true),
                      _cell('Остаток', bold: true),
                    ],
                  ),
                  ...pageProducts.map(
                    (p) => pw.TableRow(
                      children: [
                        _cell(p.name),
                        _cell(p.barcode ?? '-'),
                        _cell(_formatStock(p.stock, p.unit)),
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
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) => pw.Center(
            child: pw.Text('Нет товаров', style: pw.TextStyle(fontSize: 12)),
          ),
        ),
      );
    }
    return pdf.save();
  }

  /// Печать: Название / цена. Для системного диалога печати.
  static Future<Uint8List> buildProductsPrintNamePrice(
    List<Product> products,
  ) async {
    final theme = await _loadCyrillicTheme();
    final pdf = pw.Document(theme: theme);
    const rowsPerPage = 35;
    for (
      var pageStart = 0;
      pageStart < products.length;
      pageStart += rowsPerPage
    ) {
      final pageProducts = products.skip(pageStart).take(rowsPerPage).toList();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Товары: Название / Цена',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(4),
                  1: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      _cell('Название', bold: true),
                      _cell('Цена', bold: true),
                    ],
                  ),
                  ...pageProducts.map(
                    (p) => pw.TableRow(
                      children: [
                        _cell(p.name),
                        _cell(p.effectivePrice.toStringAsFixed(2)),
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
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) => pw.Center(
            child: pw.Text('Нет товаров', style: pw.TextStyle(fontSize: 12)),
          ),
        ),
      );
    }
    return pdf.save();
  }

  /// Печать: Название / остаток / цена прихода / цена / остаток*приход / остаток*цена.
  static Future<Uint8List> buildProductsPrintFull(
    List<Product> products,
  ) async {
    final theme = await _loadCyrillicTheme();
    final pdf = pw.Document(theme: theme);
    const rowsPerPage = 43;
    final totalCost = products.isEmpty
        ? 0.0
        : products.fold<double>(0, (s, p) => s + p.stock * p.purchasePrice);
    final totalSale = products.isEmpty
        ? 0.0
        : products.fold<double>(0, (s, p) => s + p.stock * p.effectivePrice);
    for (
      var pageStart = 0;
      pageStart < products.length;
      pageStart += rowsPerPage
    ) {
      final pageProducts = products.skip(pageStart).take(rowsPerPage).toList();
      final isLastPage = pageStart + rowsPerPage >= products.length;
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Товары: остатки и суммы',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.5),
                  1: const pw.FlexColumnWidth(0.6),
                  2: const pw.FlexColumnWidth(0.8),
                  3: const pw.FlexColumnWidth(0.8),
                  4: const pw.FlexColumnWidth(1),
                  5: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      _cell('Название', bold: true),
                      _cell('Остаток', bold: true),
                      _cell('Цена прихода', bold: true),
                      _cell('Цена', bold: true),
                      _cell('Остаток×приход', bold: true),
                      _cell('Остаток×цена', bold: true),
                    ],
                  ),
                  ...pageProducts.map((p) {
                    final costSum = p.stock * p.purchasePrice;
                    final priceSum = p.stock * p.effectivePrice;
                    return pw.TableRow(
                      children: [
                        _cell(p.name),
                        _cell(_formatStock(p.stock, p.unit)),
                        _cell(p.purchasePrice.toStringAsFixed(2)),
                        _cell(p.effectivePrice.toStringAsFixed(2)),
                        _cell(costSum.toStringAsFixed(2)),
                        _cell(priceSum.toStringAsFixed(2)),
                      ],
                    );
                  }),
                ],
              ),
              if (isLastPage) ...[
                pw.SizedBox(height: 16),
                pw.Text(
                  'Итого',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Сумма по цене закупа: ${totalCost.toStringAsFixed(2)}',
                  style: pw.TextStyle(fontSize: 11),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Сумма по цене продажи: ${totalSale.toStringAsFixed(2)}',
                  style: pw.TextStyle(fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (products.isEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) => pw.Center(
            child: pw.Text('Нет товаров', style: pw.TextStyle(fontSize: 12)),
          ),
        ),
      );
    }
    return pdf.save();
  }

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
