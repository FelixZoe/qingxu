import '../models/sync_settings.dart';
import '../models/pomodoro_state.dart';
import '../models/task_item.dart';

class SyncResponse {
  const SyncResponse({
    required this.tasks,
    required this.serverTime,
    this.pomodoro,
  });

  final List<TaskItem> tasks;
  final String serverTime;
  final PomodoroState? pomodoro;
}

abstract interface class SyncClientBase {
  bool get isSupported;

  String get defaultDeviceName;

  Future<void> testConnection(SyncSettings settings);

  Future<SyncResponse> sync(
    SyncSettings settings,
    List<TaskItem> tasks,
    PomodoroState pomodoro,
  );
}

class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}
