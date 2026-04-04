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
import 'package:openreef/models/model_download_controller.dart';
import 'package:openreef/models/model_downloader.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:openreef/models/model_storage.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/tools/mvp_native_tools.dart';
import 'package:openreef/tools/platform_native_tool_adapters.dart';
import 'package:openreef/tools/tool_manifest_bridge.dart';
import 'package:openreef/tools/tool_manifest_registry.dart';
import 'package:openreef/triggers/trigger_event_bridge.dart';
import 'package:openreef/ui/agent_loop_chat_session.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/openreef_app.dart';
import 'package:openreef/voice/audio_service.dart';
import 'package:openreef/voice/wake_word_controller.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await OpenReefBootstrap.initialize();
  runApp(MyApp(bootstrap: bootstrap));
}

class MyApp extends StatefulWidget {
  const MyApp({required this.bootstrap, super.key});

  final OpenReefBootstrap bootstrap;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late bool _modelReady = widget.bootstrap.modelReady;

  Future<void> _handleModelReady() async {
    final installedModel =
        widget.bootstrap.modelDownloadController.state.installedModel;
    if (installedModel == null) {
      return;
    }
    widget.bootstrap.modelDownloadController.markInitializingModel();
    try {
      await widget.bootstrap.initializeModelAtPath(installedModel.path);
      if (!mounted) {
        return;
      }
      setState(() {
        _modelReady = true;
      });
    } catch (error) {
      await widget.bootstrap.modelDownloadController
          .recoverFromCorruptInstalledModel(installedModel);
      widget.bootstrap.modelDownloadController.setInitializationError(error);
      if (!mounted) {
        return;
      }
      setState(() {
        _modelReady = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return OpenReefApp(
      settingsController: widget.bootstrap.settingsController,
      chatSession: widget.bootstrap.chatSession,
      modelDownloadController: widget.bootstrap.modelDownloadController,
      modelReady: _modelReady,
      onModelReady: _handleModelReady,
    );
  }
}

Future<void> initializeLiteRtModelAtPath(
  LiteRtBridge bridge, {
  required String path,
}) {
  return OpenReefBootstrap.initializeLiteRtBridge(bridge, path: path);
}

class OpenReefBootstrap {
  OpenReefBootstrap._({
    required this.settingsController,
    required this.chatSession,
    required this.modelDownloadController,
    required this.liteRtBridge,
    required this.audioService,
    required this.triggerEventBridge,
    required this.wakeWordController,
    required this.modelReady,
  });

  final SettingsController settingsController;
  final ChatSessionPort chatSession;
  final ModelDownloadController modelDownloadController;
  final LiteRtBridge liteRtBridge;
  final AudioService audioService;
  final TriggerEventBridge triggerEventBridge;
  final WakeWordController wakeWordController;
  final bool modelReady;

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
    final modelRegistry = const ModelRegistry();
    final modelStorage = ModelStorage();
    final modelDownloader = ModelDownloader(storage: modelStorage);
    final modelDownloadController = ModelDownloadController(
      registry: modelRegistry,
      storage: modelStorage,
      downloader: modelDownloader,
      bridge: liteRtBridge,
    );
    await modelDownloadController.initialize();

    var modelReady = false;
    final installedModel = modelDownloadController.state.installedModel;
    if (installedModel != null) {
      try {
        await initializeLiteRtBridge(liteRtBridge, path: installedModel.path);
        modelReady = true;
      } catch (error) {
        await modelDownloadController.recoverFromCorruptInstalledModel(
          installedModel,
        );
        modelDownloadController.setInitializationError(error);
        modelReady = false;
      }
    }

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

    final settingsController = SettingsController();
    final triggerEventBridge = TriggerEventBridge();
    return OpenReefBootstrap._(
      settingsController: settingsController,
      chatSession: AgentLoopChatSession(agentLoop: agentLoop),
      modelDownloadController: modelDownloadController,
      liteRtBridge: liteRtBridge,
      audioService: AudioService(settingsController: settingsController),
      triggerEventBridge: triggerEventBridge,
      wakeWordController: WakeWordController(
        settingsController: settingsController,
      ),
      modelReady: modelReady,
    );
  }

  Future<void> initializeModelAtPath(String path) {
    return initializeLiteRtBridge(liteRtBridge, path: path);
  }

  static Future<void> initializeLiteRtBridge(
    LiteRtBridge bridge, {
    required String path,
  }) async {
    var useNpu = false;

    try {
      final stats = await bridge.getDeviceStats();
      useNpu = stats.npuReady;
    } on PlatformException {
      useNpu = false;
    }

    try {
      await bridge.initModel(path: path, useNpu: useNpu);
    } on PlatformException catch (error) {
      if (error.code != 'ERR_NPU_FALLBACK' || !useNpu) {
        rethrow;
      }
      await bridge.initModel(path: path, useNpu: false);
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
