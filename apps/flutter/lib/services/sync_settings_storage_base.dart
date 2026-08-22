abstract interface class SyncSettingsStorageBase {
  Future<String?> load();

  Future<void> save(String value);
}
