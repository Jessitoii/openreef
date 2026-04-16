import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/mcp/mcp_connection_store.dart';
import 'package:openreef/mcp/mcp_connections_controller.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_persisted_endpoint.dart';
import 'package:openreef/mcp/mcp_runtime_coordinator.dart';
import 'package:openreef/mcp/mcp_secret_store.dart';
import 'package:openreef/mcp/mcp_transport.dart';
import 'package:openreef/ui/screens/mcp_connections_screen.dart';

void main() {
  testWidgets('custom MCP is the primary active add path', (tester) async {
    final env = await _McpTestEnvironment.create();
    await tester.pumpWidget(
      MaterialApp(home: McpConnectionsScreen(controller: env.controller)),
    );
    await tester.pump();

    expect(find.text('Custom MCP Server'), findsOneWidget);
    expect(find.text('MCP server URL'), findsOneWidget);
    expect(find.text('Connect custom server'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Custom MCP Server')).dy,
      lessThan(tester.getTopLeft(find.text('Coming soon')).dy),
    );
  });

  testWidgets('unsupported presets are passive and explanatory', (
    tester,
  ) async {
    final env = await _McpTestEnvironment.create();
    await tester.pumpWidget(
      MaterialApp(home: McpConnectionsScreen(controller: env.controller)),
    );
    await tester.pump();

    expect(find.text('Gmail'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('GitHub'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('GitHub'), findsOneWidget);
    expect(
      find.text('Requires OAuth configuration, not yet available.'),
      findsWidgets,
    );
    expect(find.text('Connect Gmail'), findsNothing);
    expect(find.text('Connect GitHub'), findsNothing);
    expect(find.text('Offline'), findsNothing);
    expect(find.text('Connected'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('manual endpoint submit attempts real custom connection', (
    tester,
  ) async {
    final env = await _McpTestEnvironment.create();
    await tester.pumpWidget(
      MaterialApp(home: McpConnectionsScreen(controller: env.controller)),
    );
    await tester.pump();

    await tester.enterText(
      find.byType(TextField).first,
      'https://example.com/sse',
    );
    await tester.tap(find.text('Connect custom server'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      env.transportEndpoints,
      contains(Uri.parse('https://example.com/sse')),
    );
    expect(env.runtimeCatalog.listTools().single.id, endsWith('/ping'));
    expect(find.text('Connected endpoints'), findsOneWidget);
    expect(find.text('1 tools imported into runtime.'), findsOneWidget);
  });

  testWidgets('invalid custom endpoint shows inline error', (tester) async {
    final env = await _McpTestEnvironment.create();
    await tester.pumpWidget(
      MaterialApp(home: McpConnectionsScreen(controller: env.controller)),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'not-a-url');
    await tester.tap(find.text('Connect custom server'));
    await tester.pump();

    expect(find.text('Use a full URL like https://host/sse.'), findsOneWidget);
    expect(env.transportEndpoints, isEmpty);
  });

  testWidgets('screen lays out on a narrow mobile width without overflow', (
    tester,
  ) async {
    final env = await _McpTestEnvironment.create();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: McpConnectionsScreen(controller: env.controller)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Custom MCP Server'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
  });
}

class _McpTestEnvironment {
  const _McpTestEnvironment({
    required this.controller,
    required this.runtimeCatalog,
    required this.transportEndpoints,
  });

  final McpConnectionsController controller;
  final RuntimeToolCatalog runtimeCatalog;
  final List<Uri> transportEndpoints;

  static Future<_McpTestEnvironment> create() async {
    final runtimeCatalog = RuntimeToolCatalog();
    final runtimeCoordinator = McpRuntimeCoordinator(
      toolCatalog: runtimeCatalog,
      embedText: (text) async => const <double>[0, 0, 0, 1, 0, 0, 0],
    );
    final secretStore = InMemoryMcpSecretStore();
    final endpoints = <Uri>[];
    final store = _InMemoryMcpConnectionStore();
    final controller = McpConnectionsController(
      store: store,
      runtimeCoordinator: runtimeCoordinator,
      autoConnectPersisted: false,
      secretStore: secretStore,
      transportFactory:
          (endpoint, {headers = const <String, String>{}, headersProvider}) {
            endpoints.add(endpoint);
            return _FakeMcpTransport(endpoint);
          },
    );
    addTearDown(controller.dispose);
    return _McpTestEnvironment(
      controller: controller,
      runtimeCatalog: runtimeCatalog,
      transportEndpoints: endpoints,
    );
  }
}

class _InMemoryMcpConnectionStore implements McpConnectionStore {
  _InMemoryMcpConnectionStore();

  final Map<String, McpPersistedEndpoint> _endpoints =
      <String, McpPersistedEndpoint>{};
  int _nextId = 0;

  @override
  Future<McpPersistedEndpoint> save(
    String rawUrl, {
    required bool trusted,
  }) async {
    _nextId += 1;
    final uri = Uri.parse(rawUrl);
    final now = DateTime(2026, 1, 1).toUtc();
    final endpoint = McpPersistedEndpoint(
      id: 'custom-$_nextId',
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      publicQuerySegments: uri.queryParameters.entries
          .map(
            (entry) =>
                McpQuerySegment(index: 0, key: entry.key, value: entry.value),
          )
          .toList(growable: false),
      trusted: trusted,
      migrationState: McpPersistedEndpointMigrationState.nativeTrusted,
      createdAt: now,
      persistedAt: now,
    );
    _endpoints[endpoint.id] = endpoint;
    return endpoint;
  }

  @override
  Future<McpPersistedEndpoint> saveConnectorEndpoint({
    required String connectorId,
    required String runtimeUrl,
    required bool trusted,
    required String credentialRef,
    required String credentialType,
  }) {
    throw UnsupportedError('preset connectors are not used in this test');
  }

  @override
  Future<void> deleteById(String endpointId) async {
    _endpoints.remove(endpointId);
  }

  @override
  Future<McpConnectionStoreLoadResult> loadAll() async {
    return McpConnectionStoreLoadResult(
      endpoints: List<McpPersistedEndpoint>.unmodifiable(_endpoints.values),
    );
  }

  @override
  Future<String?> resolveRuntimeUrl(McpPersistedEndpoint endpoint) async {
    return endpoint.buildRuntimeUri();
  }
}

class _FakeMcpTransport implements McpTransport {
  _FakeMcpTransport(this.endpoint);

  final Uri endpoint;
  final StreamController<McpTransportMessage> _messages =
      StreamController<McpTransportMessage>.broadcast();

  @override
  Stream<McpTransportMessage> get messages => _messages.stream;

  @override
  Future<void> connect() async {
    Timer(
      const Duration(milliseconds: 10),
      () => _messages.add(
        McpTransportMessage(event: 'endpoint', data: endpoint.toString()),
      ),
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
    await _messages.close();
  }
}
