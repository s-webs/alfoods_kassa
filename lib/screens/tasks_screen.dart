import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../utils/toast.dart';
import '../state/task_state.dart';
import '../widgets/task_form_dialog.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Task> _allTasks = [];
  DateTime? _selectedDate;
  TaskStatus? _selectedStatus;
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
      final tasks = await widget.apiService.getTasks(
        date: _selectedDate,
        status: _selectedStatus?.value,
      );
      if (!mounted) return;
      setState(() {
        _allTasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить задачи';
        _isLoading = false;
      });
    }
  }

  Future<void> _createTask() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const TaskFormDialog(),
    );

    if (result != null && mounted) {
      try {
        final taskState = TaskStateScope.of(context);
        await taskState.createTask(
          title: result['title'] as String,
          description: result['description'] as String?,
          dueDate: result['dueDate'] as DateTime,
          status: result['status'] as TaskStatus?,
        );
        await _load();
        final todayTaskState = TaskStateScope.of(context);
        await todayTaskState.loadTodayTasks(force: true);
      } catch (e) {
        if (mounted) {
          showToast(context, 'Не удалось создать задачу: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _editTask(Task task) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => TaskFormDialog(task: task),
    );

    if (result != null && mounted) {
      try {
        await widget.apiService.updateTask(
          task.id,
          title: result['title'] as String,
          description: result['description'] as String?,
          dueDate: result['dueDate'] as DateTime,
          status: result['status'] as TaskStatus?,
        );
        await _load();
        final taskState = TaskStateScope.of(context);
        await taskState.loadTodayTasks(force: true);
      } catch (e) {
        if (mounted) {
          showToast(context, 'Не удалось обновить задачу: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _deleteTask(Task task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text('Задача "${task.title}" будет удалена.'),
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

    if (confirm == true && mounted) {
      try {
        await widget.apiService.deleteTask(task.id);
        await _load();
        final taskState = TaskStateScope.of(context);
        await taskState.loadTodayTasks(force: true);
      } catch (e) {
        if (mounted) {
          showToast(context, 'Не удалось удалить задачу: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      await _load();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _selectedDate = null;
    });
    _load();
  }

  void _setStatusFilter(TaskStatus? status) {
    setState(() {
      _selectedStatus = status;
    });
    _load();
  }

  Map<DateTime, List<Task>> _groupTasksByDate() {
    final grouped = <DateTime, List<Task>>{};
    for (final task in _allTasks) {
      final date = DateTime(task.dueDate.year, task.dueDate.month, task.dueDate.day);
      grouped.putIfAbsent(date, () => []).add(task);
    }
    return grouped;
  }

  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.created:
        return AppColors.muted;
      case TaskStatus.inProgress:
        return AppColors.primary;
      case TaskStatus.completed:
        return AppColors.accent;
      case TaskStatus.notCompleted:
        return AppColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Задачи')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Задачи')),
        body: Center(
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
        ),
      );
    }

    final groupedTasks = _groupTasksByDate();
    final sortedDates = groupedTasks.keys.toList()
      ..sort((a, b) => a.compareTo(b));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Задачи'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createTask,
            tooltip: 'Создать задачу',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectDate,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          _selectedDate == null
                              ? 'Все даты'
                              : '${_selectedDate!.day.toString().padLeft(2, '0')}.${_selectedDate!.month.toString().padLeft(2, '0')}.${_selectedDate!.year}',
                        ),
                      ),
                    ),
                    if (_selectedDate != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearDateFilter,
                        tooltip: 'Очистить фильтр по дате',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('Все'),
                      selected: _selectedStatus == null,
                      onSelected: (_) => _setStatusFilter(null),
                    ),
                    ...TaskStatus.values.map((status) {
                      return FilterChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _getStatusColor(status),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(status.label),
                          ],
                        ),
                        selected: _selectedStatus == status,
                        onSelected: (_) => _setStatusFilter(status),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: groupedTasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.task_alt, size: 64, color: AppColors.muted),
                        const SizedBox(height: 16),
                        Text(
                          'Нет задач',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _createTask,
                          icon: const Icon(Icons.add),
                          label: const Text('Создать задачу'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: sortedDates.length,
                    itemBuilder: (context, index) {
                      final date = sortedDates[index];
                      final tasks = groupedTasks[date]!;
                      final isToday = date.year == DateTime.now().year &&
                          date.month == DateTime.now().month &&
                          date.day == DateTime.now().day;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(bottom: 8, top: index > 0 ? 16 : 0),
                            child: Row(
                              children: [
                                Text(
                                  isToday
                                      ? 'Сегодня'
                                      : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: isToday ? AppColors.primary : null,
                                      ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    tasks.length.toString(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...tasks.map((task) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(task.status),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                title: Text(
                                  task.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (task.description != null &&
                                        task.description!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          task.description!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        task.status.label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _getStatusColor(task.status),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: PopupMenuButton(
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit, size: 18),
                                          SizedBox(width: 8),
                                          Text('Редактировать'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'status',
                                      child: const Row(
                                        children: [
                                          Icon(Icons.flag, size: 18),
                                          SizedBox(width: 8),
                                          Text('Изменить статус'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, size: 18, color: AppColors.danger),
                                          SizedBox(width: 8),
                                          Text('Удалить', style: TextStyle(color: AppColors.danger)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      await _editTask(task);
                                    } else if (value == 'status') {
                                      final newStatus = await showMenu<TaskStatus>(
                                        context: context,
                                        position: const RelativeRect.fromLTRB(100, 100, 100, 100),
                                        items: TaskStatus.values.map((status) {
                                          return PopupMenuItem(
                                            value: status,
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 10,
                                                  height: 10,
                                                  decoration: BoxDecoration(
                                                    color: _getStatusColor(status),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(status.label),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      );
                                      if (newStatus != null && mounted) {
                                        try {
                                          await widget.apiService.updateTask(
                                            task.id,
                                            status: newStatus,
                                          );
                                          await _load();
                                          final taskState = TaskStateScope.of(context);
                                          await taskState.loadTodayTasks(force: true);
                                        } catch (e) {
                                          if (mounted) {
                                            showToast(context, 'Не удалось обновить статус: ${e.toString()}');
                                          }
                                        }
                                      }
                                    } else if (value == 'delete') {
                                      await _deleteTask(task);
                                    }
                                  },
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
