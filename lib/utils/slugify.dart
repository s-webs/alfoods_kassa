/// Simple slugify: lowercase, replace spaces with hyphens, remove non-alphanumeric.
/// For Cyrillic, uses basic transliteration.
String slugify(String text) {
  if (text.isEmpty) return '';
  const Map<String, String> cyrillicToLatin = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo',
    'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
    'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
    'ф': 'f', 'х': 'h', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
    'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
  };
  var result = text.toLowerCase().trim();
  final buffer = StringBuffer();
  for (var i = 0; i < result.length; i++) {
    final char = result[i];
    if (cyrillicToLatin.containsKey(char)) {
      buffer.write(cyrillicToLatin[char]);
    } else if (RegExp(r'[a-z0-9\-]').hasMatch(char)) {
      buffer.write(char);
    } else if (char == ' ' || char == '_') {
      if (buffer.isNotEmpty && !buffer.toString().endsWith('-')) {
        buffer.write('-');
      }
    }
  }
  var s = buffer.toString();
  s = s.replaceAll(RegExp(r'-+'), '-');
  s = s.replaceAll(RegExp(r'^-+|-+$'), '');
  return s;
}
