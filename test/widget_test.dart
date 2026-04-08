import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/memory/chat_session_repository.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/mcp/mcp_connection_store.dart';
import 'package:openreef/mcp/mcp_connections_controller.dart';
import 'package:openreef/mcp/mcp_runtime_coordinator.dart';
import 'package:openreef/mcp/mcp_secret_store.dart';
import 'package:openreef/models/litert_bridge.dart';
import 'package:openreef/models/model_download_controller.dart';
import 'package:openreef/models/model_downloader.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:openreef/models/model_storage.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/settings/settings_store.dart';
import 'package:openreef/skills/skill_registry.dart';
import 'package:openreef/skills/skill_registry_controller.dart';
import 'package:openreef/skills/skill_runtime_catalog.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/mock_chat_session.dart';
import 'package:openreef/ui/openreef_app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const MethodChannel _deviceStatsChannel = MethodChannel(
  'openreef/device_stats',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_deviceStatsChannel, (call) async {
          if (call.method == 'getDeviceStats') {
            return <String, Object?>{'freeRamGb': 6.0, 'npuReady': false};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_deviceStatsChannel, null);
  });

  testWidgets('app boots into drawer-driven chat shell', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(await _buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('OpenReef'), findsOneWidget);
    expect(find.byKey(const Key('chat-composer')), findsOneWidget);
  });

  testWidgets('sending a message shows user text and mock reply', (
    tester,
  ) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(await _buildApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'Check theme status',
    );
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pumpAndSettle();

    expect(find.textContaining('Check theme status'), findsOneWidget);
    expect(find.textContaining('Theme changes are live.'), findsOneWidget);
  });

  testWidgets('sub-agent activity blocks can expand during execution', (
    tester,
  ) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(await _buildApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'Check voice pipeline',
    );
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pump();

    expect(find.text('planner.daemon'), findsOneWidget);
    expect(
      find.textContaining('Input classified as offline chat request.'),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('activity-planner')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.textContaining('Input classified as offline chat request.'),
      findsOneWidget,
    );
  });

  testWidgets('drawer can create and switch recent chats', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(await _buildApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'First conversation for persistence',
    );
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-drawer-button')));
    await tester.pumpAndSettle();
    expect(find.text('RECENT CHATS'), findsOneWidget);
    expect(find.text('First conversation for persistence'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-chat-button')));
    await tester.pumpAndSettle();

    expect(find.text('First conversation for persistence'), findsNothing);

    await tester.tap(find.byKey(const Key('open-drawer-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First conversation for persistence'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('First conversation for persistence'),
      findsOneWidget,
    );
  });

  testWidgets(
    'settings are reachable from drawer and unavailable wake runtime is labeled',
    (tester) async {
      _setLargeSurface(tester);
      await tester.pumpWidget(await _buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-drawer-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('drawer-settings')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.light);

      expect(
        find.textContaining(
          'Unavailable until a Picovoice access key is provisioned',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Wake Sensitivity (inactive until wake runtime is configured) 0.7',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('models screen launches from drawer', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(await _buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-drawer-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-models')));
    await tester.pumpAndSettle();

    expect(find.text('Choose a model'), findsOneWidget);
  });

  testWidgets('skills and mcp placeholders are reachable from drawer', (
    tester,
  ) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(await _buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-drawer-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-skills')));
    await tester.pumpAndSettle();
    expect(find.text('SKILL REGISTRY'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-drawer-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-mcp')));
    await tester.pumpAndSettle();
    expect(find.text('MCP CONNECTIONS'), findsOneWidget);
  });
}

Future<Widget> _buildApp({
  SettingsController? settingsController,
  ChatSessionPort? chatSession,
}) async {
  final modelStorage = ModelStorage(
    directoryResolver: () async =>
        Directory.systemTemp.createTemp('widget-app-models-'),
  );
  final sessionDirectory = await Directory.systemTemp.createTemp(
    'widget-chat-sessions-',
  );
  final sessionRepository = ChatSessionRepository(
    path: '${sessionDirectory.path}${Platform.pathSeparator}chat.sqlite',
    databaseFactory: databaseFactoryFfi,
  );
  final memoryDatabase = await Directory.systemTemp.createTemp(
    'widget-memory-',
  );
  final memoryStorage = MemoryStorage(
    SqliteMemoryStorageBackend(
      path: '${memoryDatabase.path}${Platform.pathSeparator}memory.sqlite',
      databaseFactory: databaseFactoryFfi,
    ),
  );
  await memoryStorage.initialize();
  final skillsDirectory = await Directory.systemTemp.createTemp(
    'widget-skills-',
  );
  final skillCatalog = SkillRuntimeCatalog(
    registry: SkillRegistry(rootPaths: <String>[skillsDirectory.path]),
    toolCatalog: InMemoryToolCatalog(const <ToolDefinition>[]),
    stateFile: File(
      '${skillsDirectory.path}${Platform.pathSeparator}runtime_state.json',
    ),
  );
  await skillCatalog.reload();
  final skillRegistryController = SkillRegistryController(
    catalog: skillCatalog,
  );
  final mcpConnectionsController = McpConnectionsController(
    store: McpConnectionStore(
      memoryStorage,
      secretStore: InMemoryMcpSecretStore(),
    ),
    runtimeCoordinator: McpRuntimeCoordinator(
      toolCatalog: RuntimeToolCatalog(),
      embedText: (text) async => const <double>[0, 0, 0, 0, 1, 0, 0],
    ),
    autoConnectPersisted: false,
  );

  return OpenReefApp(
    settingsController: settingsController ??
        SettingsController(
          store: SettingsStore(
            File(
              '${sessionDirectory.path}${Platform.pathSeparator}settings.json',
            ),
          ),
        ),
    chatSession: chatSession ?? MockChatSession(),
    chatSessionRepository: sessionRepository,
    modelDownloadController: ModelDownloadController(
      registry: const ModelRegistry(),
      storage: modelStorage,
      downloader: ModelDownloader(storage: modelStorage),
      bridge: LiteRtBridge(),
    ),
    skillRegistryController: skillRegistryController,
    mcpConnectionsController: mcpConnectionsController,
    modelReady: true,
    onModelReady: () async {},
  );
}

void _setLargeSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 2200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
