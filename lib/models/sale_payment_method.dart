/// Способ оплаты продажи (зеркало backend `SalePaymentMethod`).
enum SalePaymentMethod {
  cashOfd('cash_ofd'),
  cardOfd('card_ofd'),
  mobileOfd('mobile_ofd'),
  kaspiCard('kaspi_card'),
  kaspiQr('kaspi_qr'),
  payment('payment'),
  sell('sell');

  const SalePaymentMethod(this.apiValue);

  final String apiValue;

  bool get requiresFiscalization => switch (this) {
        SalePaymentMethod.payment || SalePaymentMethod.sell => false,
        _ => true,
      };

  bool get requiresKaspiTerminal => switch (this) {
        SalePaymentMethod.kaspiCard || SalePaymentMethod.kaspiQr => true,
        _ => false,
      };

  String get label => switch (this) {
        SalePaymentMethod.cashOfd => 'Наличные',
        SalePaymentMethod.cardOfd => 'Карта',
        SalePaymentMethod.mobileOfd => 'Мобильный',
        SalePaymentMethod.kaspiCard => 'Kaspi Карта',
        SalePaymentMethod.kaspiQr => 'Kaspi QR',
        SalePaymentMethod.payment => 'Оплата',
        SalePaymentMethod.sell => 'Продать',
      };
}
