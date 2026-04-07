import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Результат оптимизации: байты и имя файла для загрузки.
class OptimizedImage {
  const OptimizedImage({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

/// Клиентская оптимизация изображений перед загрузкой: сжатие и конвертация в WebP.
/// Ограничивает размер по большей стороне 1920px, качество 85%.
class ImageOptimizer {
  ImageOptimizer._();

  static const int _maxDimension = 1920;
  static const int _quality = 85;

  /// Оптимизирует файл по пути. Возвращает [OptimizedImage] или null при ошибке / неподдерживаемой платформе.
  static Future<OptimizedImage?> optimizeFile(String path) async {
    try {
      final bytes = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: _maxDimension,
        minHeight: _maxDimension,
        quality: _quality,
        format: CompressFormat.webp,
      );
      if (bytes == null || bytes.isEmpty) return null;
      return OptimizedImage(bytes: bytes, filename: 'image.webp');
    } catch (_) {
      return null;
    }
  }

  /// Оптимизирует изображение из байтов (например с веба или из XFile.readAsBytes).
  static Future<OptimizedImage?> optimizeBytes(Uint8List bytes) async {
    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: _maxDimension,
        minHeight: _maxDimension,
        quality: _quality,
        format: CompressFormat.webp,
      );
      if (result.isEmpty) return null;
      return OptimizedImage(bytes: result, filename: 'image.webp');
    } catch (_) {
      return null;
    }
  }
}
