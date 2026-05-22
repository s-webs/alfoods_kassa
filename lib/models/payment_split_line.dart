import 'sale_payment_method.dart';

/// Строка смешанной оплаты: способ + сумма.
class PaymentSplitLine {
  PaymentSplitLine({
    required this.method,
    required this.amount,
  });

  SalePaymentMethod method;
  double amount;

  Map<String, dynamic> toApiJson() => {
        'method': method.apiValue,
        'sum': amount,
      };
}
