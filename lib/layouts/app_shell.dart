import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../state/cashier_state.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.storage,
    required this.apiService,
    required this.child,
  });

  final Storage storage;
  final ApiService apiService;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final CashierState _cashierState;

  @override
  void initState() {
    super.initState();
    _cashierState = CashierState();
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            currentLocation: location,
            onLogout: () async {
              await widget.apiService.logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
          Expanded(
            child: CashierStateScope(
              state: _cashierState,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.currentLocation, required this.onLogout});

  final String currentLocation;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: AppColors.muted.withValues(alpha: 0.5)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Text(
            'Almaty-Foods \n Касса',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _NavItem(
                  icon: PhosphorIconsRegular.cashRegister,
                  label: 'Касса',
                  isSelected: currentLocation == '/cashier',
                  onTap: () => context.go('/cashier'),
                ),
                _NavItem(
                  icon: PhosphorIconsRegular.listBullets,
                  label: 'Категории',
                  isSelected: currentLocation == '/categories',
                  onTap: () => context.go('/categories'),
                ),
                _NavItem(
                  icon: PhosphorIconsRegular.cheese,
                  label: 'Товары',
                  isSelected: currentLocation == '/products',
                  onTap: () => context.go('/products'),
                ),
                _NavItem(
                  icon: PhosphorIconsRegular.package,
                  label: 'Сеты',
                  isSelected: currentLocation == '/sets' ||
                      currentLocation.startsWith('/sets/'),
                  onTap: () => context.go('/sets'),
                ),
                _NavItem(
                  icon: PhosphorIconsRegular.money,
                  label: 'Продажи',
                  isSelected: currentLocation == '/sales' ||
                      currentLocation.startsWith('/sales/'),
                  onTap: () => context.go('/sales'),
                ),
                _NavItem(
                  icon: PhosphorIconsRegular.gear,
                  label: 'Настройки',
                  isSelected: currentLocation == '/settings',
                  onTap: () => context.go('/settings'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.logout, size: 20),
                label: const Text('Выйти'),
                onPressed: () => onLogout(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Icon(
          icon,
          size: 22,
          color: isSelected ? AppColors.primary : AppColors.muted,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? AppColors.primary : AppColors.surface,
          ),
        ),
        selected: isSelected,
        selectedTileColor: AppColors.primaryLight.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: onTap,
      ),
    );
  }
}
