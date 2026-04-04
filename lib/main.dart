import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openreef/agent/agent_loop.dart';
import 'package:openreef/agent/agent_model_adapter.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/bootstrap_context_services.dart';
import 'package:openreef/context/compactor.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_former.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/models/litert_bridge.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/tools/mvp_native_tools.dart';
import 'package:openreef/tools/platform_native_tool_adapters.dart';
import 'package:openreef/tools/tool_manifest_bridge.dart';
import 'package:openreef/tools/tool_manifest_registry.dart';
import 'package:openreef/ui/agent_loop_chat_session.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/openreef_app.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await OpenReefBootstrap.initialize();
  runApp(
    MyApp(
      settingsController: bootstrap.settingsController,
      chatSession: bootstrap.chatSession,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    required this.settingsController,
    required this.chatSession,
    super.key,
  });

  final SettingsController settingsController;
  final ChatSessionPort chatSession;

  @override
  Widget build(BuildContext context) {
    return OpenReefApp(
      settingsController: settingsController,
      chatSession: chatSession,
    );
  }
}

class OpenReefBootstrap {
  OpenReefBootstrap._({
    required this.settingsController,
    required this.chatSession,
  });

  final SettingsController settingsController;
  final ChatSessionPort chatSession;

  static Future<OpenReefBootstrap> initialize() async {
    final databaseFactory = _resolveDatabaseFactory();
    final memoryStorage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: await _databasePath(),
        databaseFactory: databaseFactory,
      ),
    );
    await memoryStorage.initialize();

    final memoryIndex = MemoryIndex(memoryStorage);
    final memoryFormer = MemoryFormer(
      storage: memoryStorage,
      memoryIndex: memoryIndex,
    );

    final toolRegistry = ToolManifestRegistry(
      createMvpNativeToolHandlers(
        volumeAdapter: PlatformVolumeAdapter(),
        clipboardAdapter: const PlatformClipboardAdapter(),
        batteryAdapter: PlatformBatteryAdapter(),
      ),
    );
    final toolBridge = ToolManifestBridge(toolRegistry);
    final toolCatalog = InMemoryToolCatalog(<ToolDefinition>[
      toolBridge.toToolDefinition(
        toolId: 'volume_set',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'clipboard_read',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'battery_info',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
    ]);

    final liteRtBridge = LiteRtBridge();
    await _initializeLiteRtBridge(liteRtBridge);

    final contextAssembler = ContextAssembler(
      memoryIndex: memoryIndex,
      embedder: const KeywordIntentEmbedder(),
      toolCatalog: toolCatalog,
      skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
      memoryContextProvider: MemoryStorageContextProvider(memoryStorage),
    );
    final agentLoop = AgentLoop(
      contextAssembler: contextAssembler,
      compactor: const ReefCompactor(summarizer: InlineCompactionSummarizer()),
      modelAdapter: LiteRtAgentModelAdapter(bridge: liteRtBridge),
      toolRouter: ToolRouter(
        catalog: toolCatalog,
        mailbox: AgentMailbox(),
        confirmToolCall: (call) async => false,
      ),
      memoryFormer: memoryFormer,
    );

    return OpenReefBootstrap._(
      settingsController: SettingsController(),
      chatSession: AgentLoopChatSession(agentLoop: agentLoop),
    );
  }

  static Future<void> _initializeLiteRtBridge(LiteRtBridge bridge) async {
    const modelPath = 'assets/models/openreef_default.litertlm';
    var useNpu = false;

    try {
      final stats = await bridge.getDeviceStats();
      useNpu = stats.npuReady;
    } on PlatformException {
      useNpu = false;
    }

    try {
      await bridge.initModel(path: modelPath, useNpu: useNpu);
    } on PlatformException catch (error) {
      if (error.code != 'ERR_NPU_FALLBACK' || !useNpu) {
        rethrow;
      }
      await bridge.initModel(path: modelPath, useNpu: false);
    }
  }

  static DatabaseFactory _resolveDatabaseFactory() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return databaseFactorySqflitePlugin;
  }

  static Future<String> _databasePath() async {
    final basePath = await getDatabasesPath();
    final separator = Platform.pathSeparator;
    return '$basePath${basePath.endsWith(separator) ? '' : separator}openreef.sqlite';
  }
}
