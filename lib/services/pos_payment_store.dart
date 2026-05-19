import '../core/storage.dart';
import '../models/pos_payment_record.dart';

class PosPaymentStore {
  PosPaymentStore(this._storage);

  final Storage _storage;

  PosPaymentRecord? get(int saleId) {
    final all = _storage.posPaymentsJson;
    final raw = all['$saleId'];
    if (raw is! Map<String, dynamic>) return null;
    return PosPaymentRecord.fromJson(raw);
  }

  Future<void> save(int saleId, PosPaymentRecord record) async {
    final all = Map<String, dynamic>.from(_storage.posPaymentsJson);
    all['$saleId'] = record.toJson();
    await _storage.setPosPaymentsJson(all);
  }

  Future<void> remove(int saleId) async {
    final all = Map<String, dynamic>.from(_storage.posPaymentsJson);
    all.remove('$saleId');
    await _storage.setPosPaymentsJson(all);
  }
}
