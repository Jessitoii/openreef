import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/mcp/mcp_connection_store.dart';
import 'package:openreef/mcp/mcp_connections_controller.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_secret_store.dart';
import 'package:openreef/mcp/mcp_transport.dart';
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
  late List<Uri> connectedEndpoints;

  setUp(() async {
    storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    secretStore = InMemoryMcpSecretStore();
    connectedEndpoints = <Uri>[];
    store = McpConnectionStore(
      storage,
      secretStore: secretStore,
      idGenerator: () => 'endpoint-${DateTime.now().microsecondsSinceEpoch}',
      clock: () => DateTime.utc(2026, 4, 6, 20),
    );
  });

  tearDown(() async {
    await storage.close();
  });

  test(
    'auto-connects only trusted persisted endpoints and uses secure secrets',
    () async {
      final trustedEndpoint = await store.save(
        'https://user:pass@example.com/sse?workspace=reef&access_token=abc',
        trusted: true,
      );
      await storage.saveRecord(
        MemoryRecord(
          store: MemoryStoreKind.mcpConnections,
          key: 'mcp_connection:legacy-raw',
          content:
              '{"url":"https://legacy.example.com/sse?access_token=%2f","persistedAt":"2026-04-05T20:00:00.000Z"}',
          category: 'mcp_connection',
          importance: 0,
          createdAt: DateTime.utc(2026, 4, 5, 20),
        ),
      );

      final controller = McpConnectionsController(
        store: store,
        transportFactory: (endpoint) {
          connectedEndpoints.add(endpoint);
          return _FakeMcpTransport(endpoint);
        },
      );

      await controller.initialize();

      expect(connectedEndpoints, hasLength(1));
      expect(
        connectedEndpoints.single.toString(),
        'https://user:pass@example.com/sse?workspace=reef&access_token=abc',
      );
      final states = controller.connections.value;
      final trustedState = states.firstWhere(
        (state) => state.endpointId == trustedEndpoint.id,
      );
      final legacyState = states.firstWhere(
        (state) => state.endpointId != trustedEndpoint.id,
      );
      expect(trustedState.status, McpConnectionStatus.connected);
      expect(legacyState.status, McpConnectionStatus.disconnected);
      expect(legacyState.trusted, isFalse);
    },
  );

  test(
    'manual reconnect fails safely when legacy migration needs re-entry',
    () async {
      await storage.saveRecord(
        MemoryRecord(
          store: MemoryStoreKind.mcpConnections,
          key: 'mcp_connection:legacy-raw',
          content:
              '{"url":"https://legacy.example.com/sse?access_token=%2f","persistedAt":"2026-04-05T20:00:00.000Z"}',
          category: 'mcp_connection',
          importance: 0,
          createdAt: DateTime.utc(2026, 4, 5, 20),
        ),
      );

      final controller = McpConnectionsController(
        store: store,
        transportFactory: (endpoint) => _FakeMcpTransport(endpoint),
      );

      await controller.initialize();
      final endpointId = controller.connections.value.single.endpointId!;
      await controller.reconnectPersisted(endpointId);

      final state = controller.connections.value.single;
      expect(state.status, McpConnectionStatus.error);
      expect(state.errorMessage, 'manual_secret_reentry_required');
      expect(state.requiresManualSecretEntry, isTrue);
    },
  );

  test('rejects unsafe manual endpoint schemes before connect', () async {
    final controller = McpConnectionsController(
      store: store,
      transportFactory: (endpoint) => _FakeMcpTransport(endpoint),
    );

    await controller.connect('http://example.com/sse', persist: false);

    final state = controller.connections.value.single;
    expect(state.status, McpConnectionStatus.error);
    expect(state.errorMessage, contains('unsafe_endpoint_scheme'));
  });
}

class _FakeMcpTransport implements McpTransport {
  _FakeMcpTransport(this.endpoint);

  final Uri endpoint;
  final StreamController<McpTransportMessage> _messages =
      StreamController<McpTransportMessage>.broadcast();
  var _closed = false;

  @override
  Stream<McpTransportMessage> get messages => _messages.stream;

  @override
  Future<void> connect() async {
    _messages.add(
      McpTransportMessage(event: 'endpoint', data: endpoint.toString()),
    );
  }

  @override
  Future<McpJsonRpcResponse> sendRequest(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
  }) async {
    if (method == 'initialize') {
      return const McpJsonRpcResponse(
        id: 1,
        result: <String, Object?>{
          'protocolVersion': '2024-11-05',
          'serverInfo': <String, Object?>{
            'name': 'secure-server',
            'version': '1.0.0',
          },
        },
      );
    }
    if (method == 'tools/list') {
      return const McpJsonRpcResponse(
        id: 2,
        result: <String, Object?>{
          'tools': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'ping',
              'description': 'Returns pong',
              'inputSchema': <String, Object?>{'type': 'object'},
            },
          ],
        },
      );
    }
    throw StateError('Unexpected method: $method');
  }

  @override
  Future<void> sendNotification(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
  }) async {}

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _messages.close();
  }
}
