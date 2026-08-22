import 'sync_settings_storage_base.dart';

class SyncSettingsStorage implements SyncSettingsStorageBase {
  String? _value;

  @override
  Future<String?> load() async => _value;

  @override
  Future<void> save(String value) async {
    _value = value;
  }
}
