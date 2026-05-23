import 'dart:typed_data';

import 'package:alfoods_kassa/models/cart_item.dart';
import 'package:alfoods_kassa/services/receipt_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildReceiptPdf produces non-empty PDF for large prices', () async {
    final items = [
      CartItem(
        productId: 1,
        name: 'Terea blue (test)',
        price: 100050,
        quantity: 3,
        unit: 'pcs',
      ),
    ];

    final Uint8List bytes = await ReceiptPdfService.buildReceiptPdf(
      saleId: 12976,
      cashierName: 'Almaty-Foods',
      items: items,
      total: 300150,
      totalQty: 3,
      dateTime: DateTime(2026, 5, 23, 10, 48, 13),
    );

    expect(bytes.length, greaterThan(500));
    expect(
      String.fromCharCodes(bytes),
      contains('%PDF'),
    );
  });

  test('buildReceiptPdf uses enough page height for multiple items', () async {
    final items = [
      CartItem(
        productId: 1,
        name: 'Terea Pearl (test)',
        price: 103550,
        quantity: 2,
        unit: 'pcs',
      ),
      CartItem(
        productId: 2,
        name: 'Terea blue (test)',
        price: 1150,
        quantity: 7,
        unit: 'pcs',
      ),
    ];

    final bytes = await ReceiptPdfService.buildReceiptPdf(
      saleId: 13002,
      cashierName: 'Test cashier',
      items: items,
      total: 215150,
      totalQty: 9,
      dateTime: DateTime(2026, 5, 23, 12, 0, 0),
    );

    final raw = String.fromCharCodes(bytes);
    // 115 мм ≈ 326 pt — ниже этого footer часто обрезается.
    final mediaBox = RegExp(r'MediaBox\[0 0 [\d.]+ ([\d.]+)\]')
        .firstMatch(raw)
        ?.group(1);
    expect(mediaBox, isNotNull);
    final pageHeightPt = double.parse(mediaBox!);
    expect(pageHeightPt, greaterThan(320));
  });
}
