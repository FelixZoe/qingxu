import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'sync_settings_storage_base.dart';

class SyncSettingsStorage implements SyncSettingsStorageBase {
  Future<File> get _file async {
    if (Platform.isWindows) {
      final root = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      return File(
        '$root${Platform.pathSeparator}Qingxu${Platform.pathSeparator}sync.json',
      );
    }
    if (Platform.isIOS) {
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      return File(
        '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}Qingxu${Platform.pathSeparator}sync.json',
      );
    }
    final support = await getApplicationSupportDirectory();
    return File('${support.path}${Platform.pathSeparator}sync.json');
  }

  @override
  Future<String?> load() async {
    final file = await _file;
    if (!await file.exists()) return null;
    return file.readAsString();
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
