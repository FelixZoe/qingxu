import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'theme_mode_storage_base.dart';

class ThemeModeStorage implements ThemeModeStorageBase {
  Future<File> get _file async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}${Platform.pathSeparator}theme.txt');
  }

  @override
  Future<String?> load() async {
    final file = await _file;
    if (!await file.exists()) return null;
    return (await file.readAsString()).trim();
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
