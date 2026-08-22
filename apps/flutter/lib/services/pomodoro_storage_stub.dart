import 'pomodoro_storage_base.dart';

class PomodoroStorage implements PomodoroStorageBase {
  @override
  Future<String?> load() async => null;

  @override
  Future<void> save(String value) async {}
}
