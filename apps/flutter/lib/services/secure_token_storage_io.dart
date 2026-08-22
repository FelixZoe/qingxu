import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_token_storage_base.dart';

class SecureTokenStorage implements SecureTokenStorageBase {
  SecureTokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  static const _key = 'qingxu.sync.token.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: normalized);
    }
  }
}
