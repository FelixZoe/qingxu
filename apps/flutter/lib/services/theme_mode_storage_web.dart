import 'package:web/web.dart' as web;

import 'theme_mode_storage_base.dart';

class ThemeModeStorage implements ThemeModeStorageBase {
  static const _key = 'qingxu.theme.v1';

  @override
  Future<String?> load() async => web.window.localStorage.getItem(_key);

  @override
  Future<void> save(String value) async {
    web.window.localStorage.setItem(_key, value);
  }
}
