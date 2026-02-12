class DebtPayment {
  final int id;
  final int saleId;
  final int counterpartyId;
  final double amount;
  final DateTime paymentDate;
  final String? notes;
  final DateTime createdAt;

  const DebtPayment({
    required this.id,
    required this.saleId,
    required this.counterpartyId,
    required this.amount,
    required this.paymentDate,
    this.notes,
    required this.createdAt,
  });

  factory DebtPayment.fromJson(Map<String, dynamic> json) {
    return DebtPayment(
      id: _parseInt(json['id']),
      saleId: _parseInt(json['sale_id']),
      counterpartyId: _parseInt(json['counterparty_id']),
      amount: _parseDouble(json['amount']),
      paymentDate: json['payment_date'] != null
          ? DateTime.parse(json['payment_date'].toString())
          : DateTime.now(),
      notes: json['notes']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
    );
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
