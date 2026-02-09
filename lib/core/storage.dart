import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  static const _keyBaseUrl = 'base_url';
  static const _keyToken = 'token';
  static const _keyUser = 'user';

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

  Future<void> clearAuth() async {
    await _prefs.remove(_keyToken);
    await _prefs.remove(_keyUser);
  }

  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
