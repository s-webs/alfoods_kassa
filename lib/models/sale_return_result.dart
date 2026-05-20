import 'fiscal_receipt.dart';
import 'sale.dart';

class SaleReturnResult {
  const SaleReturnResult({
    required this.returnSale,
    required this.originalSale,
    this.fiscal,
  });

  final Sale returnSale;
  final Sale originalSale;
  final FiscalReceipt? fiscal;

  factory SaleReturnResult.fromJson(Map<String, dynamic> json) {
    final saleJson = json['sale'] as Map<String, dynamic>?;
    final originalJson = json['original_sale'] as Map<String, dynamic>?;
    if (saleJson == null || originalJson == null) {
      throw FormatException('Invalid return sale response');
    }

    FiscalReceipt? fiscal;
    final fiscalJson = json['fiscal'];
    if (fiscalJson is Map<String, dynamic>) {
      fiscal = FiscalReceipt.fromJson(fiscalJson);
    }

    return SaleReturnResult(
      returnSale: Sale.fromJson(saleJson),
      originalSale: Sale.fromJson(originalJson),
      fiscal: fiscal,
    );
  }
}
