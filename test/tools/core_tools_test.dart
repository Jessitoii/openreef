import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/semantic_memory_retriever.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/settings/settings_store.dart';
import 'package:openreef/main.dart' as app_main;
import 'package:openreef/tools/ddgs_web_search_service.dart';
import 'package:openreef/tools/mvp_native_tools.dart';
import 'package:openreef/tools/native_tool_adapters.dart';
import 'package:openreef/tools/tool_errors.dart';
import 'package:openreef/tools/tool_manifest_bridge.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/tools/tool_manifest_registry.dart';
import 'package:openreef/triggers/trigger_native_sync.dart';
import 'package:openreef/triggers/mini_kairos.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_repository.dart';
import 'package:openreef/triggers/trigger_system.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDir;
  late MemoryStorage storage;

  late SettingsController settingsController;
  late TriggerRepository triggerRepository;
  late _RecordingScheduleBackend scheduleBackend;
  late _RecordingIntervalBackend intervalBackend;
  late _RecordingAppLauncherAdapter appLauncherAdapter;
  late ToolManifestRegistry registry;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('openreef_core_tools');
    storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    final embedder = _MappedSemanticEmbedder(<String, List<double>>{
      'prefers concise updates': const <double>[1, 0, 0],
      'concise updates': const <double>[1, 0, 0],
    });
    settingsController = SettingsController(
      store: SettingsStore(
        File('${tempDir.path}${Platform.pathSeparator}settings.json'),
      ),
    );
    await settingsController.initialize();
    triggerRepository = TriggerRepository(
      file: File('${tempDir.path}${Platform.pathSeparator}triggers.json'),
    );
    scheduleBackend = _RecordingScheduleBackend();
    intervalBackend = _RecordingIntervalBackend();
    appLauncherAdapter = _RecordingAppLauncherAdapter();
    final triggerSystem = TriggerSystem(
      scheduleBackend: scheduleBackend,
      intervalBackend: intervalBackend,
      miniKairos: MiniKairos(
        contextLoader: () async => const KairosContext(
          isAppForeground: true,
          batteryLevel: 100,
          activeSubAgents: 0,
        ),
      ),
      taskExecutor: _NoopTaskExecutor(),
    )..setRuntimeReady(true);
    registry = ToolManifestRegistry(
      createMvpNativeToolHandlers(
        volumeAdapter: _NoopVolumeAdapter(),
        clipboardAdapter: _MemoryClipboardAdapter(),
        batteryAdapter: _NoopBatteryAdapter(),
        contactAdapter: _NoopContactAdapter(),
        draftMessageAdapter: _NoopDraftMessageAdapter(),
        flashlightAdapter: _NoopFlashlightAdapter(),
        dndAdapter: _NoopDndAdapter(),
        locationAdapter: _NoopLocationAdapter(),
        mapsAdapter: _NoopMapsAdapter(),
        ttsAdapter: _NoopTtsAdapter(),
        notificationAdapter: _NoopNotificationAdapter(),
        appLauncherAdapter: appLauncherAdapter,
        shareAdapter: _NoopShareAdapter(),
        memoryRetriever: SemanticMemoryRetriever(
          storage: storage,
          embedder: embedder,
          defaultThreshold: 0.0,
        ),
        memoryStorage: storage,
        settingsController: settingsController,
        triggerNativeSync: _NoopTriggerNativeSync(),
        triggerSystem: triggerSystem,
        triggerRepository: triggerRepository,
        webSearchService: DdgsWebSearchService(),
      ),
    );
  });

  tearDown(() async {
    await storage.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'memory_save followed by memory_search returns the persisted fact',
    () async {
      await registry.execute(
        const ToolInvocation(
          toolId: 'memory_save',
          arguments: <String, Object?>{
            'content': 'Prefers concise updates',
            'category': 'user_prefs',
            'importance': 5,
            'key': 'prefs_concise',
          },
        ),
      );
      final records = await storage.readRecords(
        store: MemoryStoreKind.longTerm,
      );
      expect(records.isNotEmpty, isTrue);
      expect(records.first.content, 'Prefers concise updates');
    },
  );

  test('implemented native tools are bridged into the runtime catalog', () {
    final bridge = ToolManifestBridge(registry);
    final nativeTools = app_main.buildNativeTools(registry, bridge);
    final catalog = RuntimeToolCatalog(
      sourceTools: <String, List<ToolDefinition>>{'native': nativeTools},
    );
    final toolsById = <String, ToolDefinition>{
      for (final tool in catalog.listTools()) tool.id: tool,
    };

    expect(
      toolsById.keys,
      containsAll(<String>[
        'phone_call',
        'phone_dial',
        'sms_send',
        'communication_whatsapp_draft',
        'communication_telegram_draft',
        'app_list',
        'brightness_set',
        'device_info',
        'wifi_toggle',
        'bluetooth_toggle',
        'screen_lock',
        'web_search',
        'web_fetch',
        'geofence_add',
        'maps_search',
        'location_distance',
        'location_reverse_geocode',
        'camera_photo',
        'camera_scan',
        'media_display',
        'media_play',
        'image_analyze',
        'calendar_read',
        'calendar_write',
        'session_status',
        'agent_spawn',
        'file_list',
        'llm_task',
      ]),
    );
    expect(toolsById['location_reverse_geocode']?.enabled, isFalse);
    expect(toolsById['llm_task']?.enabled, isFalse);
    for (final id in <String>[
      'sms_send',
      'web_search',
      'web_fetch',
      'geofence_add',
      'maps_search',
      'location_distance',
      'camera_photo',
      'camera_scan',
      'media_display',
      'media_play',
      'image_analyze',
      'agent_spawn',
      'file_list',
      'device_info',
    ]) {
      expect(toolsById[id]?.enabled, isTrue, reason: id);
    }
    expect(toolsById.containsKey('code_run'), isFalse);
    expect(toolsById.containsKey('session_history'), isFalse);
    expect(toolsById.containsKey('x_search'), isFalse);
  });

  test(
    'production native manifests are compatible with strict router validation',
    () {
      final bridge = ToolManifestBridge(registry);
      final nativeTools = app_main.buildNativeTools(registry, bridge);
      final router = ToolRouter(
        catalog: RuntimeToolCatalog(
          sourceTools: <String, List<ToolDefinition>>{'native': nativeTools},
        ),
        mailbox: AgentMailbox(),
        confirmToolCall: (_) async => true,
      );

      for (final tool in nativeTools) {
        final validArgs = <String, Object?>{
          for (final spec in tool.argumentSchema) spec.name: _sampleValue(spec),
        };
        expect(
          router.validateToolCall(
            ToolCall(
              id: 'audit-valid-${tool.id}',
              toolId: tool.id,
              arguments: validArgs,
            ),
          ),
          isNull,
          reason: tool.id,
        );

        final extraKeyResult = router.validateToolCall(
          ToolCall(
            id: 'audit-extra-${tool.id}',
            toolId: tool.id,
            arguments: <String, Object?>{
              ...validArgs,
              'legacy_extra_key': true,
            },
          ),
        );
        if (tool.enabled) {
          expect(extraKeyResult?.status, ToolResultStatus.validationError);
          expect(
            extraKeyResult?.metadata['reason'],
            'malformed_tool_call',
            reason: tool.id,
          );
        } else {
          expect(extraKeyResult, isNull, reason: tool.id);
        }
      }
    },
  );

  test('file_write and file_read operate on real absolute paths', () async {
    final path = '${tempDir.path}${Platform.pathSeparator}notes.txt';

    await registry.execute(
      ToolInvocation(
        toolId: 'file_write',
        arguments: <String, Object?>{'path': path, 'content': 'reef tools'},
      ),
    );
    final result = await registry.execute(
      ToolInvocation(
        toolId: 'file_read',
        arguments: <String, Object?>{'path': path},
      ),
    );

    expect(await File(path).readAsString(), 'reef tools');
    expect(result.content, 'reef tools');
  });

  test('file_read rejects relative paths', () async {
    final result = await registry.execute(
      const ToolInvocation(
        toolId: 'file_read',
        arguments: <String, Object?>{'path': '../relative.txt'},
      ),
    );
    expect(result.status, NativeToolExecutionStatus.failure);
  });

  test(
    'stubbed DDGS service reports unavailable instead of fake success',
    () async {
      await expectLater(
        DdgsWebSearchService().search('OpenAI news'),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        DdgsWebSearchService().fetch('https://example.com'),
        throwsA(isA<UnsupportedError>()),
      );

      final searchResult = await registry.execute(
        const ToolInvocation(
          toolId: 'web_search',
          arguments: <String, Object?>{'query': 'OpenAI news'},
        ),
      );
      final fetchResult = await registry.execute(
        const ToolInvocation(
          toolId: 'web_fetch',
          arguments: <String, Object?>{'url': 'https://example.com'},
        ),
      );

      expect(searchResult.status, NativeToolExecutionStatus.failure);
      expect(searchResult.error?.code, ToolErrorCode.featureUnavailable);
      expect(searchResult.error?.message, 'web_search_backend_unavailable');
      expect(fetchResult.status, NativeToolExecutionStatus.failure);
      expect(fetchResult.error?.code, ToolErrorCode.featureUnavailable);
      expect(fetchResult.error?.message, 'web_fetch_backend_unavailable');
    },
  );

  test(
    'bluetooth_toggle does not report success without platform effect',
    () async {
      final result = await registry.execute(
        const ToolInvocation(
          toolId: 'bluetooth_toggle',
          arguments: <String, Object?>{'enabled': true},
        ),
      );

      expect(result.status, NativeToolExecutionStatus.failure);
      expect(result.error?.code, ToolErrorCode.unsupported);
      expect(result.error?.message, 'bluetooth_toggle_platform_restricted');
    },
  );

  test(
    'alarm_set creates a persisted daily reminder and trigger_list exposes it',
    () async {
      await registry.execute(
        const ToolInvocation(
          toolId: 'alarm_set',
          arguments: <String, Object?>{
            'name': 'Drink water',
            'prompt': 'Remind me to drink water.',
            'hour': 8,
            'minute': 0,
          },
        ),
      );

      final persisted = await triggerRepository.loadAll();
      final listed = await registry.execute(
        const ToolInvocation(toolId: 'trigger_list'),
      );

      expect(scheduleBackend.registeredIds, hasLength(1));
      expect(persisted.single.scheduleSpec?.hour, 8);
      expect(listed.content, contains('schedule'));
    },
  );

  test('cron_add then cron_remove controls interval-backed triggers', () async {
    final created = await registry.execute(
      const ToolInvocation(
        toolId: 'cron_add',
        arguments: <String, Object?>{
          'name': 'Check inbox',
          'prompt': 'Check inbox every 30 minutes.',
          'every_minutes': 30,
        },
      ),
    );
    final triggerId =
        ((created.metadata['trigger'] as Map<String, Object?>)['id'] as String);

    final listed = await registry.execute(
      const ToolInvocation(toolId: 'cron_list'),
    );
    await registry.execute(
      ToolInvocation(
        toolId: 'cron_remove',
        arguments: <String, Object?>{'trigger_id': triggerId},
      ),
    );

    expect(intervalBackend.registeredIds, hasLength(1));
    expect(listed.content, contains('every 30m'));
    expect(await triggerRepository.loadAll(), isEmpty);
  });
}

