import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/storage.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.init();
  final apiClient = ApiClient(storage);
  final apiService = ApiService(storage, apiClient);

  if (storage.baseUrl != null && storage.baseUrl!.isNotEmpty) {
    apiClient.reconfigure();
  }

  runApp(App(
    storage: storage,
    apiService: apiService,
  ));
}
