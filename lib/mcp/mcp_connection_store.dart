import 'dart:convert';

import 'package:openreef/mcp/mcp_endpoint_policy.dart';
import 'package:openreef/mcp/mcp_persisted_endpoint.dart';
import 'package:openreef/mcp/mcp_secret_store.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';

class McpConnectionStoreLoadResult {
  const McpConnectionStoreLoadResult({required this.endpoints});

  final List<McpPersistedEndpoint> endpoints;
}

class McpConnectionStore {
  McpConnectionStore(
    this._storage, {
    required McpSecretStore secretStore,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _secretStore = secretStore,
       _clock = clock ?? _defaultClock,
       _idGenerator = idGenerator ?? McpEndpointPolicy.generateStableId;

  final MemoryStorage _storage;
  final McpSecretStore _secretStore;
  final DateTime Function() _clock;
  final String Function() _idGenerator;

  Future<McpPersistedEndpoint> save(
    String rawUrl, {
    required bool trusted,
  }) async {
    final now = _clock().toUtc();
    final normalized = McpEndpointPolicy.normalizeForPersistence(
      id: _idGenerator(),
      rawUrl: rawUrl,
      trusted: trusted,
      migrationState: McpPersistedEndpointMigrationState.nativeTrusted,
      createdAt: now,
      persistedAt: now,
    );
    var endpoint = normalized.endpoint;
    if (normalized.secrets.hasSecrets && !normalized.isLossless) {
      endpoint = endpoint.copyWith(
        trusted: false,
        secretRef: null,
        migrationState:
            McpPersistedEndpointMigrationState.manualReentryRequired,
      );
    } else if (normalized.secrets.hasSecrets) {
      await _secretStore.writeSecret(
        normalized.endpoint.id,
        normalized.secrets.encode(),
      );
    }
    await _storage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.mcpConnections,
        key: endpoint.storageKey,
        content: endpoint.encode(),
        category: 'mcp_connection',
        importance: 0,
        createdAt: now,
      ),
    );
    return endpoint;
  }

  Future<void> deleteById(String endpointId) async {
    await _secretStore.deleteSecret(endpointId);
    await _storage.deleteRecord(_keyFor(endpointId));
  }

  Future<McpConnectionStoreLoadResult> loadAll() async {
    final records = await _storage.readRecords(
      store: MemoryStoreKind.mcpConnections,
      includeExpired: true,
    );
    final endpoints = <McpPersistedEndpoint>[];
    for (final record in records) {
      final parsed = await _parseRecord(record);
      if (parsed != null) {
        endpoints.add(parsed);
      }
    }
    return McpConnectionStoreLoadResult(
      endpoints: List<McpPersistedEndpoint>.unmodifiable(endpoints),
    );
  }

  Future<String?> resolveRuntimeUrl(McpPersistedEndpoint endpoint) async {
    if (endpoint.requiresManualSecretEntry) {
      return null;
    }
    McpEndpointSecrets? secrets;
    if (endpoint.secretRef != null && endpoint.secretRef!.isNotEmpty) {
      final rawSecrets = await _secretStore.readSecret(endpoint.secretRef!);
      if (rawSecrets == null || rawSecrets.trim().isEmpty) {
        if (endpoint.requiresSecret) {
          return null;
        }
      } else {
        secrets = McpEndpointSecrets.decode(rawSecrets);
      }
    }
    return endpoint.buildRuntimeUri(secrets: secrets);
  }

  Future<McpPersistedEndpoint?> _parseRecord(MemoryRecord record) async {
    if (record.content.trim().isEmpty) {
      return null;
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(record.content);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    final map = decoded.cast<String, Object?>();
    if ((map['version'] as num?)?.toInt() == 2) {
      return McpPersistedEndpoint.fromJson(map);
    }
    final url = map['url'];
    if (url is! String || url.trim().isEmpty) {
      return null;
    }
    return _migrateLegacyRecord(record, url.trim());
  }

  Future<McpPersistedEndpoint?> _migrateLegacyRecord(
    MemoryRecord record,
    String rawUrl,
  ) async {
    final now = _clock().toUtc();
    final migratedAt =
        DateTime.tryParse(_readPersistedAt(record.content)) ?? now;
    try {
      final migrated = McpEndpointPolicy.normalizeForPersistence(
        id: _idGenerator(),
        rawUrl: rawUrl,
        trusted: false,
        migrationState: McpPersistedEndpointMigrationState.migratedLossless,
        createdAt: record.createdAt.toUtc(),
        persistedAt: migratedAt.toUtc(),
      );
      if (migrated.secrets.hasSecrets && !migrated.isLossless) {
        final placeholder = migrated.endpoint.copyWith(
          secretRef: null,
          trusted: false,
          migrationState:
              McpPersistedEndpointMigrationState.manualReentryRequired,
        );
        await _storage.saveRecord(
          record.copyWith(
            key: placeholder.storageKey,
            content: placeholder.encode(),
            createdAt: placeholder.createdAt,
          ),
        );
        if (record.key != placeholder.storageKey) {
          await _storage.deleteRecord(record.key);
        }
        return placeholder;
      }
      if (migrated.secrets.hasSecrets) {
        await _secretStore.writeSecret(
          migrated.endpoint.id,
          migrated.secrets.encode(),
        );
      }
      await _storage.saveRecord(
        record.copyWith(
          key: migrated.endpoint.storageKey,
          content: migrated.endpoint.encode(),
          createdAt: migrated.endpoint.createdAt,
        ),
      );
      if (record.key != migrated.endpoint.storageKey) {
        await _storage.deleteRecord(record.key);
      }
      return migrated.endpoint;
    } on Exception {
      return null;
    }
  }

  String _readPersistedAt(String rawContent) {
    final decoded = jsonDecode(rawContent);
    if (decoded is! Map) {
      return '';
    }
    final value = decoded['persistedAt'];
    return value is String ? value : '';
  }

  String _keyFor(String endpointId) => 'mcp_connection:$endpointId';

  static DateTime _defaultClock() => DateTime.now().toUtc();
}

extension on McpPersistedEndpoint {
  McpPersistedEndpoint copyWith({
    bool? trusted,
    String? secretRef,
    McpPersistedEndpointMigrationState? migrationState,
  }) {
    return McpPersistedEndpoint(
      id: id,
      scheme: scheme,
      host: host,
      port: port,
      path: path,
      publicQuerySegments: publicQuerySegments,
      trusted: trusted ?? this.trusted,
      secretRef: secretRef,
      requiresSecret: requiresSecret,
      migrationState: migrationState ?? this.migrationState,
      createdAt: createdAt,
      persistedAt: persistedAt,
    );
  }
}
