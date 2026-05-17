import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/storage.dart';
import 'core/theme.dart';
import 'layouts/app_shell.dart';
import 'screens/cashier_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/category_form_screen.dart';
import 'screens/counterparties_screen.dart';
import 'screens/counterparty_form_screen.dart';
import 'screens/debtors_screen.dart';
import 'screens/login_screen.dart';
import 'screens/nkt_product_details_screen.dart';
import 'screens/nkt_sync_screen.dart';
import 'screens/order_detail_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/print_labels_screen.dart';
import 'screens/product_form_screen.dart';
import 'screens/product_receipt_detail_screen.dart';
import 'screens/product_receipt_form_screen.dart';
import 'screens/product_receipts_screen.dart';
import 'screens/products_screen.dart';
import 'screens/sale_detail_screen.dart';
import 'screens/set_form_screen.dart';
import 'screens/sets_screen.dart';
import 'screens/sale_search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shift_sales_screen.dart';
import 'screens/shifts_list_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/supplier_form_screen.dart';
import 'screens/suppliers_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/realtime_service.dart';
import 'services/time_sync_service.dart';

class App extends StatelessWidget {
  const App({
    super.key,
    required this.storage,
    required this.apiService,
    required this.realtimeService,
    required this.notificationService,
    required this.timeSyncService,
  });

