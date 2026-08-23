import '../models/sync_settings.dart';
import '../models/pomodoro_state.dart';
import '../models/task_item.dart';

class SyncResponse {
  const SyncResponse({
    required this.tasks,
    required this.serverTime,
    this.pomodoro,
    this.revision = 0,
  });

  final List<TaskItem> tasks;
  final String serverTime;
  final PomodoroState? pomodoro;
  final int revision;
}

class SyncChange {
  const SyncChange({required this.revision, required this.changed});

  final int revision;
  final bool changed;
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

abstract interface class SyncChangeClient {
  Future<SyncChange> waitForChanges(
    SyncSettings settings, {
    required int since,
  });
}

class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}
