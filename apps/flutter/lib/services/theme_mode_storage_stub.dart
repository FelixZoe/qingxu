import 'theme_mode_storage_base.dart';

class ThemeModeStorage implements ThemeModeStorageBase {
  String? _value;

  @override
  Future<String?> load() async => _value;

  @override
  Future<void> save(String value) async => _value = value;
}