  final Storage storage;
  final ApiService apiService;
  final RealtimeService realtimeService;
  final NotificationService notificationService;
  final TimeSyncService timeSyncService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Alfoods Касса',
      theme: appTheme,
      routerConfig: _createRouter(),
    );
  }

  GoRouter _createRouter() {
    return GoRouter(
      initialLocation: '/login',
      redirect: (context, state) {
        final token = storage.token;
        final isLogin = state.matchedLocation == '/login';
        if (token == null || token.isEmpty) {
          return isLogin ? null : '/login';
        }
        if (isLogin) {
          return '/cashier';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => LoginScreen(
            storage: storage,
            apiService: apiService,
            realtimeService: realtimeService,
          ),
        ),
        // редирект с корня на кассу
        ShellRoute(
          builder: (context, state, child) => AppShell(
            storage: storage,
            apiService: apiService,
            realtimeService: realtimeService,
            notificationService: notificationService,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/',
              redirect: (context, state) => '/cashier',
            ),
            GoRoute(
              path: '/cashier',
              pageBuilder: (context, state) => NoTransitionPage(
                child: CashierScreen(
                  storage: storage,
                  apiService: apiService,
                ),
              ),
            ),
            GoRoute(
              path: '/categories',
              pageBuilder: (context, state) => NoTransitionPage(
                child: CategoriesScreen(apiService: apiService),
              ),
            ),
            GoRoute(
              path: '/categories/create',
              pageBuilder: (context, state) => NoTransitionPage(
                child: CategoryFormScreen(
                  apiService: apiService,
                  mode: CategoryFormMode.create,
                ),
              ),
            ),
            GoRoute(
              path: '/categories/:id/edit',
              pageBuilder: (context, state) {
                final id = int.tryParse(state.pathParameters['id'] ?? '');
                return NoTransitionPage(
                  child: CategoryFormScreen(
                    apiService: apiService,
                    categoryId: id,
                    mode: CategoryFormMode.edit,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/counterparties',
              pageBuilder: (context, state) => NoTransitionPage(
                child: CounterpartiesScreen(apiService: apiService),
              ),
            ),
            GoRoute(
              path: '/counterparties/create',
              pageBuilder: (context, state) => NoTransitionPage(
                child: CounterpartyFormScreen(
                  apiService: apiService,
                  mode: CounterpartyFormMode.create,
                ),
              ),
            ),
            GoRoute(
              path: '/counterparties/:id/edit',
              pageBuilder: (context, state) {
                final id = int.tryParse(state.pathParameters['id'] ?? '');
                return NoTransitionPage(
                  child: CounterpartyFormScreen(
                    apiService: apiService,
                    counterpartyId: id,
                    mode: CounterpartyFormMode.edit,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/suppliers',
              pageBuilder: (context, state) => NoTransitionPage(
                child: SuppliersScreen(apiService: apiService),
              ),
            ),
            GoRoute(
              path: '/suppliers/create',
              pageBuilder: (context, state) => NoTransitionPage(
                child: SupplierFormScreen(
                  apiService: apiService,
                  mode: SupplierFormMode.create,
                ),
              ),
            ),
            GoRoute(
              path: '/suppliers/:id/edit',
              pageBuilder: (context, state) {
                final id = int.tryParse(state.pathParameters['id'] ?? '');
                return NoTransitionPage(
                  child: SupplierFormScreen(
                    apiService: apiService,
                    supplierId: id,
                    mode: SupplierFormMode.edit,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/products',
              pageBuilder: (context, state) => NoTransitionPage(
                child: ProductsScreen(apiService: apiService),
              ),
            ),
            GoRoute(
              path: '/products/create',
              pageBuilder: (context, state) => NoTransitionPage(
                child: ProductFormScreen(
                  storage: storage,
                  apiService: apiService,
                  mode: ProductFormMode.create,
                ),
              ),
            ),
            GoRoute(
              path: '/products/:id/edit',
              pageBuilder: (context, state) {
                final id = int.tryParse(state.pathParameters['id'] ?? '');
                return NoTransitionPage(
                  child: ProductFormScreen(
                    storage: storage,
                    apiService: apiService,
                    productId: id,
                    mode: ProductFormMode.edit,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/sets',
              pageBuilder: (context, state) => NoTransitionPage(
                child: SetsScreen(apiService: apiService),
              ),
            ),
            GoRoute(
              path: '/sets/create',
              pageBuilder: (context, state) => NoTransitionPage(
                child: SetFormScreen(
                  storage: storage,
                  apiService: apiService,
                  mode: SetFormMode.create,
                ),
              ),
            ),
            GoRoute(
              path: '/sets/:id/edit',
              pageBuilder: (context, state) {
                final id = int.tryParse(state.pathParameters['id'] ?? '');
                return NoTransitionPage(
                  child: SetFormScreen(
                    storage: storage,
                    apiService: apiService,
                    setId: id,
                    mode: SetFormMode.edit,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/products/print-labels',
              pageBuilder: (context, state) {
                final ids = state.extra as List<int>?;
                return NoTransitionPage(
                  child: PrintLabelsScreen(
                    storage: storage,
                    apiService: apiService,
                    initialProductIds: ids,
                    mode: PrintLabelsMode.labels,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/products/print-price-tags',
              pageBuilder: (context, state) {
                final ids = state.extra as List<int>?;
                return NoTransitionPage(
                  child: PrintLabelsScreen(
                    storage: storage,
                    apiService: apiService,
                    initialProductIds: ids,
                    mode: PrintLabelsMode.priceTags,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/sales',
              pageBuilder: (context, state) => NoTransitionPage(
                child: ShiftsListScreen(apiService: apiService),
              ),
            ),
            GoRoute(
              path: '/sales/search',
              pageBuilder: (context, state) => NoTransitionPage(
                child: SaleSearchScreen(apiService: apiService),
              ),
            ),
            GoRoute(
              path: '/nkt',
              pageBuilder: (context, state) => NoTransitionPage(
                child: NktSyncScreen(apiService: apiService),
              ),
            ),
            GoRoute(
              path: '/nkt/:id',
              pageBuilder: (context, state) {
                final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                return NoTransitionPage(
                  child: NktProductDetailsScreen(
                    apiService: apiService,
                    productId: id,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) => NoTransitionPage(
                child: SettingsScreen(
                  storage: storage,
                  apiService: apiService,
                ),
              ),
            ),
            GoRoute(
              path: '/sales/shift/:shiftId',
              pageBuilder: (context, state) {
                final shiftId =
                    int.tryParse(state.pathParameters['shiftId'] ?? '') ?? 0;
                return NoTransitionPage(
                  child: ShiftSalesScreen(
                    apiService: apiService,
                    shiftId: shiftId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/sales/sale/:saleId',
              pageBuilder: (context, state) {
                final saleId =
                    int.tryParse(state.pathParameters['saleId'] ?? '') ?? 0;
                return NoTransitionPage(
                  child: SaleDetailScreen(
                    storage: storage,
                    apiService: apiService,
                    saleId: saleId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/debtors',
              pageBuilder: (context, state) => NoTransitionPage(
                child: DebtorsScreen(
                  storage: storage,
                  apiService: apiService,
                ),
              ),
            ),
            GoRoute(
              path: '/orders',
              pageBuilder: (context, state) => NoTransitionPage(
                child: OrdersScreen(
                  apiService: apiService,
                  realtimeService: realtimeService,
                ),
              ),
            ),
            GoRoute(
              path: '/orders/:id',
              pageBuilder: (context, state) {
                final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                return NoTransitionPage(
                  child: OrderDetailScreen(
                    apiService: apiService,
                    storage: storage,
                    orderId: id,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/product-receipts',
              pageBuilder: (context, state) => NoTransitionPage(
                child: ProductReceiptsScreen(apiService: apiService),
              ),
            ),
            GoRoute(
              path: '/product-receipts/create',
              pageBuilder: (context, state) => NoTransitionPage(
                child: ProductReceiptFormScreen(
                  apiService: apiService,
                ),
              ),
            ),
            GoRoute(
              path: '/product-receipts/:receiptId',
              pageBuilder: (context, state) {
                final receiptId =
                    int.tryParse(state.pathParameters['receiptId'] ?? '') ?? 0;
                return NoTransitionPage(
                  child: ProductReceiptDetailScreen(
                    apiService: apiService,
                    receiptId: receiptId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/tasks',
              pageBuilder: (context, state) => NoTransitionPage(
                child: TasksScreen(
                  apiService: apiService,
                  realtimeService: realtimeService,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
