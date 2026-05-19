import 'package:alfoods_kassa/models/fiscal_receipt.dart';
import 'package:alfoods_kassa/models/sale_create_result.dart';
import 'package:alfoods_kassa/models/webkassa_payment_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses wrapped sale and fiscal response', () {
    final result = SaleCreateResult.fromResponse({
      'sale': {
        'id': 1,
        'shift_id': 2,
        'items': [],
        'total_qty': 1,
        'total_price': 500,
        'fiscal_status': 'fiscalized',
        'ticket_url': 'https://my.webkassa.kz/t/1',
        'created_at': '2026-05-18T12:00:00.000000Z',
      },
      'fiscal': {
        'check_number': 'FISC-1',
        'ticket_url': 'https://my.webkassa.kz/t/1',
        'offline_mode': false,
      },
    });

    expect(result.sale.id, 1);
    expect(result.sale.fiscalStatus, 'fiscalized');
    expect(result.fiscal?.checkNumber, 'FISC-1');
    expect(result.fiscal?.offlineMode, false);
  });

  test('parses legacy flat sale response', () {
    final result = SaleCreateResult.fromResponse({
      'id': 5,
      'items': [],
      'total_qty': 0,
      'total_price': 0,
      'created_at': '2026-05-18T12:00:00.000000Z',
    });

    expect(result.sale.id, 5);
    expect(result.fiscal, isNull);
  });

  test('payment type entries match backend contract', () {
    final cash = WebkassaPaymentType.entry(WebkassaPaymentType.cash, 1500);
    expect(cash['type'], 0);
    expect(cash['sum'], 1500);

    final card = WebkassaPaymentType.entry(WebkassaPaymentType.card, 99.5);
    expect(card['type'], 1);
    expect(card['sum'], 99.5);
  });

  test('fiscal receipt parses offline mode', () {
    final fiscal = FiscalReceipt.fromJson({
      'check_number': 'X',
      'offline_mode': true,
    });
    expect(fiscal.offlineMode, true);
  });
}
