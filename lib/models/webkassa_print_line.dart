class WebkassaPrintLine {
  const WebkassaPrintLine({
    required this.order,
    required this.type,
    required this.value,
    required this.style,
  });

  /// 0 — текст, 1 — изображение (base64), 2 — QR.
  final int type;
  final int order;
  final String value;
  /// 0 — обычный, 1 — жирный.
  final int style;

  factory WebkassaPrintLine.fromJson(Map<String, dynamic> json) {
    return WebkassaPrintLine(
      order: _parseInt(json['Order'] ?? json['order']),
      type: _parseInt(json['Type'] ?? json['type']),
      value: json['Value']?.toString() ?? json['value']?.toString() ?? '',
      style: _parseInt(json['Style'] ?? json['style']),
    );
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
