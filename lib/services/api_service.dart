import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/storage.dart';
import '../models/category.dart';
import '../models/cashier.dart';
import '../models/counterparty.dart';
import '../models/debt_payment.dart';
import '../models/product.dart';
import '../models/product_receipt.dart';
import '../models/product_set.dart';
import '../models/sale.dart';
import '../models/shift.dart';
import '../models/task.dart';
import '../models/user.dart';

class ApiService {
  ApiService(this._storage, this._apiClient);

  final Storage _storage;
  final ApiClient _apiClient;

  /// Login with user-provided baseUrl (before it's saved to storage)
  Future<LoginResult> login({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    final response = await dio.post(
      'api/login',
      data: {'email': email, 'password': password},
    );

    final data = response.data as Map<String, dynamic>;
    final token = data['token'] as String;
    final userJson = data['user'] as Map<String, dynamic>;
    final user = User.fromJson(userJson);

    await _storage.setBaseUrl(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    await _storage.setToken(token);
    await _storage.setUser(userJson);
    _apiClient.reconfigure();

    return LoginResult(token: token, user: user);
  }

  Future<void> logout() async {
    try {
      if (_apiClient.isConfigured) {
        await _apiClient.dio.post('api/logout');
      }
    } catch (_) {
      // Ignore errors on logout
    } finally {
      await _storage.clearAuth();
    }
  }

  Future<List<Shift>> getShifts() async {
    final response = await _apiClient.dio.get('api/shifts');
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Shift.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Shift> createShift() async {
    final response = await _apiClient.dio.post(
      'api/shifts',
      data: {
        'opened_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    return Shift.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Shift> closeShift(int shiftId) async {
    final response = await _apiClient.dio.patch(
      'api/shifts/$shiftId',
      data: {
        'closed_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    return Shift.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<Cashier>> getCashiers() async {
    final response = await _apiClient.dio.get('api/cashiers');
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Cashier.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Category> createCategory(Map<String, dynamic> data) async {
    final response = await _apiClient.dio.post('api/categories', data: data);
    return Category.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Category> updateCategory(int id, Map<String, dynamic> data) async {
    final response =
        await _apiClient.dio.patch('api/categories/$id', data: data);
    return Category.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteCategory(int id) async {
    await _apiClient.dio.delete('api/categories/$id');
  }

  Future<List<Category>> getCategories({bool? active}) async {
    final queryParams = <String, dynamic>{};
    if (active != null) queryParams['active'] = active;
    final response = await _apiClient.dio.get(
      'api/categories',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Product> createProduct(Map<String, dynamic> data) async {
    final response = await _apiClient.dio.post('api/products', data: data);
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Product> updateProduct(int id, Map<String, dynamic> data) async {
    final response =
        await _apiClient.dio.patch('api/products/$id', data: data);
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteProduct(int id) async {
    await _apiClient.dio.delete('api/products/$id');
  }

  Future<Product> getProduct(int id) async {
    final response = await _apiClient.dio.get('api/products/$id');
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<Product>> getProducts({
    bool? active,
    int? categoryId,
    String? barcode,
  }) async {
    final queryParams = <String, dynamic>{};
    if (active != null) queryParams['active'] = active;
    if (categoryId != null) queryParams['category_id'] = categoryId;
    if (barcode != null && barcode.isNotEmpty) queryParams['barcode'] = barcode;
    final response = await _apiClient.dio.get(
      'api/products',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Поиск товара по штрихкоду (для сканера). Возвращает null, если не найден.
  Future<Product?> getProductByBarcode(String barcode) async {
    final list = await getProducts(active: true, barcode: barcode.trim());
    return list.isEmpty ? null : list.first;
  }

  Future<List<ProductSet>> getSets({
    bool? active,
    String? barcode,
  }) async {
    final queryParams = <String, dynamic>{};
    if (active != null) queryParams['active'] = active;
    if (barcode != null && barcode.isNotEmpty) queryParams['barcode'] = barcode;
    final response = await _apiClient.dio.get(
      'api/sets',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => ProductSet.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ProductSet> getSet(int id) async {
    final response = await _apiClient.dio.get('api/sets/$id');
    return ProductSet.fromJson(response.data as Map<String, dynamic>);
  }

  /// Поиск сета по штрихкоду. Возвращает null, если не найден.
  Future<ProductSet?> getSetByBarcode(String barcode) async {
    final list = await getSets(active: true, barcode: barcode.trim());
    return list.isEmpty ? null : list.first;
  }

  Future<ProductSet> createSet(Map<String, dynamic> data) async {
    final response = await _apiClient.dio.post('api/sets', data: data);
    return ProductSet.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProductSet> updateSet(int id, Map<String, dynamic> data) async {
    final response = await _apiClient.dio.patch('api/sets/$id', data: data);
    return ProductSet.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteSet(int id) async {
    await _apiClient.dio.delete('api/sets/$id');
  }

  Future<List<Sale>> getSales() async {
    final response = await _apiClient.dio.get('api/sales');
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Sale.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Sale> getSale(int id) async {
    final response = await _apiClient.dio.get('api/sales/$id');
    return Sale.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Sale> createSale({
    int? cashierId,
    int? shiftId,
    int? counterpartyId,
    bool isOnCredit = false,
    required List<Map<String, dynamic>> items,
  }) async {
    final response = await _apiClient.dio.post(
      'api/sales',
      data: {
        'cashier_id': cashierId,
        'shift_id': shiftId,
        'counterparty_id': counterpartyId,
        'is_on_credit': isOnCredit,
        'items': items,
      },
    );
    return Sale.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Sale> updateSale(int id, {
    int? cashierId,
    int? shiftId,
    int? shopperId,
    List<Map<String, dynamic>>? items,
  }) async {
    final data = <String, dynamic>{};
    if (cashierId != null) data['cashier_id'] = cashierId;
    if (shiftId != null) data['shift_id'] = shiftId;
    if (shopperId != null) data['shopper_id'] = shopperId;
    if (items != null) data['items'] = items;

    final response = await _apiClient.dio.patch(
      'api/sales/$id',
      data: data,
    );
    return Sale.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteSale(int id) async {
    await _apiClient.dio.delete('api/sales/$id');
  }

  /// Принять возврат: товары пополняют остатки. Опционально привязка к смене/кассиру.
  Future<void> acceptReturn({
    required List<Map<String, dynamic>> items,
    int? shiftId,
    int? cashierId,
  }) async {
    final data = <String, dynamic>{'items': items};
    if (shiftId != null) data['shift_id'] = shiftId;
    if (cashierId != null) data['cashier_id'] = cashierId;
    await _apiClient.dio.post('api/returns', data: data);
  }

  Future<Sale> returnSale(int id) async {
    final response = await _apiClient.dio.post('api/sales/$id/return');
    return Sale.fromJson(response.data as Map<String, dynamic>);
  }

  // Counterparties
  Future<List<Counterparty>> getCounterparties() async {
    final response = await _apiClient.dio.get('api/counterparties');
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Counterparty.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Counterparty> getCounterparty(int id) async {
    final response = await _apiClient.dio.get('api/counterparties/$id');
    return Counterparty.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Counterparty> createCounterparty(Map<String, dynamic> data) async {
    final response = await _apiClient.dio.post('api/counterparties', data: data);
    return Counterparty.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Counterparty> updateCounterparty(int id, Map<String, dynamic> data) async {
    final response = await _apiClient.dio.patch('api/counterparties/$id', data: data);
    return Counterparty.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteCounterparty(int id) async {
    await _apiClient.dio.delete('api/counterparties/$id');
  }

  // Product Receipts
  Future<List<ProductReceipt>> getProductReceipts() async {
    final response = await _apiClient.dio.get('api/product-receipts');
    final list = response.data as List<dynamic>;
    return list
        .map((e) => ProductReceipt.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ProductReceipt> getProductReceipt(int id) async {
    final response = await _apiClient.dio.get('api/product-receipts/$id');
    return ProductReceipt.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProductReceipt> createProductReceipt({
    int? counterpartyId,
    String? supplierName,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = <String, dynamic>{'items': items};
    if (counterpartyId != null) data['counterparty_id'] = counterpartyId;
    if (supplierName != null && supplierName.isNotEmpty) {
      data['supplier_name'] = supplierName;
    }
    final response = await _apiClient.dio.post('api/product-receipts', data: data);
    return ProductReceipt.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProductReceipt> updateProductReceipt(int id, {
    int? counterpartyId,
    String? supplierName,
    List<Map<String, dynamic>>? items,
  }) async {
    final data = <String, dynamic>{};
    if (counterpartyId != null) data['counterparty_id'] = counterpartyId;
    if (supplierName != null) data['supplier_name'] = supplierName;
    if (items != null) data['items'] = items;

    final response = await _apiClient.dio.patch('api/product-receipts/$id', data: data);
    return ProductReceipt.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteProductReceipt(int id) async {
    await _apiClient.dio.delete('api/product-receipts/$id');
  }

  // Debt Payments
  Future<List<DebtPayment>> getDebtPayments({
    int? saleId,
    int? counterpartyId,
  }) async {
    final queryParams = <String, dynamic>{};
    if (saleId != null) queryParams['sale_id'] = saleId;
    if (counterpartyId != null) queryParams['counterparty_id'] = counterpartyId;

    final response = await _apiClient.dio.get(
      'api/debt-payments',
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => DebtPayment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DebtPayment> createDebtPayment({
    required int saleId,
    required int counterpartyId,
    required double amount,
    required DateTime paymentDate,
    String? notes,
  }) async {
    final response = await _apiClient.dio.post(
      'api/debt-payments',
      data: {
        'sale_id': saleId,
        'counterparty_id': counterpartyId,
        'amount': amount,
        'payment_date': paymentDate.toIso8601String(),
        'notes': notes,
      },
    );
    return DebtPayment.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Sale> payDebt(int saleId, {
    required double amount,
    required DateTime paymentDate,
    String? notes,
  }) async {
    final response = await _apiClient.dio.post(
      'api/sales/$saleId/pay-debt',
      data: {
        'amount': amount,
        'payment_date': paymentDate.toIso8601String(),
        'notes': notes,
      },
    );
    return Sale.fromJson(response.data as Map<String, dynamic>);
  }

  // Debtors
  Future<List<Map<String, dynamic>>> getDebtors() async {
    final response = await _apiClient.dio.get('api/debtors');
    final list = response.data as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  /// Общая оплата долгов контрагента: сумма распределяется по неоплаченным продажам,
  /// начиная с самых старых.
  Future<Map<String, dynamic>> payDebtBulk(
    int counterpartyId, {
    required double amount,
    required DateTime paymentDate,
    String? notes,
  }) async {
    final response = await _apiClient.dio.post(
      'api/counterparties/$counterpartyId/pay-debt-bulk',
      data: {
        'amount': amount,
        'payment_date': paymentDate.toIso8601String(),
        'notes': notes,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  // Tasks
  Future<List<Task>> getTasks({DateTime? date, String? status}) async {
    final queryParams = <String, dynamic>{};
    if (date != null) {
      queryParams['date'] = date.toIso8601String().split('T')[0];
    }
    if (status != null && status.isNotEmpty) {
      queryParams['status'] = status;
    }
    final response = await _apiClient.dio.get(
      'api/tasks',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Task.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Task>> getTodayTasks() async {
    final response = await _apiClient.dio.get('api/tasks/today');
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Task.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Task> createTask({
    required String title,
    String? description,
    required DateTime dueDate,
    TaskStatus? status,
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'due_date': dueDate.toIso8601String().split('T')[0],
    };
    if (description != null && description.isNotEmpty) {
      data['description'] = description;
    }
    if (status != null) {
      data['status'] = status.value;
    }
    final response = await _apiClient.dio.post('api/tasks', data: data);
    return Task.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Task> updateTask(
    int id, {
    String? title,
    String? description,
    DateTime? dueDate,
    TaskStatus? status,
  }) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (description != null) data['description'] = description;
    if (dueDate != null) {
      data['due_date'] = dueDate.toIso8601String().split('T')[0];
    }
    if (status != null) data['status'] = status.value;
    final response = await _apiClient.dio.patch('api/tasks/$id', data: data);
    return Task.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteTask(int id) async {
    await _apiClient.dio.delete('api/tasks/$id');
  }
}

class LoginResult {
  final String token;
  final User user;

  LoginResult({required this.token, required this.user});
}
