/// WebKassa payment types (Payments[].PaymentType).
class WebkassaPaymentType {
  WebkassaPaymentType._();

  static const int cash = 0;
  static const int card = 1;
  static const int mobile = 4;
  static const int credit = 3;

  static Map<String, dynamic> entry(int type, double sum) => {
        'type': type,
        'sum': sum,
      };
}
