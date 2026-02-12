/// Перевод числа и суммы прописью на русском (для накладной форма 3-2).

const List<String> _units = [
  '', 'один', 'два', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять',
  'десять', 'одиннадцать', 'двенадцать', 'тринадцать', 'четырнадцать', 'пятнадцать',
  'шестнадцать', 'семнадцать', 'восемнадцать', 'девятнадцать',
];

const List<String> _tens = [
  '', '', 'двадцать', 'тридцать', 'сорок', 'пятьдесят', 'шестьдесят',
  'семьдесят', 'восемьдесят', 'девяносто',
];

const List<String> _hundreds = [
  '', 'сто', 'двести', 'триста', 'четыреста', 'пятьсот', 'шестьсот',
  'семьсот', 'восемьсот', 'девятьсот',
];

String _tripletToWords(int n, bool feminine) {
  if (n == 0) return '';
  final h = n ~/ 100;
  final t = (n % 100) ~/ 10;
  final u = n % 10;
  final parts = <String>[];
  if (h > 0) parts.add(_hundreds[h]);
  if (t >= 2) {
    parts.add(_tens[t]);
    if (u == 1 && feminine) {
      parts.add('одна');
    } else if (u == 2 && feminine) {
      parts.add('две');
    } else if (u > 0) {
      parts.add(_units[u]);
    }
  } else if (t == 1 || u > 0) {
    final v = t * 10 + u;
    if (v == 1 && feminine) {
      parts.add('одна');
    } else if (v == 2 && feminine) {
      parts.add('две');
    } else {
      parts.add(_units[v]);
    }
  }
  return parts.join(' ');
}

/// Количество целым числом прописью (например для "всего отпущено").
/// [n] — неотрицательное целое.
String quantityInWords(int n) {
  if (n == 0) return 'ноль';
  if (n < 0) return quantityInWords(-n);
  if (n >= 1000000000) {
    final billions = n ~/ 1000000000;
    final rest = n % 1000000000;
    final b = _tripletToWords(billions, false);
    final suffix = _pluralForm(billions, 'миллиард', 'миллиарда', 'миллиардов');
    if (rest == 0) return '$b $suffix';
    return '$b $suffix ${quantityInWords(rest)}';
  }
  if (n >= 1000000) {
    final millions = n ~/ 1000000;
    final rest = n % 1000000;
    final m = _tripletToWords(millions, false);
    final suffix = _pluralForm(millions, 'миллион', 'миллиона', 'миллионов');
    if (rest == 0) return '$m $suffix';
    return '$m $suffix ${quantityInWords(rest)}';
  }
  if (n >= 1000) {
    final thousands = n ~/ 1000;
    final rest = n % 1000;
    final th = _tripletToWords(thousands, true);
    final suffix = _pluralForm(thousands, 'тысяча', 'тысячи', 'тысяч');
    if (rest == 0) return '$th $suffix';
    return '$th $suffix ${_tripletToWords(rest, false)}';
  }
  return _tripletToWords(n, false);
}

String _pluralForm(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return many;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}

/// Сумма в тенге прописью (целая часть + "тенге", без копеек для простоты).
/// [amount] — неотрицательное число, округляется до целого.
String amountInWords(double amount) {
  final n = amount.round();
  if (n == 0) return 'ноль тенге';
  if (n < 0) return amountInWords(-amount);
  final words = quantityInWords(n);
  final suffix = _pluralForm(n, 'тенге', 'тенге', 'тенге');
  return '$words $suffix';
}

/// Сумма прописью без валюты (для накладной: «в KZT три тысячи шестьсот»).
String amountInWordsNoCurrency(double amount) {
  final n = amount.round();
  if (n == 0) return 'ноль';
  if (n < 0) return amountInWordsNoCurrency(-amount);
  return quantityInWords(n);
}

/// Сумма прописью в формате накладной: «восемьдесят восемь тысяч тенге 00 тиын».
String amountInWordsWithTiyn(double amount) {
  final n = amount.round();
  final tyin = ((amount - n) * 100).round().clamp(0, 99);
  final tyinStr = tyin.toString().padLeft(2, '0');
  if (n == 0 && tyin == 0) return 'ноль тенге 00 тиын';
  if (n < 0) return amountInWordsWithTiyn(-amount);
  final words = quantityInWords(n);
  return '$words тенге $tyinStr тиын';
}
