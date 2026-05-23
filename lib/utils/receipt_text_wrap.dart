/// Перенос текста для строк чека (RAW и PDF), как в [ReceiptPrinterService].
List<String> wrapReceiptText(String text, int maxWidth) {
  if (text.isEmpty) return [''];
  if (text.length <= maxWidth) return [text];
  final lines = <String>[];
  var remaining = text;
  while (remaining.isNotEmpty) {
    if (remaining.length <= maxWidth) {
      lines.add(remaining);
      break;
    }
    var splitAt = maxWidth;
    final chunk = remaining.substring(0, maxWidth);
    final lastSpace = chunk.lastIndexOf(' ');
    if (lastSpace > maxWidth ~/ 2) {
      splitAt = lastSpace + 1;
    }
    lines.add(remaining.substring(0, splitAt).trim());
    remaining = remaining.substring(splitAt).trimLeft();
  }
  return lines;
}

/// Ширина колонки «Наименование» в символах (RAW ~48: 3+20+5+8+8).
const int receiptNameColumnChars = 20;
