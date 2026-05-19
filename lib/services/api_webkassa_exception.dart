import 'package:dio/dio.dart';

import '../models/fiscal_receipt.dart';

class ApiWebkassaException implements Exception {
  ApiWebkassaException({
    required this.message,
    this.webkassaCode,
    this.httpStatus,
    this.fiscal,
  });

  final String message;
  final int? webkassaCode;
  final int? httpStatus;
  final FiscalReceipt? fiscal;

  @override
  String toString() => message;

  factory ApiWebkassaException.fromDio(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final msg = data['message']?.toString() ?? 'Ошибка WebKassa';
      final code = data['webkassa_code'];
      FiscalReceipt? fiscal;
      if (data['fiscal'] is Map<String, dynamic>) {
        fiscal = FiscalReceipt.fromJson(
          data['fiscal'] as Map<String, dynamic>,
        );
      }
      return ApiWebkassaException(
        message: msg,
        webkassaCode: code is int ? code : int.tryParse(code?.toString() ?? ''),
        httpStatus: status,
        fiscal: fiscal,
      );
    }
    return ApiWebkassaException(
      message: e.message ?? 'Ошибка сети',
      httpStatus: status,
    );
  }
}