Object? _sampleValue(ToolArgumentSpec spec) {
  if (spec.allowedValues.isNotEmpty) {
    return spec.allowedValues.first;
  }
  switch (spec.type) {
    case ToolArgumentType.string:
      return 'sample';
    case ToolArgumentType.integer:
      return (spec.minimum ?? 1).ceil();
    case ToolArgumentType.doubleValue:
      return (spec.minimum ?? 0.5).toDouble();
    case ToolArgumentType.boolean:
      return true;
  }
}

class _MappedSemanticEmbedder implements SemanticTextEmbedder {
  const _MappedSemanticEmbedder(this._vectors);

  final Map<String, List<double>> _vectors;

  @override
  String get modelId => 'mapped-test';

  @override
  Future<List<double>> embedDocument(String text) async {
    return _vectors[text.toLowerCase()] ?? const <double>[0, 0, 1];
  }

  @override
  Future<List<double>> embedQuery(String text) async {
    return _vectors[text.toLowerCase()] ?? const <double>[0, 0, 1];
  }
}

class _NoopTaskExecutor implements AgentTaskExecutor {
  @override
  Future<bool> cancelActiveRun({
    String? runId,
    String? sessionKey,
    RunCancellationReason reason = RunCancellationReason.userRequested,
  }) async {
    return false;
  }

