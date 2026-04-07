import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class McpSecretStore {
  Future<void> writeSecret(String key, String value);

  Future<String?> readSecret(String key);

  Future<void> deleteSecret(String key);
}

class PlatformMcpSecretStore implements McpSecretStore {
  PlatformMcpSecretStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'openreef/mcp_secret_store';

  final MethodChannel _channel;

  @override
  Future<void> writeSecret(String key, String value) async {
    await _channel.invokeMethod<void>('writeSecret', <String, Object?>{
      'key': key,
      'value': value,
    });
  }

  @override
  Future<String?> readSecret(String key) {
    return _channel.invokeMethod<String>('readSecret', <String, Object?>{
      'key': key,
    });
  }

  @override
  Future<void> deleteSecret(String key) async {
    await _channel.invokeMethod<void>('deleteSecret', <String, Object?>{
      'key': key,
    });
  }
}

class InMemoryMcpSecretStore implements McpSecretStore {
  final Map<String, String> _values = <String, String>{};

  @visibleForTesting
  Map<String, String> get values => _values;

  @override
  Future<void> writeSecret(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> readSecret(String key) async {
    return _values[key];
  }

  @override
  Future<void> deleteSecret(String key) async {
    _values.remove(key);
  }
}
