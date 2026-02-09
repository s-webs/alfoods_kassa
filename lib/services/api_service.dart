import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/storage.dart';
import '../models/category.dart';
import '../models/cashier.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/shift.dart';
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

  Future<List<Product>> getProducts({bool? active, int? categoryId}) async {
    final queryParams = <String, dynamic>{};
    if (active != null) queryParams['active'] = active;
    if (categoryId != null) queryParams['category_id'] = categoryId;
    final response = await _apiClient.dio.get(
      'api/products',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
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
    required List<Map<String, dynamic>> items,
  }) async {
    final response = await _apiClient.dio.post(
      'api/sales',
      data: {
        'cashier_id': cashierId,
        'shift_id': shiftId,
        'items': items,
      },
    );
    return Sale.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Sale> updateSale(int id,
      {int? cashierId, int? shiftId, int? shopperId}) async {
    final data = <String, dynamic>{};
    if (cashierId != null) data['cashier_id'] = cashierId;
    if (shiftId != null) data['shift_id'] = shiftId;
    if (shopperId != null) data['shopper_id'] = shopperId;

    final response = await _apiClient.dio.patch(
      'api/sales/$id',
      data: data,
    );
    return Sale.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteSale(int id) async {
    await _apiClient.dio.delete('api/sales/$id');
  }
}

class LoginResult {
  final String token;
  final User user;

  LoginResult({required this.token, required this.user});
}
