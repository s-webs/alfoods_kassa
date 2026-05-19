class PosTransactionDto {
  const PosTransactionDto({
    required this.method,
    required this.transactionId,
    required this.amount,
    this.processId,
    this.paidAt,
  });

  final String method;
  final String transactionId;
  final double amount;
  final String? processId;
  final DateTime? paidAt;

  Map<String, dynamic> toJson() => {
        'method': method,
        'transaction_id': transactionId,
        'amount': amount,
        if (processId != null && processId!.isNotEmpty) 'process_id': processId,
        if (paidAt != null) 'paid_at': paidAt!.toIso8601String(),
      };
}
