import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/storage.dart';
import 'core/theme.dart';
import 'layouts/app_shell.dart';
import 'screens/cashier_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/category_form_screen.dart';
import 'screens/login_screen.dart';
import 'screens/product_form_screen.dart';
import 'screens/products_screen.dart';
import 'screens/sale_detail_screen.dart';
import 'screens/shift_sales_screen.dart';
import 'screens/shifts_list_screen.dart';
import 'services/api_service.dart';

class App extends StatelessWidget {
  const App({
    super.key,
    required this.storage,
    required this.apiService,
  });

  final Storage storage;
  final ApiService apiService;

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
          ),
        ),
        // редирект с корня на кассу
        ShellRoute(
          builder: (context, state, child) => AppShell(
            storage: storage,
            apiService: apiService,
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
              path: '/products',
              pageBuilder: (context, state) => NoTransitionPage(
                child: ProductsScreen(apiService: apiService),
              ),
            ),
            GoRoute(
              path: '/products/create',
              pageBuilder: (context, state) => NoTransitionPage(
                child: ProductFormScreen(
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
                    apiService: apiService,
                    productId: id,
                    mode: ProductFormMode.edit,
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
                    apiService: apiService,
                    saleId: saleId,
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
