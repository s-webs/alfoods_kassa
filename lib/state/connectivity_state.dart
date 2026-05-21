import 'dart:async';

import 'package:flutter/material.dart';

import '../models/connection_link_status.dart';
import '../services/api_service.dart';

/// Периодическая проверка связи с API и WebKassa.
class ConnectivityState extends ChangeNotifier {
  ConnectivityState(this._apiService);

  final ApiService _apiService;

  static const _pollInterval = Duration(seconds: 45);
  static const _requestTimeout = Duration(seconds: 10);

  Timer? _pollTimer;
  ConnectionLinkStatus _backendStatus = ConnectionLinkStatus.connecting;
  ConnectionLinkStatus _webkassaStatus = ConnectionLinkStatus.connecting;

  ConnectionLinkStatus get backendStatus => _backendStatus;
  ConnectionLinkStatus get webkassaStatus => _webkassaStatus;

  void start() {
    _pollTimer?.cancel();
    refresh();
    _pollTimer = Timer.periodic(_pollInterval, (_) => refresh());
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> refresh() async {
    await Future.wait([
      _refreshBackend(),
      _refreshWebkassa(),
    ]);
  }

  Future<void> _refreshBackend() async {
    _backendStatus = ConnectionLinkStatus.connecting;
    notifyListeners();
    _backendStatus = await _probeBackend()
        ? ConnectionLinkStatus.connected
        : ConnectionLinkStatus.disconnected;
    notifyListeners();
  }

  Future<void> _refreshWebkassa() async {
    _webkassaStatus = ConnectionLinkStatus.connecting;
    notifyListeners();
    _webkassaStatus = await _probeWebkassa()
        ? ConnectionLinkStatus.connected
        : ConnectionLinkStatus.disconnected;
    notifyListeners();
  }

  Future<bool> _probeBackend() async {
    try {
      await _apiService.pingBackend(
        receiveTimeout: _requestTimeout,
        sendTimeout: _requestTimeout,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _probeWebkassa() async {
    try {
      final health = await _apiService.getWebkassaHealth(
        receiveTimeout: _requestTimeout,
        sendTimeout: _requestTimeout,
      );
      return health['configured'] == true && health['token_present'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// Прокидывает [ConnectivityState] из Shell.
class ConnectivityStateScope extends InheritedWidget {
  const ConnectivityStateScope({
    super.key,
    required this.state,
    required super.child,
  });

  final ConnectivityState state;

  static ConnectivityState of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ConnectivityStateScope>();
    assert(scope != null, 'ConnectivityStateScope not found');
    return scope!.state;
  }

  @override
  bool updateShouldNotify(ConnectivityStateScope oldWidget) =>
      state != oldWidget.state;
}
