/// Фильтр PDF-отчёта по типу оплаты (query `payment_report`).
enum SalesPaymentReportFilter {
  nonFiscal('non_fiscal', 'Не фискализированные'),
  ofdAll('ofd_all', 'ОФД (все)'),
  ofdCash('ofd_cash', 'ОФД (наличные)'),
  ofdCard('ofd_card', 'ОФД (карта)'),
  ofdMobile('ofd_mobile', 'ОФД (мобильные)');

  const SalesPaymentReportFilter(this.apiValue, this.label);

  final String apiValue;
  final String label;

  String get fileSuffix => switch (this) {
        SalesPaymentReportFilter.nonFiscal => 'ne_fisk',
        SalesPaymentReportFilter.ofdAll => 'ofd_vse',
        SalesPaymentReportFilter.ofdCash => 'ofd_nal',
        SalesPaymentReportFilter.ofdCard => 'ofd_karta',
        SalesPaymentReportFilter.ofdMobile => 'ofd_mobil',
      };
}
