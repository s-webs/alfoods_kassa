/// Способ оплаты продажи (зеркало backend `SalePaymentMethod`).
enum SalePaymentMethod {
  cashOfd('cash_ofd'),
  cardOfd('card_ofd'),
  mobileOfd('mobile_ofd'),
  kaspiCard('kaspi_card'),
  kaspiQr('kaspi_qr'),
  mixedOfd('mixed_ofd'),
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

  /// Способы для выпадающего списка смешанной оплаты.
  static const List<SalePaymentMethod> ofdCheckoutMethods = [
    SalePaymentMethod.cashOfd,
    SalePaymentMethod.cardOfd,
    SalePaymentMethod.mobileOfd,
    SalePaymentMethod.kaspiCard,
    SalePaymentMethod.kaspiQr,
  ];

  /// WebKassa Payments[].PaymentType (0 cash, 1 card, 4 mobile).
  int? get webkassaPaymentType => switch (this) {
        SalePaymentMethod.cashOfd => 0,
        SalePaymentMethod.cardOfd || SalePaymentMethod.kaspiCard => 1,
        SalePaymentMethod.mobileOfd || SalePaymentMethod.kaspiQr => 4,
        _ => null,
      };

  String? get paymentIconAsset => switch (this) {
        SalePaymentMethod.cashOfd => 'assets/payments_type/cash.png',
        SalePaymentMethod.cardOfd => 'assets/payments_type/card.png',
        SalePaymentMethod.mobileOfd => 'assets/payments_type/mobile.png',
        SalePaymentMethod.kaspiCard => 'assets/payments_type/kaspi_card.png',
        SalePaymentMethod.kaspiQr => 'assets/payments_type/kaspi_qr.png',
        _ => null,
      };

  static SalePaymentMethod? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final m in SalePaymentMethod.values) {
      if (m.apiValue == value) return m;
    }
    return null;
  }

  String get label => switch (this) {
        SalePaymentMethod.cashOfd => 'Наличные',
        SalePaymentMethod.cardOfd => 'Карта',
        SalePaymentMethod.mobileOfd => 'Мобильный',
        SalePaymentMethod.kaspiCard => 'Kaspi Карта',
        SalePaymentMethod.kaspiQr => 'Kaspi QR',
        SalePaymentMethod.mixedOfd => 'Смешанная',
        SalePaymentMethod.payment => 'Оплата',
        SalePaymentMethod.sell => 'Продать',
      };
}
