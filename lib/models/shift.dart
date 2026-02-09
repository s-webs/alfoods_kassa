class Shift {
  final int id;
  final DateTime openedAt;
  final DateTime? closedAt;

  const Shift({
    required this.id,
    required this.openedAt,
    this.closedAt,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    return Shift(
      id: json['id'] as int,
      openedAt: DateTime.parse(json['opened_at'] as String),
      closedAt: json['closed_at'] != null
          ? DateTime.parse(json['closed_at'] as String)
          : null,
    );
  }

  bool get isOpen => closedAt == null;
}
