import 'task_storage_base.dart';

class TaskStorage implements TaskStorageBase {
  String? _value;

  @override
  Future<String?> load() async => _value;

  @override
  Future<void> save(String value) async {
    _value = value;
  }
}
