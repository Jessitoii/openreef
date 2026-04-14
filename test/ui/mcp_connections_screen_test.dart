import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_connection_store.dart';
import 'package:openreef/mcp/mcp_connections_controller.dart';
import 'package:openreef/mcp/mcp_runtime_coordinator.dart';
import 'package:openreef/mcp/mcp_secret_store.dart';
import 'package:openreef/mcp/mcp_transport.dart';
import 'package:openreef/ui/screens/mcp_connections_screen.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('only one custom MCP entry surface exists and stays above presets', (tester) async {
    final controller = await _createController();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: McpConnectionsScreen(controller: controller))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Custom MCP Server'), findsOneWidget);
    expect(find.text('Available connectors'), findsOneWidget);
    expect(find.text('Connected connectors'), findsOneWidget);
    expect(find.text('Add custom server'), findsNothing);

    expect(
      tester.getTopLeft(find.text('Custom MCP Server')).dy,
      lessThan(tester.getTopLeft(find.text('Available connectors')).dy),
    );
  });

  testWidgets('custom MCP card appears before available connectors', (tester) async {
    final controller = await _createController();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: McpConnectionsScreen(controller: controller))),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Custom MCP Server')).dy,
      lessThan(tester.getTopLeft(find.text('Available connectors')).dy),
    );
  });

  testWidgets('preset connector tap routes by setup type', (tester) async {
    final controller = await _createFakeActionController();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: McpConnectionsScreen(controller: controller))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect Home Assistant'));
    await tester.pumpAndSettle();
    expect(controller.baseUrlTokenCalls, 1);
    expect(find.text('Base URL'), findsOneWidget);
  });

  testWidgets('OAuth presets do not open manual endpoint form and are disabled', (tester) async {
    final controller = await _createFakeActionController();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: McpConnectionsScreen(controller: controller))),
    );
    await tester.pumpAndSettle();

    final oauthButton = find.widgetWithText(FilledButton, 'OAuth flow not implemented yet');
    expect(oauthButton, findsWidgets);
    final button = tester.widget<FilledButton>(oauthButton.first);
    expect(button.onPressed, isNull);
    expect(controller.oAuthCalls, 0);
    expect(find.text('MCP server URL'), findsNothing);
  });

  testWidgets('GitHub preset opens real OAuth and token actions', (tester) async {
    final controller = await _createFakeActionController();
    const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, (call) async => true);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcherChannel, null),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: McpConnectionsScreen(controller: controller))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect GitHub'));
    await tester.pumpAndSettle();

    expect(find.text('Launch OAuth'), findsOneWidget);
    expect(find.text('Connect with token'), findsOneWidget);
    await tester.tap(find.text('Launch OAuth'));
    await tester.pumpAndSettle();
    expect(controller.oAuthCalls, 1);
  });

  testWidgets('connected empty state has no duplicate add-custom CTA', (tester) async {
    final controller = await _createController();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: McpConnectionsScreen(controller: controller))),
    );
    await tester.pumpAndSettle();

    expect(find.text('No connectors are connected yet'), findsOneWidget);
    expect(find.text('Add custom server'), findsNothing);
  });

  testWidgets('manual endpoint submit is not a no-op', (tester) async {
    final controller = await _createFakeActionController();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: McpConnectionsScreen(controller: controller))),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'https://example.com/sse');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect custom server'));
    await tester.pumpAndSettle();

    expect(controller.manualConnectCalls, 1);
  });

  testWidgets('base URL + token submit is not a no-op', (tester) async {
    final controller = await _createFakeActionController();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: McpConnectionsScreen(controller: controller))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect Home Assistant'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'https://ha.example.com');
    await tester.enterText(find.byType(TextField).at(1), 'token-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect Home Assistant'));
    await tester.pumpAndSettle();

    expect(controller.baseUrlTokenCalls, 1);
  });

  testWidgets('GitHub token submit is not a no-op', (tester) async {
    final controller = await _createFakeActionController();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: McpConnectionsScreen(controller: controller))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect GitHub'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'token-456');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect with token'));
    await tester.pumpAndSettle();

    expect(controller.tokenCalls, 1);
  });

  testWidgets('screen lays out on a narrow mobile width without overflow', (tester) async {
    final controller = await _createController();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: McpConnectionsScreen(controller: controller))),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Custom MCP Server'), findsOneWidget);
    expect(find.text('Available connectors'), findsOneWidget);
  });
}

Future<McpConnectionsController> _createController() async {
  final storage = MemoryStorage(
    SqliteMemoryStorageBackend(
      path: inMemoryDatabasePath,
      databaseFactory: databaseFactoryFfi,
    ),
  );
  await storage.initialize();
  addTearDown(storage.close);

  final runtimeToolCatalog = RuntimeToolCatalog();
  final runtimeCoordinator = McpRuntimeCoordinator(
    toolCatalog: runtimeToolCatalog,
    embedText: (text) async => const <double>[0, 0, 0, 1, 0, 0, 0],
  );
  final secretStore = InMemoryMcpSecretStore();
  return McpConnectionsController(
    store: McpConnectionStore(storage, secretStore: secretStore),
    runtimeCoordinator: runtimeCoordinator,
    autoConnectPersisted: false,
    secretStore: secretStore,
    transportFactory: (endpoint, {headers = const <String, String>{}, headersProvider}) =>
        _FakeMcpTransport(endpoint),
  );
}

Future<_FakeActionController> _createFakeActionController() async {
  final storage = MemoryStorage(
    SqliteMemoryStorageBackend(
      path: inMemoryDatabasePath,
      databaseFactory: databaseFactoryFfi,
    ),
  );
  await storage.initialize();
  addTearDown(storage.close);

  final runtimeToolCatalog = RuntimeToolCatalog();
  final runtimeCoordinator = McpRuntimeCoordinator(
    toolCatalog: runtimeToolCatalog,
    embedText: (text) async => const <double>[0, 0, 0, 1, 0, 0, 0],
  );
  final secretStore = InMemoryMcpSecretStore();
  final controller = _FakeActionController(
    store: McpConnectionStore(storage, secretStore: secretStore),
    runtimeCoordinator: runtimeCoordinator,
    secretStore: secretStore,
    transportFactory: (endpoint, {headers = const <String, String>{}, headersProvider}) =>
        _FakeMcpTransport(endpoint),
  );
  return controller;
}

class _FakeActionController extends McpConnectionsController {
  _FakeActionController({
    required super.store,
    required super.runtimeCoordinator,
    required super.secretStore,
    required super.transportFactory,
  }) : super(autoConnectPersisted: false);

  int manualConnectCalls = 0;
  int baseUrlTokenCalls = 0;
  int oAuthCalls = 0;
  int tokenCalls = 0;

  @override
  Future<void> connectManualEndpoint(String url, {bool persist = true}) async {
    manualConnectCalls += 1;
  }

  @override
  Future<void> connectWithBaseUrlToken({
    required String connectorId,
    required String baseUrl,
    required String token,
    bool persist = true,
  }) async {
    baseUrlTokenCalls += 1;
  }

  @override
  Future<String?> startOAuth(String connectorId) async {
    oAuthCalls += 1;
    return 'https://auth.example.com/$connectorId';
  }

  @override
  Future<void> connectWithToken({
    required String connectorId,
    required String token,
    bool persist = true,
  }) async {
    tokenCalls += 1;
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
    _messages.add(McpTransportMessage(event: 'endpoint', data: endpoint.toString()));
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
          'serverInfo': <String, Object?>{'name': 'secure-server', 'version': '1.0.0'},
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
