import 'dart:typed_data';

import 'package:alfoods_kassa/models/cart_item.dart';
import 'package:alfoods_kassa/services/receipt_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

double? _mediaBoxHeightPt(Uint8List bytes) {
  final raw = String.fromCharCodes(bytes);
  final match =
      RegExp(r'MediaBox\[0 0 [\d.]+ ([\d.]+)\]').firstMatch(raw)?.group(1);
  if (match == null) return null;
  return double.parse(match);
}

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
    expect(String.fromCharCodes(bytes), contains('%PDF'));
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

    final pageHeightPt = _mediaBoxHeightPt(bytes);
    expect(pageHeightPt, isNotNull);
    expect(pageHeightPt!, greaterThan(240));
  });

  test('buildReceiptPdf page height grows with item count (200 items)', () async {
    final fewItems = [
      CartItem(
        productId: 1,
        name: 'Short',
        price: 100,
        quantity: 1,
        unit: 'pcs',
      ),
      CartItem(
        productId: 2,
        name: 'Short 2',
        price: 200,
        quantity: 1,
        unit: 'pcs',
      ),
    ];

    final manyItems = List.generate(
      200,
      (i) => CartItem(
        productId: i + 1,
        name: 'Line item ${i + 1}',
        price: 100,
        quantity: 1,
        unit: 'pcs',
      ),
    );

    final fewBytes = await ReceiptPdfService.buildReceiptPdf(
      saleId: 1,
      cashierName: 'Test',
      items: fewItems,
      total: 300,
      totalQty: 2,
      dateTime: DateTime(2026, 5, 23, 12, 0, 0),
    );
    final manyBytes = await ReceiptPdfService.buildReceiptPdf(
      saleId: 2,
      cashierName: 'Test',
      items: manyItems,
      total: 20000,
      totalQty: 200,
      dateTime: DateTime(2026, 5, 23, 12, 0, 0),
    );

    final fewHeight = _mediaBoxHeightPt(fewBytes)!;
    final manyHeight = _mediaBoxHeightPt(manyBytes)!;

    expect(manyHeight, greaterThan(fewHeight * 10));
  });

  test('buildReceiptPdf is tall enough for 200 items (no height cap)', () async {
    final items = List.generate(
      200,
      (i) => CartItem(
        productId: i + 1,
        name: 'Line item ${i + 1}',
        price: 100,
        quantity: 1,
        unit: 'pcs',
      ),
    );

    final bytes = await ReceiptPdfService.buildReceiptPdf(
      saleId: 999,
      cashierName: 'Test',
      items: items,
      total: 20000,
      totalQty: 200,
      dateTime: DateTime(2026, 5, 23, 12, 0, 0),
    );

    // 72+18+200×20+95+16 ≈ 4201 pt.
    expect(_mediaBoxHeightPt(bytes), greaterThan(4000));
  });

  test('buildReceiptPdf fits ~21 items without clip or huge tail', () async {
    final items = List.generate(
      21,
      (i) => CartItem(
        productId: i + 1,
        name: 'Test product ${i + 1}',
        price: 1000,
        quantity: 1,
        unit: 'pcs',
      ),
    );

    final bytes = await ReceiptPdfService.buildReceiptPdf(
      saleId: 13124,
      cashierName: 'Nikita V',
      items: items,
      total: 21000,
      totalQty: 21,
      dateTime: DateTime(2026, 5, 23, 17, 8, 30),
    );

    final h = _mediaBoxHeightPt(bytes)!;
    // Слишком низко — обрезка (только шапка); слишком высоко — белый хвост.
    expect(h, greaterThan(400));
    expect(h, lessThan(3500));
  });

  test('buildReceiptPdf tall enough for long wrapped product name', () async {
    final longName =
        'Very long product name that must wrap across several lines in the receipt';
    final shortItems = [
      CartItem(
        productId: 1,
        name: 'Short',
        price: 100,
        quantity: 1,
        unit: 'pcs',
      ),
    ];
    final longNameItems = [
      CartItem(
        productId: 1,
        name: longName,
        price: 100,
        quantity: 1,
        unit: 'pcs',
      ),
    ];

    final shortBytes = await ReceiptPdfService.buildReceiptPdf(
      saleId: 1,
      cashierName: 'Test',
      items: shortItems,
      total: 100,
      totalQty: 1,
      dateTime: DateTime(2026, 5, 23, 12, 0, 0),
    );
    final longBytes = await ReceiptPdfService.buildReceiptPdf(
      saleId: 2,
      cashierName: 'Test',
      items: longNameItems,
      total: 100,
      totalQty: 1,
      dateTime: DateTime(2026, 5, 23, 12, 0, 0),
    );

    expect(
      _mediaBoxHeightPt(longBytes)!,
      greaterThan(_mediaBoxHeightPt(shortBytes)! + 20),
    );
  });
}
