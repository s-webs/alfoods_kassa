class Cashier {
  Cashier({
    required this.id,
    required this.name,
    this.userId,
    this.enabled = true,
  });

  final int id;
  final String name;
  final int? userId;
  final bool enabled;

  factory Cashier.fromJson(Map<String, dynamic> json) {
    return Cashier(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      userId: json['user_id'] as int?,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}
