import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../models/order.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/realtime_service.dart';
import '../state/cashier_state.dart';
import '../state/task_state.dart';
import '../utils/toast.dart';
import '../widgets/today_tasks_dropdown.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.storage,
    required this.apiService,
    required this.realtimeService,
    required this.notificationService,
    required this.child,
  });

  final Storage storage;
  final ApiService apiService;
  final RealtimeService realtimeService;
  final NotificationService notificationService;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final CashierState _cashierState;
  late final TaskState _taskState;
  StreamSubscription? _realtimeSub;
  Timer? _newOrdersPollTimer;
  Timer? _newOrdersDebounce;
  int _newOnlineOrdersTotal = 0;

  @override
  void initState() {
    super.initState();
    _cashierState = CashierState();
    _taskState = TaskState(widget.apiService);
    if (widget.storage.token != null && widget.storage.token!.isNotEmpty) {
      _initRealtime();
      _initNotifications();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshNewOnlineOrdersCount();
      });
      _newOrdersPollTimer = Timer.periodic(
        const Duration(seconds: 55),
        (_) => _refreshNewOnlineOrdersCount(),
      );
    }
    _realtimeSub = widget.realtimeService.notifications.listen(_onRealtimeNotification);
  }

  Future<void> _initRealtime() async {
    try {
      await widget.realtimeService.connect();
    } catch (e) {
      if (mounted) {
        debugPrint('RealtimeService init error: $e');
      }
    }
  }

  Future<void> _initNotifications() async {
    try {
      await widget.notificationService.requestPermissions();
    } catch (e) {
      if (mounted) {
        debugPrint('NotificationService init error: $e');
      }
    }
  }

  void _onRealtimeNotification(dynamic n) {
    if (!mounted) return;
    if (n is RealtimeNotification) {
      widget.notificationService.showFromRealtime(n);
      if (n.type == 'order') {
        showToast(
          context,
          n.message,
          duration: const Duration(seconds: 3),
          orderAccent: true,
        );
        _newOrdersDebounce?.cancel();
        _newOrdersDebounce = Timer(const Duration(milliseconds: 400), () {
          if (mounted) _refreshNewOnlineOrdersCount();
        });
        return;
      }
    }
    final message = n is RealtimeNotification ? n.message : n.toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _refreshNewOnlineOrdersCount() async {
    final token = widget.storage.token;
    if (token == null || token.isEmpty || !mounted) return;
    try {
      final result = await widget.apiService.getOrders(
        status: Order.statusNew,
        page: 1,
      );
      if (!mounted) return;
      setState(() => _newOnlineOrdersTotal = result.total);
    } catch (_) {
      // тихо: сеть/API недоступны — оставляем предыдущее значение
    }
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _newOrdersPollTimer?.cancel();
    _newOrdersDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            currentLocation: location,
            newOnlineOrdersCount: _newOnlineOrdersTotal,
            onLogout: () async {
              await widget.realtimeService.disconnect();
              await widget.apiService.logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
          Expanded(
            child: TaskStateScope(
              state: _taskState,
              child: CashierStateScope(
                state: _cashierState,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.muted.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TodayTasksDropdown(),
                        ],
                      ),
                    ),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.currentLocation,
    required this.newOnlineOrdersCount,
    required this.onLogout,
  });

  final String currentLocation;
  final int newOnlineOrdersCount;
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
                  icon: PhosphorIconsRegular.package,
                  label: 'Поступления',
                  isSelected: currentLocation == '/product-receipts' ||
                      currentLocation.startsWith('/product-receipts/'),
                  onTap: () => context.go('/product-receipts'),
                ),
                _NavItem(
                  icon: PhosphorIconsRegular.cheese,
                  label: 'Товары',
                  isSelected: currentLocation == '/products' ||
                      currentLocation.startsWith('/products/'),
                  onTap: () => context.go('/products'),
                ),
                _NavItem(
                  icon: PhosphorIconsRegular.money,
                  label: 'Продажи',
                  isSelected: currentLocation == '/sales' ||
                      currentLocation.startsWith('/sales/'),
                  onTap: () => context.go('/sales'),
                ),
                _OnlineOrdersNavTile(
                  isSelected: currentLocation == '/orders' ||
                      currentLocation.startsWith('/orders/'),
                  highlightPulse: newOnlineOrdersCount > 0,
                  badgeCount: newOnlineOrdersCount,
                  onTap: () => context.go('/orders'),
                ),
                _NavItem(
                  icon: PhosphorIconsRegular.truck,
                  label: 'Поставщики',
                  isSelected: currentLocation == '/suppliers' ||
                      currentLocation.startsWith('/suppliers/'),
                  onTap: () => context.go('/suppliers'),
                ),
                _NavItem(
                  icon: PhosphorIconsRegular.listBullets,
                  label: 'Категории',
                  isSelected: currentLocation == '/categories' ||
                      currentLocation.startsWith('/categories/'),
                  onTap: () => context.go('/categories'),
                ),
                _NavItem(
                  icon: PhosphorIconsRegular.buildings,
                  label: 'Покупатели',
                  isSelected: currentLocation == '/counterparties' ||
                      currentLocation.startsWith('/counterparties/'),
                  onTap: () => context.go('/counterparties'),
                ),
                _NavItem(
                  icon: PhosphorIconsRegular.package,
                  label: 'Сеты',
                  isSelected: currentLocation == '/sets' ||
                      currentLocation.startsWith('/sets/'),
                  onTap: () => context.go('/sets'),
                ),
                _NavItem(
                  icon: PhosphorIconsRegular.creditCard,
                  label: 'Должники',
                  isSelected: currentLocation == '/debtors',
                  onTap: () => context.go('/debtors'),
                ),
                _NavItem(
                  icon: Icons.task_alt,
                  label: 'Задачи',
                  isSelected: currentLocation == '/tasks',
                  onTap: () => context.go('/tasks'),
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

class _OnlineOrdersNavTile extends StatefulWidget {
  const _OnlineOrdersNavTile({
    required this.isSelected,
    required this.highlightPulse,
    required this.badgeCount,
    required this.onTap,
  });

  final bool isSelected;
  final bool highlightPulse;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  State<_OnlineOrdersNavTile> createState() => _OnlineOrdersNavTileState();
}

class _OnlineOrdersNavTileState extends State<_OnlineOrdersNavTile>
    with SingleTickerProviderStateMixin {
  static const Color _accent = Color(0xFF3B14AF);

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (_activePulse) {
      _pulse.repeat(reverse: true);
    }
  }

  bool get _activePulse => widget.highlightPulse && !widget.isSelected;

  @override
  void didUpdateWidget(covariant _OnlineOrdersNavTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = _activePulse;
    final was = oldWidget.highlightPulse && !oldWidget.isSelected;
    if (now && !was) {
      _pulse.repeat(reverse: true);
    } else if (!now && was) {
      _pulse
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pulse = _activePulse;

    final iconColor = widget.isSelected
        ? AppColors.primary
        : pulse
            ? _accent
            : AppColors.muted;
    final titleColor = widget.isSelected
        ? AppColors.primary
        : pulse
            ? _accent
            : AppColors.surface;

    final tile = ListTile(
      leading: Icon(
        PhosphorIconsRegular.shoppingBag,
        size: 22,
        color: iconColor,
      ),
      title: Text(
        'Онлайн заказы',
        style: TextStyle(
          fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
          color: titleColor,
        ),
      ),
      trailing: widget.badgeCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.badgeCount > 99 ? '99+' : '${widget.badgeCount}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: widget.isSelected ? AppColors.primary : _accent,
                ),
              ),
            )
          : null,
      selected: widget.isSelected,
      selectedTileColor: AppColors.primaryLight.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: widget.onTap,
    );

    if (!pulse) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: tile,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final v = _pulse.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _accent.withValues(alpha: 0.45 + 0.35 * v),
                width: 1.5,
              ),
              color: _accent.withValues(alpha: 0.06 + 0.07 * v),
            ),
            child: child,
          );
        },
        child: tile,
      ),
    );
  }
}
