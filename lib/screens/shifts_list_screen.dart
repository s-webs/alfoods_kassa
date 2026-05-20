import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/shift.dart';
import '../services/api_service.dart';
import '../utils/time_util.dart';

class ShiftsListScreen extends StatefulWidget {
  const ShiftsListScreen({
    super.key,
    required this.apiService,
  });

  final ApiService apiService;

  @override
  State<ShiftsListScreen> createState() => _ShiftsListScreenState();
}

class _ShiftsListScreenState extends State<ShiftsListScreen> {
  final List<Shift> _shifts = [];
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  int _lastPage = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _hasMore => _currentPage < _lastPage;

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _currentPage = 1;
        _shifts.clear();
      });
    }

    try {
      final page = await widget.apiService.getShifts(page: 1);
      if (!mounted) return;
      setState(() {
        _shifts
          ..clear()
          ..addAll(page.data);
        _currentPage = page.currentPage;
        _lastPage = page.lastPage;
        _total = page.total;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить смены';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await widget.apiService.getShifts(page: _currentPage + 1);
      if (!mounted) return;
      setState(() {
        _shifts.addAll(page.data);
        _currentPage = page.currentPage;
        _lastPage = page.lastPage;
        _total = page.total;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  String _formatShiftTitle(Shift s) {
    final opened =
        '${TimeUtil.toUtcPlus5Wall(s.openedAt).day.toString().padLeft(2, '0')}.${TimeUtil.toUtcPlus5Wall(s.openedAt).month.toString().padLeft(2, '0')}.${TimeUtil.toUtcPlus5Wall(s.openedAt).year} '
        '${TimeUtil.toUtcPlus5Wall(s.openedAt).hour.toString().padLeft(2, '0')}:${TimeUtil.toUtcPlus5Wall(s.openedAt).minute.toString().padLeft(2, '0')}';
    if (s.closedAt != null) {
      final closed =
          '${TimeUtil.toUtcPlus5Wall(s.closedAt!).hour.toString().padLeft(2, '0')}:${TimeUtil.toUtcPlus5Wall(s.closedAt!).minute.toString().padLeft(2, '0')}';
      return '$opened – $closed';
    }
    return '$opened (открыта)';
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
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Продажи',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (_total > 0)
                      Text(
                        'Смен: $_total',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => context.push('/sales/search'),
                icon: const Icon(Icons.search, size: 20),
                label: const Text('Поиск продажи'),
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
                          Icon(Icons.error_outline,
                              size: 48, color: AppColors.danger),
                          const SizedBox(height: 16),
                          Text(_error!),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => _load(reset: true),
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    )
                  : _shifts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.schedule,
                                  size: 64, color: AppColors.muted),
                              const SizedBox(height: 16),
                              Text(
                                'Нет смен',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _load(reset: true),
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _shifts.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _shifts.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              final shift = _shifts[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primaryLight,
                                    child: Icon(
                                      shift.isOpen
                                          ? Icons.play_circle_filled
                                          : Icons.stop_circle,
                                      color: shift.isOpen
                                          ? AppColors.accent
                                          : AppColors.muted,
                                    ),
                                  ),
                                  title: Text(_formatShiftTitle(shift)),
                                  subtitle: Text(
                                    shift.isOpen ? 'Открыта' : 'Закрыта',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => context.push(
                                    '/sales/shift/${shift.id}',
                                  ),
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
