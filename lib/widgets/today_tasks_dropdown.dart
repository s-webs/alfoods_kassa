import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../utils/toast.dart';
import '../models/task.dart';
import '../state/task_state.dart';

class TodayTasksDropdown extends StatefulWidget {
  const TodayTasksDropdown({super.key});

  @override
  State<TodayTasksDropdown> createState() => _TodayTasksDropdownState();
}

class _TodayTasksDropdownState extends State<TodayTasksDropdown> {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final taskState = TaskStateScope.of(context);
    taskState.loadTodayTasks();
  }

  void _showDropdown() {
    if (_overlayEntry != null) return;

    final taskState = TaskStateScope.of(context);

    _overlayEntry = OverlayEntry(
      builder: (context) => _TaskDropdownOverlay(
        layerLink: _layerLink,
        taskState: taskState,
        onClose: () {
          _overlayEntry?.remove();
          _overlayEntry = null;
        },
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideDropdown() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideDropdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final taskState = TaskStateScope.of(context);

    return CompositedTransformTarget(
      link: _layerLink,
      child: ListenableBuilder(
        listenable: taskState,
        builder: (context, _) {
          final count = taskState.todayTasksCount;
          final isLoading = taskState.isLoadingTodayTasks;

          return OutlinedButton(
            onPressed: () {
              if (_overlayEntry == null) {
                taskState.loadTodayTasks(force: true);
                _showDropdown();
              } else {
                _hideDropdown();
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.task_alt, size: 18),
                const SizedBox(width: 8),
                const Text('Задачи на сегодня'),
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      count.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TaskDropdownOverlay extends StatelessWidget {
  const _TaskDropdownOverlay({
    required this.layerLink,
    required this.taskState,
    required this.onClose,
  });

  final LayerLink layerLink;
  final TaskState taskState;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.transparent,
        child: CompositedTransformFollower(
          link: layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 48),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
              child: ListenableBuilder(
                listenable: taskState,
                builder: (context, _) {
                  final tasks = taskState.todayTasks;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tasks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Нет задач на сегодня',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: tasks.length,
                            itemBuilder: (context, index) {
                              final task = tasks[index];
                              return _TaskItem(
                                task: task,
                                taskState: taskState,
                              );
                            },
                          ),
                        ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.list, size: 20),
                        title: const Text(
                          'Все задачи',
                          style: TextStyle(fontSize: 14),
                        ),
                        onTap: () {
                          onClose();
                          context.push('/tasks');
                        },
                        dense: true,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskItem extends StatefulWidget {
  const _TaskItem({
    required this.task,
    required this.taskState,
  });

  final Task task;
  final TaskState taskState;

  @override
  State<_TaskItem> createState() => _TaskItemState();
}

class _TaskItemState extends State<_TaskItem> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didUpdateWidget(_TaskItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Если задача изменилась (например, статус), закрываем раскрытие
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.task.status != widget.task.status) {
      if (_isExpanded) {
        setState(() {
          _isExpanded = false;
        });
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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

  Future<void> _selectStatus(TaskStatus status) async {
    if (status != widget.task.status) {
      try {
        await widget.taskState.updateTaskStatus(widget.task, status);
        setState(() {
          _isExpanded = false;
        });
        _animationController.reverse();
      } catch (e) {
        if (mounted) {
          showToast(context, 'Не удалось обновить статус: ${e.toString()}');
        }
      }
    } else {
      setState(() {
        _isExpanded = false;
      });
      _animationController.reverse();
    }
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    if (_isExpanded) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(widget.task.status);

    return Column(
      children: [
        InkWell(
          onTap: _toggleExpanded,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.task.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      if (widget.task.description != null &&
                          widget.task.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            widget.task.description!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            widget.task.status.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: _isExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              Icons.arrow_drop_down,
                              size: 16,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SizeTransition(
          sizeFactor: _expandAnimation,
          axisAlignment: -1.0,
          child: Container(
            margin: const EdgeInsets.only(left: 28, right: 16),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: TaskStatus.values.map((status) {
                final isSelected = status == widget.task.status;
                final itemColor = _getStatusColor(status);
                return InkWell(
                  onTap: () => _selectStatus(status),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: itemColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            status.label,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected ? itemColor : null,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check,
                            size: 18,
                            color: itemColor,
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
