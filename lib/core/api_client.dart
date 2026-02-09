import 'package:dio/dio.dart';

import 'storage.dart';

class ApiClient {
  ApiClient(this._storage) {
    _initDio();
  }

  final Storage _storage;
  late Dio _dio;

  Dio get dio => _dio;

  void _initDio() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _storage.baseUrl ?? 'http://localhost',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _storage.token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            // Token expired or invalid - will be handled by caller
          }
          return handler.next(error);
        },
      ),
    );
  }

  void reconfigure() {
    _initDio();
  }

  bool get isConfigured => _storage.baseUrl != null && _storage.baseUrl!.isNotEmpty;
}
