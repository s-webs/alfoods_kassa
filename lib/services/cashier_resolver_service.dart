import '../core/storage.dart';
import '../models/cashier.dart';
import 'api_service.dart';

class CashierResolverService {
  CashierResolverService(this._storage);

  final Storage _storage;

  Future<int?> resolveCashierId(ApiService apiService) async {
    final cached = _storage.selectedCashierId;
    if (cached != null) {
      return cached;
    }

    final userId = _parseUserId(_storage.user?['id']);
    if (userId == null) {
      return null;
    }

    final cashiers = await apiService.getCashiers();
    final match = cashiers
        .where((c) => c.enabled && c.userId == userId)
        .toList();

    if (match.isEmpty) {
      return null;
    }

    final id = match.first.id;
    await _storage.setSelectedCashierId(id);
    return id;
  }

  Future<void> refreshCashierId(ApiService apiService) async {
    await _storage.setSelectedCashierId(null);
    await resolveCashierId(apiService);
  }

  Cashier? findCashierForUser(List<Cashier> cashiers) {
    final userId = _parseUserId(_storage.user?['id']);
    if (userId == null) {
      return null;
    }
    for (final c in cashiers) {
      if (c.enabled && c.userId == userId) {
        return c;
      }
    }
    return null;
  }

  int? _parseUserId(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
