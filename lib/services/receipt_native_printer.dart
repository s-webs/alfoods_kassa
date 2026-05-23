import 'dart:io';

import 'package:flutter/services.dart';

import '../models/cart_item.dart';

/// Прямая печать товарного чека через нативный Windows-плагин (GDI, без RAW/PDF).
class ReceiptNativePrinter {
  static const MethodChannel _channel =
      MethodChannel('receipt_native_printer');

  static Future<void> printReceipt({
    required String? printerName,
    required int saleId,
    required String cashierName,
    required List<CartItem> items,
    required double total,
    required double totalQty,
    required DateTime dateTime,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Нативная печать чека доступна только на Windows',
      );
    }

    final dtStr =
        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-'
        '${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}:'
        '${dateTime.second.toString().padLeft(2, '0')}';

    final args = <String, dynamic>{
      if (printerName != null && printerName.isNotEmpty)
        'printerName': printerName,
      'saleId': saleId,
      'cashierName': cashierName,
      'total': total,
      'totalQty': totalQty,
      'dateTime': dtStr,
      'items': items
          .map(
            (item) => {
              'name': item.name,
              'price': item.price,
              'quantity': item.quantity,
              'unit': item.unit,
              'total': item.total,
            },
          )
          .toList(),
    };

    try {
      final ok = await _channel.invokeMethod<bool>('printReceipt', args);
      if (ok != true) {
        throw Exception('Не удалось напечатать чек (native)');
      }
    } on PlatformException catch (e) {
      throw Exception(
        e.message ?? 'Ошибка нативной печати чека',
      );
    }
  }
}
