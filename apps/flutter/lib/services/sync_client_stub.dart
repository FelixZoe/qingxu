import '../models/sync_settings.dart';
import '../models/pomodoro_state.dart';
import '../models/task_item.dart';
import 'sync_client_base.dart';

class SyncClient implements SyncClientBase {
  @override
  bool get isSupported => false;

  @override
  String get defaultDeviceName => '清序设备';

  @override
  Future<void> testConnection(SyncSettings settings) {
    throw const SyncException('当前平台暂不支持同步设置');
  }

  @override
  Future<SyncResponse> sync(
    SyncSettings settings,
    List<TaskItem> tasks,
    PomodoroState pomodoro,
  ) {
    throw const SyncException('当前平台暂不支持同步');
  }
}
