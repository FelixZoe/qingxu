import '../models/sync_settings.dart';
import '../models/task_item.dart';

class SyncResponse {
  const SyncResponse({required this.tasks, required this.serverTime});

  final List<TaskItem> tasks;
  final String serverTime;
}

abstract interface class SyncClientBase {
  bool get isSupported;

  String get defaultDeviceName;

  Future<void> testConnection(SyncSettings settings);

  Future<SyncResponse> sync(SyncSettings settings, List<TaskItem> tasks);
}

class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}
