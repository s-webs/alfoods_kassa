class SalePosTransaction {
  const SalePosTransaction({
    required this.method,
    required this.transactionId,
    required this.amount,
    this.processId,
  });

  final String method;
  final String transactionId;
  final double amount;
  final String? processId;

  factory SalePosTransaction.fromJson(Map<String, dynamic> json) {
    return SalePosTransaction(
      method: json['method']?.toString() ?? '',
      transactionId: json['transaction_id']?.toString() ?? '',
      amount: _parseDouble(json['amount']),
      processId: json['process_id']?.toString(),
    );
  }

  static double _parseDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
