import 'package:flutter_test/flutter_test.dart';
import 'package:qingxu/services/task_storage_stub.dart';
import 'package:qingxu/state/task_controller.dart';

void main() {
  test('seeds today and persists a newly added task', () async {
    final storage = TaskStorage();
    final controller = TaskController(storage: storage);
    await controller.initialize();

    expect(controller.visibleTasks, hasLength(3));
    controller.addTask('测试任务');
    expect(controller.visibleTasks.any((task) => task.title == '测试任务'), isTrue);

    await Future<void>.delayed(Duration.zero);
    final restored = TaskController(storage: storage);
    await restored.initialize();
    expect(restored.visibleTasks.any((task) => task.title == '测试任务'), isTrue);
  });
}