  @override
  Future<ExecutionResult> execute(ExecutionRequest request) async {
    return ExecutionResult(
      requestId: request.id,
      sessionKey: request.sessionKey,
      source: request.source,
      mode: request.mode,
      terminalStatus: ExecutionLifecycleStatus.completed,
      admissionOutcome: ExecutionAdmissionOutcome.admitted,
      policyReason: 'completed',
      visibility: request.visibility,
      loopResult: const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'ok',
        reason: 'completed',
      ),
    );
  }

  @override
  Future<AgentTaskExecutionResult> executeTask(AgentTaskRequest request) async {
    final result = await execute(request.toExecutionRequest());
    return AgentTaskExecutionResult.fromLoopResult(result.toAgentLoopResult());
  }
}

class _RecordingScheduleBackend implements ScheduleSchedulerBackend {
  final List<String> registeredIds = <String>[];

  @override
  Future<void> cancel(String triggerId) async {}

  @override
  Future<void> registerSchedule(TriggerConfig trigger) async {
    registeredIds.add(trigger.id);
  }
}

class _RecordingIntervalBackend implements IntervalSchedulerBackend {
  final List<String> registeredIds = <String>[];

  @override
  Future<void> cancel(String triggerId) async {}

  @override
  Future<void> registerInterval(TriggerConfig trigger) async {
    registeredIds.add(trigger.id);
  }
}

