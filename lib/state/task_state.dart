import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/api_service.dart';

/// Состояние задач.
/// Живёт в Shell и не сбрасывается при переходе на другие экраны.
class TaskState extends ChangeNotifier {
  TaskState(this._apiService);

  final ApiService _apiService;

  List<Task> _todayTasks = [];
  bool _isLoadingTodayTasks = false;
  DateTime? _lastTodayTasksLoad;

  List<Task> get todayTasks => _todayTasks;
  bool get isLoadingTodayTasks => _isLoadingTodayTasks;
  int get todayTasksCount => _todayTasks.length;

  /// Загрузить задачи на сегодня.
  Future<void> loadTodayTasks({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastTodayTasksLoad != null &&
        _lastTodayTasksLoad!.day == now.day &&
        _lastTodayTasksLoad!.month == now.month &&
        _lastTodayTasksLoad!.year == now.year) {
      return;
    }

    _isLoadingTodayTasks = true;
    notifyListeners();

    try {
      _todayTasks = await _apiService.getTodayTasks();
      _lastTodayTasksLoad = now;
    } catch (e) {
      // Ignore errors, keep previous state
    } finally {
      _isLoadingTodayTasks = false;
      notifyListeners();
    }
  }

  /// Обновить задачу (например, изменить статус).
  Future<void> updateTask(Task task) async {
    try {
      final updated = await _apiService.updateTask(
        task.id,
        title: task.title,
        description: task.description,
        dueDate: task.dueDate,
        status: task.status,
      );

      final index = _todayTasks.indexWhere((t) => t.id == task.id);
      if (index >= 0) {
        _todayTasks[index] = updated;
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Создать задачу.
  Future<Task> createTask({
    required String title,
    String? description,
    required DateTime dueDate,
    TaskStatus? status,
  }) async {
    try {
      final task = await _apiService.createTask(
        title: title,
        description: description,
        dueDate: dueDate,
        status: status,
      );

      final today = DateTime.now();
      if (task.dueDate.year == today.year &&
          task.dueDate.month == today.month &&
          task.dueDate.day == today.day) {
        _todayTasks.add(task);
        notifyListeners();
      }

      return task;
    } catch (e) {
      rethrow;
    }
  }

  /// Удалить задачу.
  Future<void> deleteTask(Task task) async {
    try {
      await _apiService.deleteTask(task.id);
      _todayTasks.removeWhere((t) => t.id == task.id);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  /// Обновить статус задачи.
  Future<void> updateTaskStatus(Task task, TaskStatus status) async {
    await updateTask(task.copyWith(status: status));
  }
}

/// Прокидывает [TaskState] вниз по дереву (из Shell).
class TaskStateScope extends InheritedWidget {
  const TaskStateScope({
    super.key,
    required this.state,
    required super.child,
  });

  final TaskState state;

  static TaskState of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<TaskStateScope>();
    assert(scope != null, 'TaskStateScope not found');
    return scope!.state;
  }

  @override
  bool updateShouldNotify(TaskStateScope oldWidget) =>
      state != oldWidget.state;
}
