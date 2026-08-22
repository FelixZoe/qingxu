abstract interface class SecureTokenStorageBase {
  Future<String?> read();

  Future<void> write(String value);
}