class _NoopVolumeAdapter implements DeviceVolumeAdapter {
  @override
  Future<double> setVolumeLevel(double normalizedLevel) async =>
      normalizedLevel;
}

class _MemoryClipboardAdapter implements ClipboardAdapter {
  @override
  Future<String?> readClipboardText() async => null;

  @override
  Future<void> writeClipboardText(String text) async {}
}

class _NoopBatteryAdapter implements BatteryAdapter {
  @override
  Future<BatterySnapshot> readBatteryInfo() async =>
      const BatterySnapshot(level: 80, state: BatteryState.charging);
}

class _NoopContactAdapter implements ContactAdapter {
  @override
  Future<ContactRecord> createContact({
    required String displayName,
    String? phone,
    String? email,
  }) async => const ContactRecord(displayName: 'noop');

  @override
  Future<List<ContactRecord>> searchContacts({
    String? query,
    required int limit,
  }) async => const <ContactRecord>[];
}

class _NoopDraftMessageAdapter implements DraftMessageAdapter {
  @override
  Future<void> openEmailDraft({
    String? to,
    String? subject,
    String? body,
  }) async {}

  @override
  Future<void> openSmsDraft({String? to, String? body}) async {}
}

class _NoopFlashlightAdapter implements FlashlightAdapter {
  @override
  Future<bool> setEnabled(bool enabled) async => enabled;
}

class _NoopDndAdapter implements DndAdapter {
  @override
  Future<DndMode> setMode(DndMode mode) async => mode;
}

class _NoopLocationAdapter implements LocationAdapter {
  @override
  Future<LocationSnapshot> getCurrentLocation({
    required bool highAccuracy,
  }) async {
    return LocationSnapshot(
      latitude: 0,
      longitude: 0,
      provider: 'noop',
      timestamp: DateTime.utc(2026, 4, 7),
    );
  }
}

class _NoopMapsAdapter implements MapsAdapter {
  @override
  Future<void> openNavigation({required String query}) async {}
}

class _NoopTtsAdapter implements TtsAdapter {
  @override
  Future<void> speak({required String text, required bool interrupt}) async {}
}

class _NoopNotificationAdapter implements NotificationAdapter {
  @override
  Future<NotificationDispatch> showNotification({
    required String title,
    required String body,
  }) async {
    return NotificationDispatch(
      notificationId: 1,
      dispatchedAt: DateTime.utc(2026, 4, 7, 8),
    );
  }
}

class _RecordingAppLauncherAdapter implements AppLauncherAdapter {
  String? lastPackageName;

  @override
  Future<void> openApp(String packageName) async {
    lastPackageName = packageName;
  }
}

class _NoopShareAdapter implements ShareAdapter {
  @override
  Future<void> shareText({required String text, String? subject}) async {}
}

class _NoopTriggerNativeSync extends TriggerNativeSync {
  _NoopTriggerNativeSync() : super(methodChannel: null);

  @override
  Future<void> syncTriggers(List<TriggerConfig> triggers) async {}

  @override
  Future<void> registerGlobalPollingWork() async {}

  @override
  Future<void> syncGlobalPollMinutes(int minutes) async {}
}
