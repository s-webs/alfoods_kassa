import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alfoods_kassa/app.dart';
import 'package:alfoods_kassa/core/api_client.dart';
import 'package:alfoods_kassa/core/storage.dart';
import 'package:alfoods_kassa/services/api_service.dart';

void main() {
  testWidgets('App loads and shows login screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.init();
    final apiClient = ApiClient(storage);
    final apiService = ApiService(storage, apiClient);

    await tester.pumpWidget(App(
      storage: storage,
      apiService: apiService,
    ));

    expect(find.text('Alfoods Касса'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
  });
}
