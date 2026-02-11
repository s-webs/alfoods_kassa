import 'dart:typed_data';

import 'package:barcode_image/barcode_image.dart';
import 'package:image/image.dart' as img;

/// Рисует штрихкод в PNG и возвращает байты.
/// Для 13 цифр используется EAN-13, иначе Code128.
/// Возвращает null при пустой [data] или ошибке.
Future<Uint8List?> barcodeToPngBytes(
  String data, {
  int width = 200,
  int height = 80,
}) async {
  final trimmed = data.trim();
  if (trimmed.isEmpty) return null;

  try {
    final bc = _barcodeFor(trimmed);
    if (bc == null) return null;

    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    drawBarcode(
      image,
      bc,
      trimmed,
      x: 0,
      y: 0,
      width: width,
      height: height,
    );
    return Uint8List.fromList(img.encodePng(image));
  } catch (_) {
    return null;
  }
}

Barcode? _barcodeFor(String data) {
  if (RegExp(r'^\d{13}$').hasMatch(data)) {
    try {
      Barcode.ean13().verify(data);
      return Barcode.ean13();
    } catch (_) {
      return Barcode.code128();
    }
  }
  return Barcode.code128();
}
