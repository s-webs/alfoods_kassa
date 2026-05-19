class PosPaymentRecord {
  const PosPaymentRecord({
    required this.method,
    required this.transactionId,
    required this.amount,
    required this.processId,
    required this.paidAt,
  });

  final String method;
  final String transactionId;
  final int amount;
  final String processId;
  final DateTime paidAt;

  Map<String, dynamic> toJson() => {
        'method': method,
        'transaction_id': transactionId,
        'amount': amount,
        'process_id': processId,
        'paid_at': paidAt.toIso8601String(),
      };

  factory PosPaymentRecord.fromJson(Map<String, dynamic> json) {
    return PosPaymentRecord(
      method: json['method']?.toString() ?? '',
      transactionId: json['transaction_id']?.toString() ?? '',
      amount: _parseInt(json['amount']),
      processId: json['process_id']?.toString() ?? '',
      paidAt: json['paid_at'] != null
          ? DateTime.tryParse(json['paid_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
