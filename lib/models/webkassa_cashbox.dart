class WebkassaCashbox {
  const WebkassaCashbox({
    required this.id,
    required this.cashboxUniqueNumber,
    required this.name,
    this.cashierId,
    this.isActive = true,
    this.cashierName,
  });

  final int id;
  final String cashboxUniqueNumber;
  final String name;
  final int? cashierId;
  final bool isActive;
  final String? cashierName;

  factory WebkassaCashbox.fromJson(Map<String, dynamic> json) {
    final cashier = json['cashier'];
    return WebkassaCashbox(
      id: json['id'] as int,
      cashboxUniqueNumber:
          json['cashbox_unique_number']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      cashierId: json['cashier_id'] as int?,
      isActive: json['is_active'] as bool? ?? true,
      cashierName: cashier is Map<String, dynamic>
          ? cashier['name']?.toString()
          : null,
    );
  }
}
