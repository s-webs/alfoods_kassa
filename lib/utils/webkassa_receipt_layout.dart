import '../models/webkassa_print_line.dart';

/// Определяет выравнивание строк фискального чека WebKassa.
///
/// По умолчанию — по центру. По левому краю: таблица товаров и нижний блок
/// (ОФД, адрес, фискальные реквизиты).
class WebkassaReceiptLayout {
  /// `true` — по левому краю, `false` — по центру.
  static List<bool> leftAlignFlags(List<WebkassaPrintLine> lines) {
    final sorted = List<WebkassaPrintLine>.from(lines)
      ..sort((a, b) => a.order.compareTo(b.order));

    final left = List<bool>.filled(sorted.length, false);
    int? productStart;
    int? productEnd;
    int? footerStart;

    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i].type != 0) continue;
      final n = _norm(sorted[i].value);

      if (productStart == null && _isProductTableStart(n)) {
        productStart = i;
      } else if (productStart != null &&
          productEnd == null &&
          _isAfterProducts(n)) {
        productEnd = i;
      }

      if (footerStart == null && _isFooterStart(n)) {
        footerStart = i;
      }
    }

    if (productStart == null) {
      for (var i = 0; i < sorted.length; i++) {
        if (sorted[i].type != 0) continue;
        if (_looksLikeProductRow(_norm(sorted[i].value))) {
          productStart = i;
          break;
        }
      }
    }

    if (productStart != null && productEnd == null) {
      for (var i = productStart + 1; i < sorted.length; i++) {
        if (sorted[i].type != 0) continue;
        if (_isAfterProducts(_norm(sorted[i].value))) {
          productEnd = i;
          break;
        }
      }
    }

    for (var i = 0; i < sorted.length; i++) {
      final inProducts = productStart != null &&
          i >= productStart &&
          (productEnd == null || i < productEnd);
      final inFooter = footerStart != null && i >= footerStart;
      left[i] = inProducts || inFooter;
    }

    return left;
  }

  static bool isLeftAligned(int index, List<bool> flags) {
    if (index < 0 || index >= flags.length) return false;
    return flags[index];
  }

  static String _norm(String value) => value.replaceAll('\t', ' ');

  static bool _isProductTableStart(String n) {
    final u = n.toUpperCase();
    if (u.contains('НАИМЕНОВАНИЕ')) return true;
    if (u.contains('КОЛ') && (u.contains('ЦЕН') || u.contains('СУММ'))) {
      return true;
    }
    return false;
  }

  static bool _isAfterProducts(String n) {
    final u = n.trim().toUpperCase();
    if (RegExp(r'^ИТОГО\b').hasMatch(u)) return true;
    if (RegExp(r'^ИТОГ\b').hasMatch(u)) return true;
    if (RegExp(r'^ВСЕГО\b').hasMatch(u)) return true;
    if (u.contains('К ОПЛАТЕ') || u.contains('КО ОПЛАТЕ')) return true;
    if (RegExp(r'^НДС\b').hasMatch(u)) return true;
    if (RegExp(r'^ПОЛУЧЕНО\b').hasMatch(u)) return true;
    if (RegExp(r'^СДАЧА\b').hasMatch(u)) return true;
    if (RegExp(r'^НАЛИЧН').hasMatch(u)) return true;
    if (RegExp(r'^БЕЗНАЛ').hasMatch(u)) return true;
    if (RegExp(r'^КАРТ').hasMatch(u) && u.contains('ОПЛАТ')) return true;
    return false;
  }

  static bool _isFooterStart(String n) {
    final u = n.toUpperCase();
    final lower = n.toLowerCase();
    if (u.contains('ОФД')) return true;
    if (lower.contains('ofd')) return true;
    if (u.contains('CONSUMER')) return true;
    if (RegExp(r'\bФП\b').hasMatch(u) || u.startsWith('ФП:') || u.startsWith('ФП ')) {
      return true;
    }
    if (u.contains('РНК') || u.contains('ЗНМ') || u.contains('ЗН ККМ')) {
      return true;
    }
    if (RegExp(r'^АДРЕС\b', caseSensitive: false).hasMatch(n.trim())) {
      return true;
    }
    final t = n.trim().toLowerCase();
    if (t.startsWith('http://') || t.startsWith('https://')) return true;
    if (u.contains('FISCAL.GOV') || u.contains('KOFD')) return true;
    if (lower.contains('webkassa.kz') && (lower.contains('http') || u.contains('ПРОВЕР'))) {
      return true;
    }
    return false;
  }

  static bool _looksLikeProductRow(String n) {
    if (_isProductTableStart(n)) return true;
    if (RegExp(r'\d+[.,]\d+\s*[xх×*]\s*\d+', caseSensitive: false).hasMatch(n)) {
      return true;
    }
    if (RegExp(r'\d+[.,]\d{2}\s*=').hasMatch(n)) return true;
    if (RegExp(r'\d+[.,]\d{2}').allMatches(n).length >= 2) return true;
    return false;
  }
}
