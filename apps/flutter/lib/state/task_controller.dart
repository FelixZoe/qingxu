import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/task_item.dart';
import '../services/task_storage.dart';
import '../services/task_storage_base.dart';

class TaskController extends ChangeNotifier {
  TaskController({TaskStorageBase? storage}) : _storage = storage ?? TaskStorage();

  final TaskStorageBase _storage;
  final List<TaskItem> _tasks = [];

  static const projects = <ProjectItem>[
    ProjectItem('personal', '个人', 0xFF78A4D6),
    ProjectItem('qingxu', '清序第一版', 0xFFD79468),
  ];

  String activeView = 'today';
  String search = '';
  String? selectedTaskId;

  List<TaskItem> get tasks => List.unmodifiable(_tasks);

  TaskItem? get selectedTask {
    for (final task in _tasks) {
      if (task.id == selectedTaskId && task.deletedAt == null) return task;
    }
    return null;
  }

  String get currentTitle {
    if (search.trim().isNotEmpty) return search.trim();
    if (activeView.startsWith('project:')) {
      final id = activeView.substring('project:'.length);
      return projects.where((project) => project.id == id).firstOrNull?.title ?? '项目';
    }
    return const {
          'inbox': '收集箱',
          'today': '今天',
          'upcoming': '计划',
          'anytime': '随时',
          'logbook': '日志',
        }[activeView] ??
        '今天';
  }

  List<TaskItem> get visibleTasks {
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    final startTomorrow = startToday.add(const Duration(days: 1));
    final query = search.trim().toLowerCase();

    final result = _tasks.where((task) {
      if (task.deletedAt != null) return false;
      if (query.isNotEmpty) {
        return '${task.title}\n${task.notes}'.toLowerCase().contains(query);
      }
      if (activeView.startsWith('project:')) {
        return task.isOpen && task.projectId == activeView.substring('project:'.length);
      }
      if (activeView == 'logbook') return task.status == TaskStatus.completed;
      if (!task.isOpen) return false;
      final start = task.startAt?.toLocal();
      return switch (activeView) {
        'today' => start != null && start.isBefore(startTomorrow),
        'upcoming' => start != null && !start.isBefore(startTomorrow),
        'anytime' => start == null,
        _ => task.projectId == null && start == null,
      };
    }).toList();

    result.sort((first, second) {
      final firstDate = first.startAt?.millisecondsSinceEpoch ?? 1 << 62;
      final secondDate = second.startAt?.millisecondsSinceEpoch ?? 1 << 62;
      final dateOrder = firstDate.compareTo(secondDate);
      return dateOrder == 0 ? first.order.compareTo(second.order) : dateOrder;
    });
    return result;
  }

  Future<void> initialize() async {
    final encoded = await _storage.load();
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final decoded = jsonDecode(encoded) as List<dynamic>;
        _tasks.addAll(decoded.map((value) => TaskItem.fromJson(value as Map<String, Object?>)));
      } on FormatException {
        _tasks.clear();
      }
    }
    if (_tasks.isEmpty) _seed();
  }

  void selectView(String view) {
    activeView = view;
    search = '';
    selectedTaskId = null;
    notifyListeners();
  }

  void setSearch(String value) {
    search = value;
    notifyListeners();
  }

  void selectTask(String? id) {
    selectedTaskId = id;
    notifyListeners();
  }

  void addTask(String title) {
    final value = title.trim();
    if (value.isEmpty) return;
    final now = DateTime.now().toUtc();
    final local = DateTime.now();
    final today = DateTime(local.year, local.month, local.day, 9).toUtc();
    final task = TaskItem(
      id: 'task-${now.microsecondsSinceEpoch}',
      title: value,
      notes: '',
      status: TaskStatus.open,
      projectId: activeView.startsWith('project:') ? activeView.substring('project:'.length) : null,
      startAt: activeView == 'today' ? today : null,
      deadlineAt: null,
      completedAt: null,
      order: now.microsecondsSinceEpoch,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );
    _tasks.add(task);
    selectedTaskId = task.id;
    _changed();
  }

  void updateTask(TaskItem updated) {
    final index = _tasks.indexWhere((task) => task.id == updated.id);
    if (index < 0) return;
    _tasks[index] = updated.copyWith(updatedAt: DateTime.now().toUtc());
    _changed();
  }

  void toggleTask(TaskItem task) {
    final completed = task.status != TaskStatus.completed;
    updateTask(task.copyWith(
      status: completed ? TaskStatus.completed : TaskStatus.open,
      completedAt: completed ? DateTime.now().toUtc() : null,
      clearCompletedAt: !completed,
    ));
  }

  void deleteTask(TaskItem task) {
    updateTask(task.copyWith(deletedAt: DateTime.now().toUtc()));
    selectedTaskId = null;
    notifyListeners();
  }

  void _changed() {
    notifyListeners();
    unawaited(_storage.save(jsonEncode(_tasks.map((task) => task.toJson()).toList())));
  }

  void _seed() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9).toUtc();
    final tomorrow = today.add(const Duration(days: 1));
    final created = DateTime.now().toUtc();
    _tasks.addAll([
      _seedTask('seed-quick', '体验快速新增任务', 1000, today, null, created),
      _seedTask('seed-focus', '整理今天真正重要的三件事', 2000, today, 'personal', created),
      _seedTask('seed-offline', '确认离线保存正常', 3000, today, 'qingxu', created,
          notes: '新增任务后刷新页面，内容仍然保留。'),
      _seedTask('seed-sync', '规划下一阶段的同步服务', 4000, tomorrow, 'qingxu', created),
    ]);
    unawaited(_storage.save(jsonEncode(_tasks.map((task) => task.toJson()).toList())));
  }

  TaskItem _seedTask(
    String id,
    String title,
    int order,
    DateTime startAt,
    String? projectId,
    DateTime createdAt, {
    String notes = '',
  }) {
    return TaskItem(
      id: id,
      title: title,
      notes: notes,
      status: TaskStatus.open,
      projectId: projectId,
      startAt: startAt,
      deadlineAt: null,
      completedAt: null,
      order: order,
      createdAt: createdAt,
      updatedAt: createdAt,
      deletedAt: null,
    );
  }
}
