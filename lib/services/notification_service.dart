import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'realtime_service.dart';

/// Handles local notifications for tasks and orders from Centrifugo WebSocket events.
/// Shows system notifications when app receives real-time events.
class NotificationService {
  NotificationService() {
    _localPlugin = FlutterLocalNotificationsPlugin();
  }

  late final FlutterLocalNotificationsPlugin _localPlugin;

  static const String _channelId = 'alfoods_tasks_orders';
  static const String _channelName = 'Задачи и заказы';

  bool _initialized = false;

  /// Initialize local notifications.
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    if (Platform.isAndroid) {
      await _localPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              importance: Importance.defaultImportance,
            ),
          );
    }

    _initialized = true;
  }

  void _onLocalNotificationTap(NotificationResponse response) {
    if (kDebugMode) {
      print('Notification tapped: ${response.payload}');
    }
  }

  /// Request notification permissions (iOS, Android 13+).
  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidPlugin = _localPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await androidPlugin?.requestNotificationsPermission() ?? true;
    }
    return true;
  }

  /// Show a local notification.
  Future<void> showLocalNotification({
    required String title,
    required String body,
    int? id,
    Map<String, String>? payload,
  }) async {
    final notificationId = id ?? DateTime.now().millisecondsSinceEpoch % 100000;
    String? payloadStr;
    if (payload != null && payload.isNotEmpty) {
      payloadStr = payload.entries.map((e) => '${e.key}=${e.value}').join('|');
    }
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _localPlugin.show(notificationId, title, body, details, payload: payloadStr);
  }

  /// Show local notification from a RealtimeNotification (Centrifugo).
  void showFromRealtime(RealtimeNotification n) {
    showLocalNotification(
      title: n.type == 'order' ? 'Заказ' : 'Задача',
      body: n.message,
      payload: {
        'type': n.type,
        if (n.data['id'] != null) 'id': n.data['id'].toString(),
      },
    );
  }
}
