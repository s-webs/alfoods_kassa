import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  static const _keyBaseUrl = 'base_url';
  static const _keyCentrifugoWsUrl = 'centrifugo_ws_url';
  static const _keyCentrifugoToken = 'centrifugo_token';
  static const _keyToken = 'token';
  static const _keyUser = 'user';
  static const _keyReceiptPrinterName = 'receipt_printer_name';
  static const _keyReceiptPrintMode = 'receipt_print_mode';
  static const _keyReceiptRawEncoding = 'receipt_raw_encoding';
  static const _keyReceiptRawXprinterPreamble = 'receipt_raw_xprinter_preamble';
  static const _keyLabelTemplate = 'label_template';
  static const _keyPriceTagTemplate = 'price_tag_template';
  static const _keyEntrepreneurName = 'entrepreneur_name';
  static const _keyEntrepreneurBin = 'entrepreneur_bin';
  static const _keyEntrepreneurManager = 'entrepreneur_manager';
  static const _keyEntrepreneurAddress = 'entrepreneur_address';
  static const _keyTimeOffsetMs = 'time_offset_ms';
  static const _keyTimeLastSyncMs = 'time_last_sync_ms';
  static const _keyWaybillAiModel = 'waybill_ai_model';
  static const _keyWaybillAiApiKey = 'waybill_ai_api_key';
  static const _keyPosHost = 'pos_host';
  static const _keyPosPort = 'pos_port';
  static const _keyPosRegisterName = 'pos_register_name';
  static const _keyPosAccessToken = 'pos_access_token';
  static const _keyPosRefreshToken = 'pos_refresh_token';
  static const _keyPosTokenExpiration = 'pos_token_expiration';
  static const _keyPosTerminalId = 'pos_terminal_id';
  static const _keyPosSkipSslVerify = 'pos_skip_ssl_verify';
  static const _keyPosPaymentsJson = 'pos_payments_json';
  static const _keySelectedCashierId = 'selected_cashier_id';
  static const _keyRememberedCustomerXin = 'remembered_customer_xin';

  final SharedPreferences _prefs;

  Storage(this._prefs);

  static Future<Storage> init() async {
    final prefs = await SharedPreferences.getInstance();
    return Storage(prefs);
  }

  String? get baseUrl => _prefs.getString(_keyBaseUrl);
  Future<void> setBaseUrl(String url) => _prefs.setString(_keyBaseUrl, url);

  /// WebSocket URL for Centrifugo. If null, derived from baseUrl (same host, path /connection/websocket).
  String? get centrifugoWsUrl => _prefs.getString(_keyCentrifugoWsUrl);
  Future<void> setCentrifugoWsUrl(String? url) async {
    if (url == null || url.isEmpty) {
      await _prefs.remove(_keyCentrifugoWsUrl);
    } else {
      await _prefs.setString(_keyCentrifugoWsUrl, url);
    }
  }

  /// JWT for Centrifugo connection (from login response).
  String? get centrifugoToken => _prefs.getString(_keyCentrifugoToken);
  Future<void> setCentrifugoToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _prefs.remove(_keyCentrifugoToken);
    } else {
      await _prefs.setString(_keyCentrifugoToken, token);
    }
  }

  String? get token => _prefs.getString(_keyToken);
  Future<void> setToken(String token) => _prefs.setString(_keyToken, token);

  Map<String, dynamic>? get user {
    final json = _prefs.getString(_keyUser);
    if (json == null) return null;
    return jsonDecode(json) as Map<String, dynamic>?;
  }

  Future<void> setUser(Map<String, dynamic>? user) async {
    if (user == null) {
      await _prefs.remove(_keyUser);
    } else {
      await _prefs.setString(_keyUser, jsonEncode(user));
    }
  }

  String? get receiptPrinterName => _prefs.getString(_keyReceiptPrinterName);
  Future<void> setReceiptPrinterName(String? name) async {
    if (name == null) {
      await _prefs.remove(_keyReceiptPrinterName);
    } else {
      await _prefs.setString(_keyReceiptPrinterName, name);
    }
  }

  /// Тип печати: 'raw', 'pdf', 'pdf_direct' или 'native'. По умолчанию 'raw'.
  /// - 'raw' - RAW печать на термопринтер
  /// - 'pdf' - обычная печать через системный диалог
  /// - 'pdf_direct' - прямая печать PDF без диалога
  /// - 'native' - прямая печать через Windows GDI (растр, без RAW/PDF)
  String get receiptPrintMode => _prefs.getString(_keyReceiptPrintMode) ?? 'raw';
  Future<void> setReceiptPrintMode(String mode) async {
    await _prefs.setString(_keyReceiptPrintMode, mode);
  }

  /// Кодировка RAW-чека: идентификатор, задающий пару (кодовая страница ESC/POS + кодировка текста).
  /// - 'cp866_17'  — ESC t 17, CP866 (DOS Cyrillic) — стандарт ESC/POS
  /// - 'cp1251_22' — ESC t 22, Windows-1251 — для принтеров, не реагирующих на CP866
  /// - 'cp866_25'  — ESC t 25, CP866 — альтернативная нумерация у некоторых производителей
  String get receiptRawEncoding =>
      _prefs.getString(_keyReceiptRawEncoding) ?? 'cp866_17';
  Future<void> setReceiptRawEncoding(String value) async {
    await _prefs.setString(_keyReceiptRawEncoding, value);
  }

  /// Преамбула для Xprinter/клонов: убирает «китайский» режим парных байтов при RAW-печати.
  /// Включите, если вместо кириллицы печатаются иероглифы (при корректной кодировке в списке выше).
  bool get receiptRawXprinterPreamble =>
      _prefs.getBool(_keyReceiptRawXprinterPreamble) ?? false;
  Future<void> setReceiptRawXprinterPreamble(bool value) async {
    await _prefs.setBool(_keyReceiptRawXprinterPreamble, value);
  }

  /// Макет этикетки по умолчанию (JSON).
  Map<String, dynamic>? get labelTemplateJson {
    final s = _prefs.getString(_keyLabelTemplate);
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>?;
  }

  Future<void> setLabelTemplateJson(Map<String, dynamic>? json) async {
    if (json == null) {
      await _prefs.remove(_keyLabelTemplate);
    } else {
      await _prefs.setString(_keyLabelTemplate, jsonEncode(json));
    }
  }

  /// Макет ценника по умолчанию (JSON).
  Map<String, dynamic>? get priceTagTemplateJson {
    final s = _prefs.getString(_keyPriceTagTemplate);
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>?;
  }

  Future<void> setPriceTagTemplateJson(Map<String, dynamic>? json) async {
    if (json == null) {
      await _prefs.remove(_keyPriceTagTemplate);
    } else {
      await _prefs.setString(_keyPriceTagTemplate, jsonEncode(json));
    }
  }

  String? get entrepreneurName => _prefs.getString(_keyEntrepreneurName);
  Future<void> setEntrepreneurName(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_keyEntrepreneurName);
    } else {
      await _prefs.setString(_keyEntrepreneurName, value);
    }
  }

  String? get entrepreneurBin => _prefs.getString(_keyEntrepreneurBin);
  Future<void> setEntrepreneurBin(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_keyEntrepreneurBin);
    } else {
      await _prefs.setString(_keyEntrepreneurBin, value);
    }
  }

  String? get entrepreneurManager => _prefs.getString(_keyEntrepreneurManager);
  Future<void> setEntrepreneurManager(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_keyEntrepreneurManager);
    } else {
      await _prefs.setString(_keyEntrepreneurManager, value);
    }
  }

  String? get entrepreneurAddress => _prefs.getString(_keyEntrepreneurAddress);
  Future<void> setEntrepreneurAddress(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_keyEntrepreneurAddress);
    } else {
      await _prefs.setString(_keyEntrepreneurAddress, value);
    }
  }

  int get timeOffsetMs => _prefs.getInt(_keyTimeOffsetMs) ?? 0;
  Future<void> setTimeOffsetMs(int value) => _prefs.setInt(_keyTimeOffsetMs, value);

  // --- Waybill AI settings ---

  /// Model name for OpenAI. Default: gpt-4.1-mini.
  String? get waybillAiModel => _prefs.getString(_keyWaybillAiModel);
  Future<void> setWaybillAiModel(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_keyWaybillAiModel);
    } else {
      await _prefs.setString(_keyWaybillAiModel, value);
    }
  }

  /// OpenAI API key (only used when provider == 'openai').
  String? get waybillAiApiKey => _prefs.getString(_keyWaybillAiApiKey);
  Future<void> setWaybillAiApiKey(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_keyWaybillAiApiKey);
    } else {
      await _prefs.setString(_keyWaybillAiApiKey, value);
    }
  }

  int? get timeLastSyncMs => _prefs.getInt(_keyTimeLastSyncMs);
  Future<void> setTimeLastSyncMs(int value) => _prefs.setInt(_keyTimeLastSyncMs, value);

  // --- Kaspi Smart POS ---

  String? get posHost => _prefs.getString(_keyPosHost);
  Future<void> setPosHost(String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _prefs.remove(_keyPosHost);
    } else {
      await _prefs.setString(_keyPosHost, value.trim());
    }
  }

  int get posPort => _prefs.getInt(_keyPosPort) ?? 8080;
  Future<void> setPosPort(int value) => _prefs.setInt(_keyPosPort, value);

  String? get posRegisterName => _prefs.getString(_keyPosRegisterName);
  Future<void> setPosRegisterName(String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _prefs.remove(_keyPosRegisterName);
    } else {
      await _prefs.setString(_keyPosRegisterName, value.trim());
    }
  }

  String? get posAccessToken => _prefs.getString(_keyPosAccessToken);
  Future<void> setPosAccessToken(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_keyPosAccessToken);
    } else {
      await _prefs.setString(_keyPosAccessToken, value);
    }
  }

  String? get posRefreshToken => _prefs.getString(_keyPosRefreshToken);
  Future<void> setPosRefreshToken(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_keyPosRefreshToken);
    } else {
      await _prefs.setString(_keyPosRefreshToken, value);
    }
  }

  String? get posTokenExpiration => _prefs.getString(_keyPosTokenExpiration);
  Future<void> setPosTokenExpiration(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_keyPosTokenExpiration);
    } else {
      await _prefs.setString(_keyPosTokenExpiration, value);
    }
  }

  String? get posTerminalId => _prefs.getString(_keyPosTerminalId);
  Future<void> setPosTerminalId(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_keyPosTerminalId);
    } else {
      await _prefs.setString(_keyPosTerminalId, value);
    }
  }

  bool get posSkipSslVerify => _prefs.getBool(_keyPosSkipSslVerify) ?? false;
  Future<void> setPosSkipSslVerify(bool value) async {
    await _prefs.setBool(_keyPosSkipSslVerify, value);
  }

  Map<String, dynamic> get posPaymentsJson {
    final s = _prefs.getString(_keyPosPaymentsJson);
    if (s == null) return {};
    final decoded = jsonDecode(s);
    if (decoded is Map<String, dynamic>) return decoded;
    return {};
  }

  Future<void> setPosPaymentsJson(Map<String, dynamic> json) async {
    if (json.isEmpty) {
      await _prefs.remove(_keyPosPaymentsJson);
    } else {
      await _prefs.setString(_keyPosPaymentsJson, jsonEncode(json));
    }
  }

  bool get isPosConfigured =>
      posHost != null &&
      posHost!.isNotEmpty &&
      posAccessToken != null &&
      posAccessToken!.isNotEmpty;

  int? get selectedCashierId => _prefs.getInt(_keySelectedCashierId);

  Future<void> setSelectedCashierId(int? id) async {
    if (id == null) {
      await _prefs.remove(_keySelectedCashierId);
    } else {
      await _prefs.setInt(_keySelectedCashierId, id);
    }
  }

  String? get rememberedCustomerXin =>
      _prefs.getString(_keyRememberedCustomerXin);

  Future<void> setRememberedCustomerXin(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_keyRememberedCustomerXin);
    } else {
      await _prefs.setString(_keyRememberedCustomerXin, value);
    }
  }

  Future<void> clearAuth() async {
    await _prefs.remove(_keyToken);
    await _prefs.remove(_keyUser);
    await _prefs.remove(_keyCentrifugoWsUrl);
    await _prefs.remove(_keyCentrifugoToken);
    await _prefs.remove(_keySelectedCashierId);
  }

  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
