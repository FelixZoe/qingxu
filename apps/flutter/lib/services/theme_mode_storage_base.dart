abstract interface class ThemeModeStorageBase {
  Future<String?> load();

  Future<void> save(String value);
}
