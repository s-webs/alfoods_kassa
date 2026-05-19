import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../core/storage.dart';

class KaspiPosException implements Exception {
  KaspiPosException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class KaspiPosTokens {
  const KaspiPosTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expirationDate,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expirationDate;

  factory KaspiPosTokens.fromData(Map<String, dynamic> data) {
    return KaspiPosTokens(
      accessToken: data['accessToken']?.toString() ?? '',
      refreshToken: data['refreshToken']?.toString() ?? '',
      expirationDate: _parseExpiration(data['expirationDate']),
    );
  }

  static DateTime _parseExpiration(dynamic v) {
    if (v == null) return DateTime.now();
    final s = v.toString().trim();
    final parsed = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (parsed != null) return parsed;
    return DateTime.now();
  }
}

class KaspiPosDeviceInfo {
  const KaspiPosDeviceInfo({
    required this.posNum,
    required this.serialNum,
    required this.terminalId,
  });

  final String posNum;
  final String serialNum;
  final String terminalId;

  factory KaspiPosDeviceInfo.fromData(Map<String, dynamic> data) {
    return KaspiPosDeviceInfo(
      posNum: data['posNum']?.toString() ?? '',
      serialNum: data['serialNum']?.toString() ?? '',
      terminalId: data['terminalId']?.toString() ?? '',
    );
  }
}

class KaspiPosProcessStart {
  const KaspiPosProcessStart({
    required this.processId,
    required this.status,
  });

  final String processId;
  final String status;
}

class KaspiPosProcessStatus {
  const KaspiPosProcessStatus({
    required this.processId,
    required this.status,
    this.subStatus,
    this.message,
    this.method,
    this.transactionId,
    this.chequeInfo,
  });

  final String processId;
  final String status;
  final String? subStatus;
  final String? message;
  final String? method;
  final String? transactionId;
  final Map<String, dynamic>? chequeInfo;

  bool get isFinished =>
      status == 'success' || status == 'fail' || status == 'unknown';

  factory KaspiPosProcessStatus.fromData(Map<String, dynamic> data) {
    Map<String, dynamic>? cheque;
    final rawCheque = data['chequeInfo'];
    if (rawCheque is Map<String, dynamic>) {
      cheque = rawCheque;
    } else if (rawCheque is Map) {
      cheque = Map<String, dynamic>.from(rawCheque);
    }

    String? method = data['method']?.toString();
    if ((method == null || method.isEmpty) && cheque != null) {
      method = cheque['method']?.toString();
    }

    return KaspiPosProcessStatus(
      processId: data['processId']?.toString() ?? '',
      status: data['status']?.toString() ?? '',
      subStatus: data['subStatus']?.toString(),
      message: data['message']?.toString(),
      method: method,
      transactionId: data['transactionId']?.toString(),
      chequeInfo: cheque,
    );
  }
}

class KaspiPosService {
  KaspiPosService(this._storage);

  final Storage _storage;
  Dio? _dio;
  DateTime? _lastActualizeAt;

  void _configureDio() {
    final host = _storage.posHost;
    if (host == null || host.isEmpty) {
      throw KaspiPosException('Не указан IP или DNS терминала в настройках');
    }
    final port = _storage.posPort;
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://$host:$port',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
      ),
    );
    if (_storage.posSkipSslVerify) {
      (_dio!.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    }
  }

