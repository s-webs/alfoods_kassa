import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  static const _keyBaseUrl = 'base_url';
  static const _keyToken = 'token';
  static const _keyUser = 'user';
  static const _keyReceiptPrinterName = 'receipt_printer_name';
  static const _keyReceiptPrintMode = 'receipt_print_mode';
  static const _keyLabelTemplate = 'label_template';
  static const _keyPriceTagTemplate = 'price_tag_template';

  final SharedPreferences _prefs;

  Storage(this._prefs);

  static Future<Storage> init() async {
    final prefs = await SharedPreferences.getInstance();
    return Storage(prefs);
  }

  String? get baseUrl => _prefs.getString(_keyBaseUrl);
  Future<void> setBaseUrl(String url) => _prefs.setString(_keyBaseUrl, url);

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

  /// Тип печати: 'raw', 'pdf' или 'pdf_direct'. По умолчанию 'raw'.
  /// - 'raw' - RAW печать на термопринтер
  /// - 'pdf' - обычная печать через системный диалог
  /// - 'pdf_direct' - прямая печать PDF без диалога
  String get receiptPrintMode => _prefs.getString(_keyReceiptPrintMode) ?? 'raw';
  Future<void> setReceiptPrintMode(String mode) async {
    await _prefs.setString(_keyReceiptPrintMode, mode);
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

  Future<void> clearAuth() async {
    await _prefs.remove(_keyToken);
    await _prefs.remove(_keyUser);
  }

  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
