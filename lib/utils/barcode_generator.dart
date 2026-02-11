import 'dart:math';

import 'package:barcode/barcode.dart';

/// Генерирует новый валидный штрихкод EAN-13 (13 цифр, последняя — контрольная).
/// Подходит для подстановки в поле штрихкода при добавлении/редактировании товара.
String generateBarcode() {
  final r = Random();
  // 12 цифр: первая от 1 до 9 (избегаем ведущего 0 для совместимости с частью сканеров)
  final digits = List<int>.generate(12, (i) => i == 0 ? 1 + r.nextInt(9) : r.nextInt(10));
  final check = _ean13CheckDigit(digits);
  final code = '${digits.join()}$check';
  Barcode.ean13().verify(code);
  return code;
}

int _ean13CheckDigit(List<int> digits12) {
  int sum = 0;
  for (var i = 0; i < 12; i++) {
    if (i.isOdd) {
      sum += digits12[i] * 3;
    } else {
      sum += digits12[i];
    }
  }
  final r = sum % 10;
  return r == 0 ? 0 : 10 - r;
}
