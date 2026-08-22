import 'secure_token_storage_base.dart';

class SecureTokenStorage implements SecureTokenStorageBase {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value.trim().isEmpty ? null : value.trim();
  }
}
