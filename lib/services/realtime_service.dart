import 'dart:async';
import 'dart:convert';

import 'package:centrifuge/centrifuge.dart';
import 'package:flutter/foundation.dart';

import '../core/storage.dart';

/// Payload for order or task push notification.
class RealtimeNotification {
  const RealtimeNotification({
    required this.type,
    required this.message,
    required this.data,
  });

  final String type; // 'order' | 'task'
  final String message;
  final Map<String, dynamic> data;
}

class RealtimeService {
  RealtimeService(this._storage);

  final Storage _storage;
  Client? _client;
  Subscription? _ordersSub;
  Subscription? _tasksSub;
  StreamSubscription<ServerPublicationEvent>? _pubSub;
  final _notificationController = StreamController<RealtimeNotification>.broadcast();

  /// Stream of push notifications (orders and tasks).
  Stream<RealtimeNotification> get notifications => _notificationController.stream;

  bool get isConnected =>
      _client != null && _client!.state == State.connected;

  /// WebSocket URL for Centrifugo. Uses [Storage.centrifugoWsUrl] if set,
  /// otherwise derives from [Storage.baseUrl] (same host, path /connection/websocket).
  String? get centrifugoWsUrl {
    final explicit = _storage.centrifugoWsUrl;
    if (explicit != null && explicit.isNotEmpty) return _normalizeWsUrl(explicit);
    final base = _storage.baseUrl;
    if (base == null || base.isEmpty) return null;
    String url = base.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (url.startsWith('https://')) {
      url = 'wss://${url.substring(8)}';
    } else if (url.startsWith('http://')) {
      url = 'ws://${url.substring(7)}';
    } else {
      return null;
    }
    return _normalizeWsUrl('$url/connection/websocket');
  }

  /// Removes invalid port :0 from host so wss://host:0/... becomes wss://host/...
  static String _normalizeWsUrl(String url) {
    return url.replaceFirst(':0/', '/');
  }

  /// Connect to Centrifugo and subscribe to orders and tasks. No-op if already connected or URL missing.
  Future<void> connect() async {
    if (_client != null) return;
    final url = centrifugoWsUrl;
    if (url == null || url.isEmpty) return;
    final apiToken = _storage.token;
    if (apiToken == null || apiToken.isEmpty) return;

    final wsUrl = url.contains('?') ? '$url&format=protobuf' : '$url?format=protobuf';
    final centrifugoToken = _storage.centrifugoToken ?? '';
    _client = createClient(
      wsUrl,
      ClientConfig(token: centrifugoToken),
    );
    _ordersSub = _client!.newSubscription('orders');
    _tasksSub = _client!.newSubscription('tasks');

    _pubSub = _client!.publication.listen(_onPublication);

    try {
      await _client!.connect();
      await _ordersSub!.subscribe();
      await _tasksSub!.subscribe();
      if (kDebugMode) {
        // ignore: avoid_print
        print('RealtimeService: connected to Centrifugo');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('RealtimeService: connect error $e');
      }
      await disconnect();
      rethrow;
    }
  }

  void _onPublication(ServerPublicationEvent event) {
    try {
      final json = utf8.decode(event.data);
      final data = jsonDecode(json) as Map<String, dynamic>?;
      if (data == null) return;
      final eventType = data['event'] as String?;
      final id = data['id'];
      final status = data['status'] as String?;

      if (event.channel == 'orders') {
        final message = _orderMessage(eventType, id, status);
        if (message != null) {
          _notificationController.add(RealtimeNotification(
            type: 'order',
            message: message,
            data: data,
          ));
        }
      } else if (event.channel == 'tasks') {
        final message = _taskMessage(eventType, id, status, data['title'] as String?);
        if (message != null) {
          _notificationController.add(RealtimeNotification(
            type: 'task',
            message: message,
            data: data,
          ));
        }
      }
    } catch (_) {
      // ignore malformed
    }
  }

  String? _orderMessage(String? eventType, dynamic id, String? status) {
    final idStr = id != null ? '#$id' : '';
    switch (eventType) {
      case 'created':
        return 'Новый заказ $idStr';
      case 'updated':
        return 'Заказ $idStr обновлён${status != null ? ' ($status)' : ''}';
      case 'cancelled':
        return 'Заказ $idStr отменён';
      default:
        return 'Заказ $idStr';
    }
  }

  String? _taskMessage(String? eventType, dynamic id, String? status, String? title) {
    switch (eventType) {
      case 'created':
        return title != null && title.isNotEmpty ? 'Новая задача: $title' : 'Новая задача #$id';
      case 'updated':
        return title != null && title.isNotEmpty ? 'Задача обновлена: $title' : 'Задача #$id обновлена';
      case 'deleted':
        return 'Задача #$id удалена';
      default:
        return 'Задача #$id';
    }
  }

  /// Disconnect and unsubscribe. Safe to call multiple times.
  Future<void> disconnect() async {
    await _pubSub?.cancel();
    _pubSub = null;
    if (_ordersSub != null) {
      await _client?.removeSubscription(_ordersSub!);
      _ordersSub = null;
    }
    if (_tasksSub != null) {
      await _client?.removeSubscription(_tasksSub!);
      _tasksSub = null;
    }
    if (_client != null) {
      await _client!.disconnect();
      _client = null;
    }
  }

  void dispose() {
    _notificationController.close();
  }
}
