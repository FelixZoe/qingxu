import 'package:flutter_test/flutter_test.dart';
import 'package:qingxu/services/secure_token_storage_stub.dart';
import 'package:qingxu/services/sync_settings_storage_stub.dart';
import 'package:qingxu/services/task_storage_stub.dart';
import 'package:qingxu/state/task_controller.dart';

void main() {
  test('seeds today and persists a newly added task', () async {
    final storage = TaskStorage();
    final syncSettingsStorage = SyncSettingsStorage();
    final secureTokenStorage = SecureTokenStorage();
    final controller = TaskController(
      storage: storage,
      syncSettingsStorage: syncSettingsStorage,
      secureTokenStorage: secureTokenStorage,
    );
    await controller.initialize();

    expect(controller.visibleTasks, hasLength(3));
    controller.addTask('测试任务');
    expect(controller.visibleTasks.any((task) => task.title == '测试任务'), isTrue);

    await Future<void>.delayed(Duration.zero);
    final restored = TaskController(
      storage: storage,
      syncSettingsStorage: syncSettingsStorage,
      secureTokenStorage: secureTokenStorage,
    );
    await restored.initialize();
    expect(restored.visibleTasks.any((task) => task.title == '测试任务'), isTrue);
  });

  test('uses the four primary navigation destinations', () async {
    final controller = TaskController(
      storage: TaskStorage(),
      syncSettingsStorage: SyncSettingsStorage(),
      secureTokenStorage: SecureTokenStorage(),
    );
    await controller.initialize();

    controller.selectView('inbox');
    expect(controller.currentTitle, '收集箱');
    controller.selectView('pomodoro');
    expect(controller.currentTitle, '番茄钟');
    expect(controller.visibleTasks, isEmpty);
    controller.selectView('settings');
    expect(controller.currentTitle, '设置');
    expect(controller.visibleTasks, isEmpty);
  });
}
