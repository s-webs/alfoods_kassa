import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/task.dart';

class TaskFormDialog extends StatefulWidget {
  const TaskFormDialog({
    super.key,
    this.task,
  });

  final Task? task;

  @override
  State<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<TaskFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TaskStatus _selectedStatus = TaskStatus.created;

  @override
  void initState() {
    super.initState();
    if (widget.task != null) {
      _titleController.text = widget.task!.title;
      _descriptionController.text = widget.task!.description ?? '';
      _selectedDate = widget.task!.dueDate;
      _selectedStatus = widget.task!.status;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'dueDate': _selectedDate,
        'status': _selectedStatus,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.task == null ? 'Создать задачу' : 'Редактировать задачу'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите название задачи';
                  }
                  return null;
                },
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Описание (необязательно)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _selectDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Дата выполнения',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    '${_selectedDate.day.toString().padLeft(2, '0')}.${_selectedDate.month.toString().padLeft(2, '0')}.${_selectedDate.year}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<TaskStatus>(
                value: _selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Статус',
                  border: OutlineInputBorder(),
                ),
                items: TaskStatus.values.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
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
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedStatus = value;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.task == null ? 'Создать' : 'Сохранить'),
        ),
      ],
    );
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
}
