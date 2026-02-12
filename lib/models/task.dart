enum TaskStatus {
  created('created', 'Создана'),
  inProgress('in_progress', 'Выполняется'),
  completed('completed', 'Выполнена'),
  notCompleted('not_completed', 'Не выполнена');

  const TaskStatus(this.value, this.label);
  final String value;
  final String label;

  static TaskStatus fromString(String? value) {
    if (value == null) return TaskStatus.created;
    return TaskStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TaskStatus.created,
    );
  }
}

class Task {
  final int id;
  final String title;
  final String? description;
  final DateTime dueDate;
  final TaskStatus status;
  final int userId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Task({
    required this.id,
    required this.title,
    this.description,
    required this.dueDate,
    required this.status,
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: _parseInt(json['id']),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'].toString())
          : DateTime.now(),
      status: TaskStatus.fromString(json['status']?.toString()),
      userId: _parseInt(json['user_id']),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'due_date': dueDate.toIso8601String().split('T')[0],
      'status': status.value,
    };
  }

  Task copyWith({
    int? id,
    String? title,
    String? description,
    DateTime? dueDate,
    TaskStatus? status,
    int? userId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }
}
