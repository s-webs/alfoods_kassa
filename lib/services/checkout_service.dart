import '../models/pos_transaction_dto.dart';
import '../models/sale_create_result.dart';
import '../models/sale_payment_method.dart';
import 'api_service.dart';
import 'api_webkassa_exception.dart';

class CheckoutService {
  CheckoutService(this._apiService);

  final ApiService _apiService;

  Future<SaleCreateResult> finalizeOfdSale({
    required int cashierId,
    required int shiftId,
    required List<Map<String, dynamic>> items,
    required SalePaymentMethod paymentMethod,
    int? draftSaleId,
    PosTransactionDto? posTransaction,
    String? customerXin,
    String? externalCheckNumber,
  }) async {
    await _deleteDraftIfAny(draftSaleId);

    try {
      return await _apiService.createSale(
        cashierId: cashierId,
        shiftId: shiftId,
        items: items,
        paymentMethod: paymentMethod,
        customerXin: customerXin,
        externalCheckNumber: externalCheckNumber,
        posTransaction: posTransaction?.toJson(),
      );
    } on ApiWebkassaException {
      rethrow;
    }
  }

  Future<SaleCreateResult> finalizeNonOfdSale({
    required int? cashierId,
    required int shiftId,
    required List<Map<String, dynamic>> items,
    required SalePaymentMethod paymentMethod,
    int? draftSaleId,
  }) async {
    await _deleteDraftIfAny(draftSaleId);

    return _apiService.createSale(
      cashierId: cashierId,
      shiftId: shiftId,
      items: items,
      paymentMethod: paymentMethod,
    );
  }

  Future<void> _deleteDraftIfAny(int? draftSaleId) async {
    if (draftSaleId != null) {
      try {
        await _apiService.deleteSale(draftSaleId);
      } catch (_) {
        // Best effort: draft may already be deleted.
      }
    }
  }
}
