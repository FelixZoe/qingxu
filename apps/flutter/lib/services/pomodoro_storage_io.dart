import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'pomodoro_storage_base.dart';

class PomodoroStorage implements PomodoroStorageBase {
  Future<File> get _file async {
    if (Platform.isWindows) {
      final root = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      return File(
        '$root${Platform.pathSeparator}Qingxu${Platform.pathSeparator}pomodoro.json',
      );
    }
    if (Platform.isIOS) {
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      return File(
        '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}Qingxu${Platform.pathSeparator}pomodoro.json',
      );
    }
    final support = await getApplicationSupportDirectory();
    return File('${support.path}${Platform.pathSeparator}pomodoro.json');
  }

  @override
  Future<String?> load() async {
    final file = await _file;
    try {
      if (!await file.exists()) return null;
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> save(String value) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
