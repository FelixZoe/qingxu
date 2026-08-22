import 'package:web/web.dart' as web;

import 'task_storage_base.dart';

class TaskStorage implements TaskStorageBase {
  static const _key = 'qingxu.tasks.v1';

  @override
  Future<String?> load() async => web.window.localStorage.getItem(_key);

  @override
  Future<void> save(String value) async {
    web.window.localStorage.setItem(_key, value);
  }
}
