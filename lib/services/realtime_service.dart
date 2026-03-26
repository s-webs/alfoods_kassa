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

    // Listen to subscription publications
    _ordersSub!.publication.listen((event) => _onPublication('orders', event));
    _tasksSub!.publication.listen((event) => _onPublication('tasks', event));

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

  void _onPublication(String channel, PublicationEvent event) {
    if (kDebugMode) {
      print('📨 RealtimeService: received event on channel $channel');
      print('   Raw data length: ${event.data.length} bytes');
    }
    try {
      final json = utf8.decode(event.data);
      if (kDebugMode) {
        print('   Decoded JSON: $json');
      }
      final data = jsonDecode(json) as Map<String, dynamic>?;
      if (data == null) {
        if (kDebugMode) {
          print('   ⚠️ Data is null after JSON decode');
        }
        return;
      }
      final eventType = data['event'] as String?;
      final id = data['id'];
      final status = data['status'] as String?;

      // Extract simple event name from Laravel format (e.g., "task.created" -> "created")
      String? simpleEvent;
      if (eventType != null) {
        final parts = eventType.split('.');
        simpleEvent = parts.length > 1 ? parts.last : eventType;
      }

      if (kDebugMode) {
        print('   Event type: $eventType (simple: $simpleEvent), ID: $id, Status: $status');
      }

      if (channel == 'orders') {
        final message = _orderMessage(simpleEvent, id, status);
        if (message != null) {
          if (kDebugMode) {
            print('   ✅ Adding order notification: $message');
          }
          _notificationController.add(RealtimeNotification(
            type: 'order',
            message: message,
            data: data,
          ));
        }
      } else if (channel == 'tasks') {
        final message = _taskMessage(simpleEvent, id, status, data['title'] as String?);
        if (message != null) {
          if (kDebugMode) {
            print('   ✅ Adding task notification: $message');
          }
          _notificationController.add(RealtimeNotification(
            type: 'task',
            message: message,
            data: data,
          ));
        }
      }
    } catch (e, stack) {
      if (kDebugMode) {
        print('   ❌ Error parsing publication: $e');
        print('   Stack: $stack');
      }
    }
  }

  static String _orderStatusLabel(String? status) {
    if (status == null || status.isEmpty) return status ?? '';
    switch (status) {
      case 'new':
        return 'новый';
      case 'in_progress':
        return 'в работе';
      case 'completed':
        return 'выполнен';
      case 'cancelled':
        return 'отменён';
      default:
        return status;
    }
  }

  static String _taskStatusLabel(String? status) {
    if (status == null || status.isEmpty) return status ?? '';
    switch (status) {
      case 'created':
      case 'new':
        return 'новая';
      case 'in_progress':
        return 'в работе';
      case 'completed':
      case 'done':
        return 'выполнено';
      case 'cancelled':
        return 'отменено';
      default:
        return status;
    }
  }

  String? _orderMessage(String? eventType, dynamic id, String? status) {
    final numStr = id != null ? ' №$id' : '';
    switch (eventType) {
      case 'created':
        return 'Новый заказ$numStr';
      case 'updated':
        if (status != null && status.isNotEmpty) {
          final label = _orderStatusLabel(status);
          return 'Статус заказа$numStr изменён на $label';
        }
        return 'Заказ$numStr обновлён';
      case 'cancelled':
        return 'Заказ$numStr отменён';
      default:
        return 'Заказ$numStr';
    }
  }

  String? _taskMessage(String? eventType, dynamic id, String? status, String? title) {
    final numStr = id != null ? ' №$id' : '';
    final titlePart = (title != null && title.isNotEmpty) ? ': $title' : '';
    switch (eventType) {
      case 'created':
        return 'Создана задача$numStr$titlePart';
      case 'updated':
        if (status != null && status.isNotEmpty) {
          final label = _taskStatusLabel(status);
          return 'Статус задачи$numStr изменён на $label$titlePart';
        }
        return 'Обновлена задача$numStr$titlePart';
      case 'deleted':
        return 'Удалена задача$numStr$titlePart';
      default:
        return 'Задача$numStr';
    }
  }

  /// Disconnect and unsubscribe. Safe to call multiple times.
  Future<void> disconnect() async {
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
