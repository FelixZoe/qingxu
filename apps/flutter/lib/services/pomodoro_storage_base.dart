abstract interface class PomodoroStorageBase {
  Future<String?> load();

  Future<void> save(String value);
}
