import 'package:flutter_test/flutter_test.dart';
import 'package:qingxu/models/task_item.dart';

void main() {
  final legacyJson = <String, Object?>{
    'id': 'task-1',
    'title': '整理收集箱',
    'notes': '',
    'status': 'open',
    'projectId': null,
    'startAt': null,
    'deadlineAt': null,
    'completedAt': null,
    'order': 1,
    'createdAt': '2026-08-23T10:00:00.000Z',
    'updatedAt': '2026-08-23T10:00:00.000Z',
    'deletedAt': null,
  };

  test('legacy tasks remain compatible when priority is absent', () {
    final task = TaskItem.fromJson(legacyJson);

    expect(task.priority, isNull);
    expect(task.toJson()['priority'], isNull);
  });

  test('task priority survives sync serialization and can be cleared', () {
    final task = TaskItem.fromJson({...legacyJson, 'priority': 'high'});

    expect(task.priority, 'high');
    expect(TaskItem.fromJson(task.toJson()).priority, 'high');
    expect(task.copyWith(clearPriority: true).priority, isNull);
  });
}
