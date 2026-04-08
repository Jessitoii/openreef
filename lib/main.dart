import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openreef/agent/agent_loop.dart';
import 'package:openreef/agent/agent_model_adapter.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/agent_notifier.dart';
import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/execution_log.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/bootstrap_context_services.dart';
import 'package:openreef/context/compactor.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_former.dart';
import 'package:openreef/memory/memory_formation_service.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/semantic_memory_retriever.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
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
import 'package:openreef/settings/settings_store.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/skills/skill_registry.dart';
import 'package:openreef/skills/skill_registry_controller.dart';
import 'package:openreef/skills/skill_runtime_catalog.dart';
import 'package:openreef/tools/mvp_native_tools.dart';
import 'package:openreef/tools/platform_native_tool_adapters.dart';
import 'package:openreef/tools/tool_manifest_bridge.dart';
import 'package:openreef/tools/tool_manifest_registry.dart';
import 'package:openreef/triggers/android_schedule_scheduler_backend.dart';
import 'package:openreef/triggers/in_process_interval_scheduler_backend.dart';
import 'package:openreef/triggers/mini_kairos.dart';
import 'package:openreef/triggers/trigger_repository.dart';
import 'package:openreef/triggers/trigger_event_bridge.dart';
import 'package:openreef/triggers/trigger_system.dart';
import 'package:openreef/ui/agent_loop_chat_session.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/openreef_app.dart';
import 'package:openreef/voice/audio_service.dart';
import 'package:openreef/voice/wake_word_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
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
      await widget.bootstrap.initializeModelAtPath(installedModel.modelId);
      await widget.bootstrap.markRuntimeReady();
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
      wakeWordController: widget.bootstrap.wakeWordController,
      modelDownloadController: widget.bootstrap.modelDownloadController,
      skillRegistryController: widget.bootstrap.skillRegistryController,
      mcpConnectionsController: widget.bootstrap.mcpConnectionsController,
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
    required this.triggerSystem,
    required this.wakeWordController,
    required this.skillRegistryController,
    required this.mcpConnectionsController,
    required bool modelReady,
  }) : _modelReady = modelReady;

  final SettingsController settingsController;
  final ChatSessionPort chatSession;
  final ModelDownloadController modelDownloadController;
  final LiteRtBridge liteRtBridge;
  final AudioService audioService;
  final TriggerEventBridge triggerEventBridge;
  final TriggerSystem triggerSystem;
  final WakeWordController wakeWordController;
  final SkillRegistryController skillRegistryController;
  final McpConnectionsController mcpConnectionsController;
  bool _modelReady;
  bool _bootTriggersFired = false;

  bool get modelReady => _modelReady;

  static Future<OpenReefBootstrap> initialize() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final settingsController = SettingsController(
      store: SettingsStore(
        File(
          '${documentsDir.path}${Platform.pathSeparator}settings${Platform.pathSeparator}app_settings.json',
        ),
      ),
    );
    await settingsController.initialize();
    final databaseFactory = _resolveDatabaseFactory();
    final memoryStorage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: await _databasePath(),
        databaseFactory: databaseFactory,
      ),
    );
    await memoryStorage.initialize();

    final memoryIndex = MemoryIndex(memoryStorage);
    final semanticEmbedder = OnDeviceSemanticTextEmbedder();
    final semanticMemoryRetriever = SemanticMemoryRetriever(
      storage: memoryStorage,
      embedder: semanticEmbedder,
    );
    final memoryFormer = MemoryFormer(
      storage: memoryStorage,
      memoryIndex: memoryIndex,
      embedder: semanticEmbedder,
    );
    final executionBridge = _DelegatingAgentTaskExecutor();
    final triggerRepository = TriggerRepository(
      file: File(
        '${documentsDir.path}${Platform.pathSeparator}triggers${Platform.pathSeparator}triggers.json',
      ),
    );
    late TriggerSystem triggerSystem;
    final intervalBackend = InProcessIntervalSchedulerBackend(
      onTriggerFired: (triggerId) async {
        await triggerSystem.fireInterval(triggerId);
      },
    );
    triggerSystem = TriggerSystem(
      scheduleBackend: AndroidScheduleSchedulerBackend(),
      intervalBackend: intervalBackend,
      miniKairos: MiniKairos(
        contextLoader: () async => const KairosContext(
          isAppForeground: true,
          batteryLevel: 100,
          activeSubAgents: 0,
        ),
      ),
      taskExecutor: executionBridge,
    );

    final toolRegistry = ToolManifestRegistry(
      createMvpNativeToolHandlers(
        volumeAdapter: PlatformVolumeAdapter(),
        clipboardAdapter: const PlatformClipboardAdapter(),
        batteryAdapter: PlatformBatteryAdapter(),
        contactAdapter: PlatformContactAdapter(),
        draftMessageAdapter: PlatformDraftMessageAdapter(),
        flashlightAdapter: PlatformFlashlightAdapter(),
        dndAdapter: PlatformDndAdapter(),
        locationAdapter: PlatformLocationAdapter(),
        mapsAdapter: PlatformMapsAdapter(),
        ttsAdapter: PlatformTtsAdapter(),
        notificationAdapter: PlatformNotificationAdapter(),
        appLauncherAdapter: PlatformAppLauncherAdapter(),
        shareAdapter: PlatformShareAdapter(),
        memoryRetriever: semanticMemoryRetriever,
        memoryFormer: memoryFormer,
        memoryIndex: memoryIndex,
        settingsController: settingsController,
        triggerSystem: triggerSystem,
        triggerRepository: triggerRepository,
      ),
    );
    final toolBridge = ToolManifestBridge(toolRegistry);
    final nativeTools = <ToolDefinition>[
      toolBridge.toToolDefinition(
        toolId: 'volume_set',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'clipboard_read',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'clipboard_write',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'battery_info',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'contact_read',
        embedding: const <double>[0, 1, 0, 0, 0, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'contact_create',
        embedding: const <double>[0, 1, 0, 0, 0, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'sms_draft',
        embedding: const <double>[0, 1, 0, 0, 0, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'email_draft',
        embedding: const <double>[0, 1, 0, 0, 0, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'flashlight_toggle',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'dnd_set',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'location_get',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'maps_navigate',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'regex_eval',
        embedding: const <double>[0, 0, 0, 1, 0, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'math_eval',
        embedding: const <double>[0, 0, 0, 1, 0, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'tts_speak',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'notify',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'app_open',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'share',
        embedding: const <double>[0, 1, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'file_read',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 1],
      ),
      toolBridge.toToolDefinition(
        toolId: 'file_write',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 1],
      ),
      toolBridge.toToolDefinition(
        toolId: 'settings_read',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'settings_write',
        embedding: const <double>[0, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'memory_save',
        embedding: const <double>[0, 0, 0, 0, 0, 1, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'memory_search',
        embedding: const <double>[0, 0, 0, 0, 0, 1, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'trigger_create',
        embedding: const <double>[1, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'trigger_list',
        embedding: const <double>[1, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'trigger_remove',
        embedding: const <double>[1, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'alarm_set',
        embedding: const <double>[1, 0, 1, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'cron_add',
        embedding: const <double>[1, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'cron_list',
        embedding: const <double>[1, 0, 0, 0, 1, 0, 0],
      ),
      toolBridge.toToolDefinition(
        toolId: 'cron_remove',
        embedding: const <double>[1, 0, 0, 0, 1, 0, 0],
      ),
    ];
    final toolCatalog = RuntimeToolCatalog(
      sourceTools: <String, List<ToolDefinition>>{
        'native': nativeTools,
      },
    );

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
        await initializeLiteRtBridge(
          liteRtBridge,
          path: installedModel.modelId,
        );
        modelReady = true;
      } catch (error) {
        await modelDownloadController.recoverFromCorruptInstalledModel(
          installedModel,
        );
        modelDownloadController.setInitializationError(error);
        modelReady = false;
      }
    }

    final lexicalIntentEmbedder = const LexicalIntentEmbedder();
    final skillsDir = Directory(
      '${documentsDir.path}${Platform.pathSeparator}skills',
    );
    final skillRuntimeCatalog = SkillRuntimeCatalog(
      registry: SkillRegistry(rootPaths: <String>[skillsDir.path]),
      toolCatalog: toolCatalog,
      stateFile: File(
        '${skillsDir.path}${Platform.pathSeparator}runtime_state.json',
      ),
    );
    await skillRuntimeCatalog.reload();

    final contextAssembler = ContextAssembler(
      memoryIndex: memoryIndex,
      embedder: lexicalIntentEmbedder,
      toolCatalog: toolCatalog,
      skillCatalog: skillRuntimeCatalog,
      memoryContextProvider: SemanticMemoryContextProvider(
        semanticMemoryRetriever,
      ),
    );
    final mailbox = AgentMailbox();
    final approvalController = MainAgentApprovalController(mailbox: mailbox);
    final chatSink = _DelegatingChatExecutionSink();
    final executionLogStore = InMemoryExecutionLogStore();
    final agentLoop = AgentLoop(
      contextAssembler: contextAssembler,
      compactor: ReefCompactor(
        summarizer: LiteRtCompactionSummarizer(bridge: liteRtBridge),
      ),
      modelAdapter: LiteRtAgentModelAdapter(bridge: liteRtBridge),
      toolRouter: ToolRouter(
        catalog: toolCatalog,
        mailbox: mailbox,
        confirmToolCall: approvalController.confirmToolCall,
      ),
      memoryFormer: memoryFormer,
      memoryFormationService: ModelBackedMemoryFormationService(
        modelAdapter: LiteRtAgentModelAdapter(bridge: liteRtBridge),
      ),
      notifier: const DebugPrintAgentNotifier(),
    );
    final taskExecutor = AgentLoopTaskExecutor(
      agentLoop: agentLoop,
      executionLogStore: executionLogStore,
      chatSink: chatSink,
      backgroundSink: const _DebugBackgroundExecutionSink(),
    );
    executionBridge.delegate = taskExecutor;
    final mcpRuntimeCoordinator = McpRuntimeCoordinator(
      toolCatalog: toolCatalog,
      embedText: lexicalIntentEmbedder.embed,
      taskExecutor: executionBridge,
    );
    final chatSession = AgentLoopChatSession(
      taskExecutor: taskExecutor,
      approvalController: approvalController,
    );
    chatSink.delegate = chatSession;

    final triggerEventBridge = TriggerEventBridge();
    for (final trigger in await triggerRepository.loadAll()) {
      final registration = await triggerSystem.register(trigger);
      if (!registration.isRegistered) {
        debugPrint(
          'OpenReefBootstrap.initialize: skipped persisted trigger ${trigger.id}: ${registration.error}',
        );
      }
    }
    final skillRegistryController = SkillRegistryController(
      catalog: skillRuntimeCatalog,
    );
    final mcpConnectionsController = McpConnectionsController(
      store: McpConnectionStore(
        memoryStorage,
        secretStore: PlatformMcpSecretStore(),
      ),
      runtimeCoordinator: mcpRuntimeCoordinator,
    );
    triggerEventBridge.events.listen((event) {
      unawaited(triggerSystem.handlePlatformEvent(event));
    });
    final bootstrap = OpenReefBootstrap._(
      settingsController: settingsController,
      chatSession: chatSession,
      modelDownloadController: modelDownloadController,
      liteRtBridge: liteRtBridge,
      audioService: AudioService(settingsController: settingsController),
      triggerEventBridge: triggerEventBridge,
      triggerSystem: triggerSystem,
      wakeWordController: WakeWordController(
        settingsController: settingsController,
      ),
      skillRegistryController: skillRegistryController,
      mcpConnectionsController: mcpConnectionsController,
      modelReady: modelReady,
    );
    if (modelReady) {
      await bootstrap.markRuntimeReady();
    }
    return bootstrap;
  }

  Future<void> initializeModelAtPath(String path) {
    return initializeLiteRtBridge(liteRtBridge, path: path);
  }

  Future<void> markRuntimeReady() async {
    _modelReady = true;
    triggerSystem.setRuntimeReady(true);
    if (_bootTriggersFired) {
      return;
    }
    _bootTriggersFired = true;
    await triggerSystem.fireBootTriggers();
  }

  static Future<void> initializeLiteRtBridge(
    LiteRtBridge bridge, {
    required String path,
  }) async {
    var useNpu = false;

    try {
      final stats = await bridge.getDeviceStats();
      useNpu = stats?.npuReady ?? false;
    } on PlatformException {
      useNpu = false;
    }

    try {
      debugPrint(
        'OpenReefBootstrap.initializeLiteRtBridge: initModel modelId=$path useNpu=$useNpu',
      );
      await bridge.initModel(path: path, useNpu: useNpu);
    } on PlatformException catch (error) {
      if (error.code != 'ERR_NPU_FALLBACK' || !useNpu) {
        rethrow;
      }
      debugPrint(
        'OpenReefBootstrap.initializeLiteRtBridge: NPU fallback, retrying on CPU/GPU',
      );
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

class _DelegatingAgentTaskExecutor implements AgentTaskExecutor {
  AgentTaskExecutor? delegate;

  @override
  Future<AgentLoopResult> execute(ExecutionRequest request) async {
    final activeDelegate = delegate;
    if (activeDelegate == null) {
      return const AgentLoopResult(
        sessionResult: SessionResult.failed,
        text: '',
        reason: 'executor_not_ready',
      );
    }
    return activeDelegate.execute(request);
  }

  @override
  Future<AgentTaskExecutionResult> executeTask(AgentTaskRequest request) async {
    final activeDelegate = delegate;
    if (activeDelegate == null) {
      return const AgentTaskExecutionResult(
        status: AgentTaskExecutionStatus.failed,
        text: '',
        reason: 'executor_not_ready',
        toolsUsed: <String>[],
      );
    }
    return activeDelegate.executeTask(request);
  }
}

class _DelegatingChatExecutionSink implements ChatExecutionSink {
  ChatExecutionSink? delegate;

  @override
  Future<void> appendExecutionResult(
    ExecutionRequest request,
    AgentLoopResult result,
  ) async {
    await delegate?.appendExecutionResult(request, result);
  }
}

class _DebugBackgroundExecutionSink implements BackgroundExecutionSink {
  const _DebugBackgroundExecutionSink();

  @override
  Future<void> recordExecution(
    ExecutionRequest request,
    AgentLoopResult result,
  ) async {
    debugPrint(
      'Background execution ${request.id} (${request.source.name}) '
      'finished with ${result.sessionResult.name}.',
    );
  }
}
