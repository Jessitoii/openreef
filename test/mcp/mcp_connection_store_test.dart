import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/mcp/mcp_connection_store.dart';
import 'package:openreef/mcp/mcp_persisted_endpoint.dart';
import 'package:openreef/mcp/mcp_secret_store.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late MemoryStorage storage;
  late InMemoryMcpSecretStore secretStore;
  late McpConnectionStore store;

  setUp(() async {
    storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    secretStore = InMemoryMcpSecretStore();
    store = McpConnectionStore(
      storage,
      secretStore: secretStore,
      idGenerator: () => 'endpoint-a',
      clock: () => DateTime.utc(2026, 4, 6, 20),
    );
  });

  tearDown(() async {
    await storage.close();
  });

  test(
    'sanitizes credential-bearing persisted urls and stores secrets separately',
    () async {
      final endpoint = await store.save(
        'https://user:pass@example.com/sse?workspace=reef&access_token=abc',
        trusted: true,
      );

      final records = await storage.readRecords(
        store: MemoryStoreKind.mcpConnections,
        includeExpired: true,
      );

      expect(endpoint.id, 'endpoint-a');
      expect(endpoint.displayUri, 'https://example.com/sse?workspace=reef');
      expect(records, hasLength(1));
      expect(records.single.key, 'mcp_connection:endpoint-a');
      expect(records.single.content, isNot(contains('user:pass')));
      expect(records.single.content, isNot(contains('access_token')));
      expect(secretStore.values['endpoint-a'], isNotNull);
    },
  );

  test('migrates lossless legacy records and reconstructs runtime urls', () async {
    await storage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.mcpConnections,
        key:
            'mcp_connection:https://user:pass@example.com/sse?workspace=reef&access_token=abc',
        content: jsonEncode(<String, Object?>{
          'url':
              'https://user:pass@example.com/sse?workspace=reef&access_token=abc',
          'persistedAt': '2026-04-05T20:00:00.000Z',
        }),
        category: 'mcp_connection',
        importance: 0,
        createdAt: DateTime.utc(2026, 4, 5, 20),
      ),
    );

    final result = await store.loadAll();
    final endpoint = result.endpoints.single;
    final runtimeUrl = await store.resolveRuntimeUrl(endpoint);

    expect(
      endpoint.migrationState,
      McpPersistedEndpointMigrationState.migratedLossless,
    );
    expect(endpoint.trusted, isFalse);
    expect(endpoint.requiresManualSecretEntry, isFalse);
    expect(
      runtimeUrl,
      'https://user:pass@example.com/sse?workspace=reef&access_token=abc',
    );
    expect(secretStore.values['endpoint-a'], isNotNull);
  });

  test(
    'requires manual re-entry when legacy secret migration is not lossless',
    () async {
      await storage.saveRecord(
        MemoryRecord(
          store: MemoryStoreKind.mcpConnections,
          key: 'mcp_connection:https://example.com/sse?access_token=%2f',
          content: jsonEncode(<String, Object?>{
            'url': 'https://example.com/sse?access_token=%2f',
            'persistedAt': '2026-04-05T20:00:00.000Z',
          }),
          category: 'mcp_connection',
          importance: 0,
          createdAt: DateTime.utc(2026, 4, 5, 20),
        ),
      );

      final result = await store.loadAll();
      final endpoint = result.endpoints.single;
      final runtimeUrl = await store.resolveRuntimeUrl(endpoint);

      expect(
        endpoint.migrationState,
        McpPersistedEndpointMigrationState.manualReentryRequired,
      );
      expect(endpoint.requiresManualSecretEntry, isTrue);
      expect(runtimeUrl, isNull);
      expect(secretStore.values, isEmpty);
    },
  );
}
