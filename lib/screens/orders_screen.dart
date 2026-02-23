import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/order.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({
    super.key,
    required this.apiService,
    required this.realtimeService,
  });

  final ApiService apiService;
  final RealtimeService realtimeService;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Order> _orders = [];
  bool _isLoading = true;
  String? _error;
  int _currentPage = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  String? _search;
  String? _statusFilter;
  String? _dateFrom;
  String? _dateTo;
  final _searchController = TextEditingController();
  final _dateFromController = TextEditingController();
  final _dateToController = TextEditingController();
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _load();
    _realtimeSub = widget.realtimeService.notifications
        .where((n) => n.type == 'order')
        .listen((_) {
      if (mounted) _load(resetPage: true);
    });
  }

  void _setDateFrom(DateTime? date) {
    if (date == null) return;
    setState(() {
      _dateFrom = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      _dateFromController.text = _dateFrom!;
    });
  }

  void _setDateTo(DateTime? date) {
    if (date == null) return;
    setState(() {
      _dateTo = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      _dateToController.text = _dateTo!;
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _searchController.dispose();
    _dateFromController.dispose();
    _dateToController.dispose();
    super.dispose();
  }

  Future<void> _load({bool resetPage = true}) async {
    if (resetPage) _currentPage = 1;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await widget.apiService.getOrders(
        search: _search?.trim().isEmpty == true ? null : _search,
        status: _statusFilter?.isEmpty == true ? null : _statusFilter,
        dateFrom: _dateFrom?.isEmpty == true ? null : _dateFrom,
        dateTo: _dateTo?.isEmpty == true ? null : _dateTo,
        page: _currentPage,
      );
      if (!mounted) return;
      setState(() {
        _orders = result.data;
        _currentPage = result.currentPage;
        _hasMore = result.hasMore;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить заказы';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.apiService.getOrders(
        search: _search?.trim().isEmpty == true ? null : _search,
        status: _statusFilter?.isEmpty == true ? null : _statusFilter,
        dateFrom: _dateFrom?.isEmpty == true ? null : _dateFrom,
        dateTo: _dateTo?.isEmpty == true ? null : _dateTo,
        page: _currentPage + 1,
      );
      if (!mounted) return;
      setState(() {
        _orders = [..._orders, ...result.data];
        _currentPage = result.currentPage;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _applyFilters() {
    _search = _searchController.text.trim().isEmpty ? null : _searchController.text.trim();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: AppColors.muted.withValues(alpha: 0.5)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Онлайн заказы',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'ID заказа или имя/email',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) => _applyFilters(),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<String>(
                        value: _statusFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Статус',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Все')),
                          DropdownMenuItem(value: Order.statusNew, child: Text('Новый')),
                          DropdownMenuItem(value: Order.statusInProgress, child: Text('Заказ собирается')),
                          DropdownMenuItem(value: Order.statusIssued, child: Text('Выдан')),
                          DropdownMenuItem(value: Order.statusCancelled, child: Text('Отменён')),
                        ],
                        onChanged: (v) {
                          setState(() => _statusFilter = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 130,
                      child: TextFormField(
                        controller: _dateFromController,
                        decoration: const InputDecoration(
                          labelText: 'Дата с',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        readOnly: true,
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          _setDateFrom(date);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 130,
                      child: TextFormField(
                        controller: _dateToController,
                        decoration: const InputDecoration(
                          labelText: 'Дата по',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        readOnly: true,
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          _setDateTo(date);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _applyFilters,
                child: const Text('Искать'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                          const SizedBox(height: 16),
                          Text(_error!),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => _load(),
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    )
                  : _orders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined,
                                  size: 64, color: AppColors.muted),
                              const SizedBox(height: 16),
                              Text(
                                'Нет заказов',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _load(),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _orders.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _orders.length) {
                                _loadMore();
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              final order = _orders[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primaryLight,
                                    child: Icon(
                                      Icons.receipt_long,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  title: Text('#${order.id} · ${order.createdAt.toString().substring(0, 16)}'),
                                  subtitle: Text(
                                    '${order.user?.name ?? "—"} · ${order.total.toStringAsFixed(2)} · ${order.statusLabel}',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () async {
                                    final updated = await context.push<bool>(
                                      '/orders/${order.id}',
                                    );
                                    if (updated == true && mounted) _load();
                                  },
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
