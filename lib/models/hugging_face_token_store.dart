import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class HuggingFaceTokenStore {
  Future<bool> hasTokenForModel(String modelId);

  Future<String?> readTokenForModel(String modelId);

  Future<void> writeTokenForModel(String modelId, String token);

  Future<void> deleteTokenForModel(String modelId);
}

class SecureHuggingFaceTokenStore implements HuggingFaceTokenStore {
  const SecureHuggingFaceTokenStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<void> deleteTokenForModel(String modelId) {
    return _storage.delete(key: _key(modelId));
  }

  @override
  Future<bool> hasTokenForModel(String modelId) async {
    final token = await readTokenForModel(modelId);
    return token != null && token.trim().isNotEmpty;
  }

  @override
  Future<String?> readTokenForModel(String modelId) {
    return _storage.read(key: _key(modelId));
  }

  @override
  Future<void> writeTokenForModel(String modelId, String token) {
    return _storage.write(key: _key(modelId), value: token.trim());
  }

  String _key(String modelId) => 'openreef.hf_token.$modelId';
}
