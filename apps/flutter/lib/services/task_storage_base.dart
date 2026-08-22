abstract interface class TaskStorageBase {
  Future<String?> load();

  Future<void> save(String value);
}