  Dio get _client {
    _configureDio();
    return _dio!;
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool auth = true,
  }) async {
    final headers = <String, dynamic>{};
    if (auth) {
      await ensureValidToken();
      final token = _storage.posAccessToken;
      if (token == null || token.isEmpty) {
        throw KaspiPosException(
          'Касса не зарегистрирована на терминале. Выполните регистрацию в настройках.',
        );
      }
      headers['accesstoken'] = token;
    }
    try {
      final response = await _client.get(
        path,
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );
      return _parseBody(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw KaspiPosException(
          'Сессия терминала истекла. Обновите токен или зарегистрируйте кассу заново.',
        );
      }
      final msg = e.message ?? e.toString();
      throw KaspiPosException('Ошибка связи с терминалом: $msg');
    }
  }

  Map<String, dynamic> _parseBody(dynamic body) {
    if (body is! Map<String, dynamic>) {
      throw KaspiPosException('Некорректный ответ терминала');
    }
    final statusCode = body['statusCode'];
    if (statusCode is int && statusCode != 0) {
      final data = body['data'];
      String detail = body['errorText']?.toString() ?? 'Ошибка терминала';
      if (data is Map && data['message'] != null) {
        detail = '${data['message']} ($detail)';
      }
      throw KaspiPosException(detail, statusCode: statusCode);
    }
    final data = body['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<void> ensureValidToken() async {
    final expirationStr = _storage.posTokenExpiration;
    if (expirationStr == null || expirationStr.isEmpty) return;

    final expiration = DateTime.tryParse(
      expirationStr.replaceFirst(' ', 'T'),
    );
    if (expiration == null) return;

    if (DateTime.now().isBefore(expiration.subtract(const Duration(minutes: 30)))) {
      return;
    }

    final refresh = _storage.posRefreshToken;
    final name = _storage.posRegisterName;
    if (refresh == null ||
        refresh.isEmpty ||
        name == null ||
        name.isEmpty) {
      return;
    }
    await revoke(name: name, refreshToken: refresh);
  }

  Future<KaspiPosTokens> register({required String name}) async {
    final data = await _get(
      '/v2/register',
      queryParameters: {'name': name},
      auth: false,
    );
    final tokens = KaspiPosTokens.fromData(data);
    await _persistTokens(tokens);
    return tokens;
  }

  Future<KaspiPosTokens> revoke({
    required String name,
    required String refreshToken,
  }) async {
    final data = await _get(
      '/v2/revoke',
      queryParameters: {'name': name, 'refreshToken': refreshToken},
      auth: false,
    );
    final tokens = KaspiPosTokens.fromData(data);
    await _persistTokens(tokens);
    return tokens;
  }

  Future<void> _persistTokens(KaspiPosTokens tokens) async {
    await _storage.setPosAccessToken(tokens.accessToken);
    await _storage.setPosRefreshToken(tokens.refreshToken);
    await _storage.setPosTokenExpiration(
      tokens.expirationDate.toIso8601String(),
    );
  }

  Future<KaspiPosDeviceInfo> deviceInfo() async {
    final data = await _get('/v2/deviceinfo');
    final info = KaspiPosDeviceInfo.fromData(data);
    if (info.terminalId.isNotEmpty) {
      await _storage.setPosTerminalId(info.terminalId);
    }
    return info;
  }

  Future<KaspiPosProcessStart> startPayment(
    int amount, {
    bool ownCheque = true,
  }) async {
    final data = await _get(
      '/v2/payment',
      queryParameters: {
        'amount': amount,
        if (ownCheque) 'owncheque': 'true',
      },
    );
    return KaspiPosProcessStart(
      processId: data['processId']?.toString() ?? '',
      status: data['status']?.toString() ?? 'wait',
    );
  }

  Future<KaspiPosProcessStart> startRefund({
    required int amount,
    required String method,
    required String transactionId,
    bool ownCheque = true,
  }) async {
    final data = await _get(
      '/v2/refund',
      queryParameters: {
        'amount': amount,
        'method': method,
        'transactionId': transactionId,
        if (ownCheque) 'owncheque': 'true',
      },
    );
    return KaspiPosProcessStart(
      processId: data['processId']?.toString() ?? '',
      status: data['status']?.toString() ?? 'wait',
    );
  }

  Future<KaspiPosProcessStatus> getStatus(String processId) async {
    await ensureValidToken();
    final terminalId = await _resolveTerminalId();
    final token = _storage.posAccessToken;
    if (token == null || token.isEmpty) {
      throw KaspiPosException(
        'Касса не зарегистрирована на терминале. Выполните регистрацию в настройках.',
      );
    }
    try {
      final response = await _client.get(
        '/v2/status',
        queryParameters: {'processId': processId},
        options: Options(
          headers: {
            'accesstoken': token,
            'terminalId': terminalId,
          },
        ),
      );
      final parsed = _parseBody(response.data);
      return KaspiPosProcessStatus.fromData(parsed);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw KaspiPosException(
          'Сессия терминала истекла. Обновите токен или зарегистрируйте кассу заново.',
        );
      }
      throw KaspiPosException('Ошибка связи с терминалом: ${e.message}');
    }
  }

  Future<String> _resolveTerminalId() async {
    var terminalId = _storage.posTerminalId;
    if (terminalId != null && terminalId.isNotEmpty) return terminalId;
    final info = await deviceInfo();
    return info.terminalId;
  }

  Future<KaspiPosProcessStatus> actualize(String processId) async {
    final now = DateTime.now();
    if (_lastActualizeAt != null &&
        now.difference(_lastActualizeAt!) < const Duration(seconds: 10)) {
      throw KaspiPosException(
        'Подождите 10 секунд перед повторной актуализацией',
      );
    }
    _lastActualizeAt = now;
    await ensureValidToken();
    final token = _storage.posAccessToken;
    try {
      final response = await _client.get(
        '/v2/actualize',
        queryParameters: {'processId': processId},
        options: Options(headers: {'accesstoken': token}),
      );
      final parsed = _parseBody(response.data);
      return KaspiPosProcessStatus.fromData(parsed);
    } on DioException catch (e) {
      throw KaspiPosException('Ошибка актуализации: ${e.message}');
    }
  }

  Future<KaspiPosProcessStatus> pollUntilFinished(
    String processId, {
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 200),
    void Function(KaspiPosProcessStatus status)? onUpdate,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await getStatus(processId);
      onUpdate?.call(status);
      if (status.isFinished) return status;
      await Future<void>.delayed(interval);
    }
    throw KaspiPosException('Превышено время ожидания ответа терминала');
  }
}
