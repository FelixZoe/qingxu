enum TaskStatus { open, completed, cancelled }

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.notes,
    required this.status,
    required this.projectId,
    required this.startAt,
    required this.deadlineAt,
    required this.completedAt,
    required this.order,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final String title;
  final String notes;
  final TaskStatus status;
  final String? projectId;
  final DateTime? startAt;
  final DateTime? deadlineAt;
  final DateTime? completedAt;
  final int order;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isOpen => status == TaskStatus.open && deletedAt == null;

  TaskItem copyWith({
    String? title,
    String? notes,
    TaskStatus? status,
    String? projectId,
    bool clearProject = false,
    DateTime? startAt,
    bool clearStartAt = false,
    DateTime? deadlineAt,
    bool clearDeadline = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? deletedAt,
    DateTime? updatedAt,
  }) {
    return TaskItem(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      projectId: clearProject ? null : (projectId ?? this.projectId),
      startAt: clearStartAt ? null : (startAt ?? this.startAt),
      deadlineAt: clearDeadline ? null : (deadlineAt ?? this.deadlineAt),
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      order: order,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'status': status.name,
        'projectId': projectId,
        'startAt': startAt?.toIso8601String(),
        'deadlineAt': deadlineAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'order': order,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory TaskItem.fromJson(Map<String, Object?> json) {
    DateTime? optionalDate(String key) {
      final value = json[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    return TaskItem(
      id: json['id']! as String,
      title: json['title']! as String,
      notes: (json['notes'] as String?) ?? '',
      status: TaskStatus.values.byName((json['status'] as String?) ?? 'open'),
      projectId: json['projectId'] as String?,
      startAt: optionalDate('startAt'),
      deadlineAt: optionalDate('deadlineAt'),
      completedAt: optionalDate('completedAt'),
      order: (json['order'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      deletedAt: optionalDate('deletedAt'),
    );
  }
}

class ProjectItem {
  const ProjectItem(this.id, this.title, this.color);

  final String id;
  final String title;
  final int color;
}

