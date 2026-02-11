import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/counterparty.dart';
import '../services/api_service.dart';

class CounterpartiesScreen extends StatefulWidget {
  const CounterpartiesScreen({
    super.key,
    required this.apiService,
  });

  final ApiService apiService;

  @override
  State<CounterpartiesScreen> createState() => _CounterpartiesScreenState();
}

class _CounterpartiesScreenState extends State<CounterpartiesScreen> {
  List<Counterparty> _counterparties = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await widget.apiService.getCounterparties();
      if (!mounted) return;
      setState(() {
        _counterparties = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить контрагентов';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteCounterparty(Counterparty counterparty) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить контрагента?'),
        content: Text('Контрагент «${counterparty.name}» будет удален безвозвратно.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await widget.apiService.deleteCounterparty(counterparty.id);
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось удалить');
    }
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
                child: Text(
                  'Контрагенты',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final result = await context.push<bool>('/counterparties/create');
                  if (result == true && mounted) _load();
                },
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Добавить'),
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
                            onPressed: _load,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    )
                  : _counterparties.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.business_outlined,
                                  size: 64, color: AppColors.muted),
                              const SizedBox(height: 16),
                              Text(
                                'Нет контрагентов',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _counterparties.length,
                            itemBuilder: (context, index) {
                              final counterparty = _counterparties[index];
                              return Dismissible(
                                key: Key('counterparty-${counterparty.id}'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  color: AppColors.danger,
                                  child: const Icon(Icons.delete, color: Colors.white),
                                ),
                                confirmDismiss: (direction) async {
                                  await _deleteCounterparty(counterparty);
                                  return false;
                                },
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.primaryLight,
                                      child: Icon(
                                        Icons.business,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    title: Text(counterparty.name),
                                    subtitle: counterparty.phone != null || counterparty.email != null
                                        ? Text(
                                            [counterparty.phone, counterparty.email]
                                                .where((e) => e != null && e.isNotEmpty)
                                                .join(', '),
                                            style: TextStyle(
                                              color: AppColors.muted,
                                              fontSize: 12,
                                            ),
                                          )
                                        : null,
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () async {
                                      final result = await context.push<bool>(
                                        '/counterparties/${counterparty.id}/edit',
                                      );
                                      if (result == true && mounted) _load();
                                    },
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
