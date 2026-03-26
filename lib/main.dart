import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/storage.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/realtime_service.dart';
import 'services/time_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.init();
  final apiClient = ApiClient(storage);
  final apiService = ApiService(storage, apiClient);
  final realtimeService = RealtimeService(storage);
  final notificationService = NotificationService();
  final timeSyncService = TimeSyncService(storage);

  if (storage.baseUrl != null && storage.baseUrl!.isNotEmpty) {
    apiClient.reconfigure();
  }

  await notificationService.initialize();
  await timeSyncService.restoreCachedOffset();
  await timeSyncService.syncNow();
  timeSyncService.startAutoSync();

  runApp(App(
    storage: storage,
    apiService: apiService,
    realtimeService: realtimeService,
    notificationService: notificationService,
    timeSyncService: timeSyncService,
  ));
}
