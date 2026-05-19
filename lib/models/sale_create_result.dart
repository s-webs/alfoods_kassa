import 'fiscal_receipt.dart';
import 'sale.dart';

class SaleCreateResult {
  const SaleCreateResult({
    required this.sale,
    this.fiscal,
    this.printReceipt = false,
  });

  final Sale sale;
  final FiscalReceipt? fiscal;
  final bool printReceipt;

  factory SaleCreateResult.fromResponse(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw FormatException('Expected JSON object for sale response');
    }
    if (data['sale'] is Map<String, dynamic>) {
      final saleMap = data['sale'] as Map<String, dynamic>;
      FiscalReceipt? fiscal;
      if (data['fiscal'] is Map<String, dynamic>) {
        fiscal = FiscalReceipt.fromJson(
          data['fiscal'] as Map<String, dynamic>,
        );
      }
      final actions = data['actions'];
      final printReceipt = actions is Map && actions['print_receipt'] == true;

      return SaleCreateResult(
        sale: Sale.fromJson(saleMap),
        fiscal: fiscal,
        printReceipt: printReceipt,
      );
    }
    return SaleCreateResult(
      sale: Sale.fromJson(data),
      fiscal: null,
    );
  }
}
