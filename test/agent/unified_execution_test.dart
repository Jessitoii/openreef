import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_loop.dart';
import 'package:openreef/agent/agent_model_adapter.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/agent_notifier.dart';
import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/execution_log.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/run_state.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/compactor.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/mcp/mcp_client.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_runtime_coordinator.dart';
import 'package:openreef/mcp/mcp_transport.dart';
import 'package:openreef/memory/memory_former.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/triggers/mini_kairos.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_system.dart';
import 'package:openreef/ui/agent_loop_chat_session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'user, trigger, and mcp event paths all use the same executor',
    () async {
      final executor = _RecordingExecutor();
      final chatSession = AgentLoopChatSession(taskExecutor: executor);
      final triggerSystem = TriggerSystem(
        scheduleBackend: _NoopScheduleBackend(),
        intervalBackend: _NoopIntervalBackend(),
        miniKairos: MiniKairos(
          contextLoader: () async => const KairosContext(
            isAppForeground: true,
            batteryLevel: 100,
            activeSubAgents: 0,
          ),
        ),
        taskExecutor: executor,
        systemSessionKey: 'system_main',
      );
      final runtimeCoordinator = McpRuntimeCoordinator(
        toolCatalog: RuntimeToolCatalog(),
        embedText: (text) async => const <double>[1, 0, 0, 0, 0, 0, 0],
        taskExecutor: executor,
      );
      await runtimeCoordinator.replaceSourceTools(
        binding: McpRuntimeSourceBinding(
          sourceId: 'source-1',
          client: McpClient(_NoopTransport()),
          isActive: () => true,
          requiresTrust: false,
          trusted: true,
          requiresManualSecretEntry: false,
          hasRequiredSecretMaterial: () async => true,
        ),
        discoveredTools: const <McpTool>[],
      );

      await chatSession.sendMessage('hello');
      await triggerSystem.register(
        const TriggerConfig(
          id: 'manual_sync',
          name: 'Manual sync',
          prompt: 'Run trigger task.',
          type: TriggerType.manual,
          priority: TriggerPriority.normal,
        ),
      );
      triggerSystem.setRuntimeReady(true);
      await triggerSystem.fireManual('manual_sync');
      runtimeCoordinator.emitSourceEvent(
        McpRuntimeEvent(
          sourceId: 'source-1',
          eventName: 'repo.updated',
          payload: const <String, Object?>{'prompt': 'Handle repo update.'},
          receivedAt: DateTime.utc(2026, 4, 7, 12),
          transportEvent: 'notification',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(executor.requests, hasLength(3));
      expect(executor.requests[0].source, ExecutionSource.user);
      expect(executor.requests[1].source, ExecutionSource.trigger);
      expect(executor.requests[2].source, ExecutionSource.mcpEvent);
    },
  );

  test('executor rejects overlapping runs for the same session key', () async {
    final harness = await _ExecutorHarness.create(
      modelAdapter: _BlockingModelAdapter(
        onGenerate: () => Completer<void>().future,
      ),
    );
    addTearDown(harness.dispose);

    final firstFuture = harness.executor.execute(
      ExecutionRequest.fromUserMessage(
        sessionKey: 'system_main',
        prompt: 'first',
        id: 'first',
        createdAt: DateTime.utc(2026, 4, 7, 12),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final secondResult = await harness.executor.execute(
      ExecutionRequest.fromUserMessage(
        sessionKey: 'system_main',
        prompt: 'second',
        id: 'second',
        createdAt: DateTime.utc(2026, 4, 7, 12, 0, 1),
      ),
    );

    expect(secondResult.sessionResult, SessionResult.failed);
    expect(secondResult.reason, 'session_busy');
    expect(harness.logStore.records.value, hasLength(2));
    expect(harness.logStore.records.value.last.failureReason, 'session_busy');

    unawaited(firstFuture);
  });

  test(
    'ephemeral chat execution is classified and does not persist run state',
    () async {
      final harness = await _ExecutorHarness.create(
        modelAdapter: _BlockingModelAdapter(onGenerate: () async {}),
      );
      addTearDown(harness.dispose);

      final request = ExecutionRequest.fromUserMessage(
        sessionKey: 'chat-session',
        prompt: 'hello',
        id: 'chat-1',
        createdAt: DateTime.utc(2026, 4, 7, 12),
      );
      final result = await harness.executor.execute(request);

      expect(request.mode, ExecutionLifecycleMode.ephemeralRequest);
      expect(result.sessionResult, SessionResult.completed);
      expect(harness.executor.runStateStore.runs.value, isEmpty);
    },
  );

  test(
    'triggered persistent execution creates inspectable run state',
    () async {
      final harness = await _ExecutorHarness.create(
        modelAdapter: _BlockingModelAdapter(onGenerate: () async {}),
      );
      addTearDown(harness.dispose);

      final request = ExecutionRequest.fromTrigger(
        sessionKey: 'system_main',
        prompt: 'sync',
        source: ExecutionSource.trigger,
        id: 'trigger-request-1',
        createdAt: DateTime.utc(2026, 4, 7, 12),
        metadata: const <String, dynamic>{
          'triggerId': 'standing-sync',
          'appliedStandingOrderIds': <String>['rule-1'],
        },
      );

      await harness.executor.execute(request);
      final run = await harness.executor.runStateStore.byId('standing-sync');

      expect(request.mode, ExecutionLifecycleMode.triggeredRequest);
      expect(run, isNotNull);
      expect(run!.status, ExecutionLifecycleStatus.completed);
      expect(
        run.transitions.map((entry) => entry.to),
        contains(ExecutionLifecycleStatus.running),
      );
      expect(
        run.transitions.map((entry) => entry.to),
        contains(ExecutionLifecycleStatus.completed),
      );
    },
  );

  test('resume request loads suspended stored run state', () async {
    final harness = await _ExecutorHarness.create(
      modelAdapter: _BlockingModelAdapter(onGenerate: () async {}),
    );
    addTearDown(harness.dispose);
    final createdAt = DateTime.utc(2026, 4, 7, 12);
    await harness.executor.runStateStore.save(
      RunState(
        runId: 'run-1',
        requestIdOrigin: 'origin-1',
        status: ExecutionLifecycleStatus.suspended,
        mode: ExecutionLifecycleMode.triggeredRequest,
        currentStepIndex: 1,
        variables: const <String, Object?>{'previous': 'ok'},
        createdAt: createdAt,
        updatedAt: createdAt,
        sessionId: 'system_main',
        waitingReason: 'waiting_input',
      ),
    );

    final result = await harness.executor.execute(
      ExecutionRequest.resume(
        sessionKey: 'system_main',
        prompt: 'continue',
        runId: 'run-1',
        id: 'resume-1',
        createdAt: DateTime.utc(2026, 4, 7, 12, 1),
      ),
    );
    final run = await harness.executor.runStateStore.byId('run-1');

    expect(result.sessionResult, SessionResult.completed);
    expect(
      run!.transitions.map((entry) => entry.reason),
      contains('resume_request'),
    );
    expect(run.status, ExecutionLifecycleStatus.completed);
  });

  test('duplicate standing-order style runs reject while active', () async {
    final gate = Completer<void>();
    final harness = await _ExecutorHarness.create(
      modelAdapter: _BlockingModelAdapter(onGenerate: () => gate.future),
    );
    addTearDown(harness.dispose);
    final first = ExecutionRequest.fromTrigger(
      sessionKey: 'system_main',
      prompt: 'first',
      source: ExecutionSource.trigger,
      id: 'trigger-1',
      metadata: const <String, dynamic>{
        'triggerId': 'standing-sync',
        'appliedStandingOrderIds': <String>['rule-1'],
      },
    );
    final firstFuture = harness.executor.execute(first);
    await Future<void>.delayed(Duration.zero);

    final duplicate = await harness.executor.execute(
      ExecutionRequest.fromTrigger(
        sessionKey: 'system_main',
        prompt: 'second',
        source: ExecutionSource.trigger,
        id: 'trigger-2',
        metadata: const <String, dynamic>{
          'triggerId': 'standing-sync',
          'appliedStandingOrderIds': <String>['rule-1'],
        },
      ),
    );

    expect(duplicate.sessionResult, SessionResult.failed);
    expect(duplicate.reason, 'duplicate_active_run');
    gate.complete();
    expect((await firstFuture).sessionResult, SessionResult.completed);
  });

  test('chat preempts queued background work in the same session', () async {
    final firstGate = Completer<void>();
    final harness = await _ExecutorHarness.create(
      modelAdapter: _BlockingModelAdapter(onGenerate: () => firstGate.future),
    );
    addTearDown(harness.dispose);
    final running = harness.executor.execute(
      ExecutionRequest.fromTrigger(
        sessionKey: 'system_main',
        prompt: 'running',
        source: ExecutionSource.trigger,
        id: 'running-trigger',
        metadata: const <String, dynamic>{'triggerId': 'running-trigger'},
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final queued = harness.executor.execute(
      ExecutionRequest.fromTrigger(
        sessionKey: 'system_main',
        prompt: 'queued',
        source: ExecutionSource.trigger,
        id: 'queued-trigger',
        metadata: const <String, dynamic>{'triggerId': 'queued-trigger'},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final chat = await harness.executor.execute(
      ExecutionRequest.fromUserMessage(
        sessionKey: 'system_main',
        prompt: 'foreground',
        id: 'chat-preempt',
      ),
    );

    expect(chat.reason, 'session_busy');
    firstGate.complete();
    expect((await queued).reason, 'preempted_by_chat');
    expect((await running).sessionResult, SessionResult.completed);
  });

  test('executor allows overlapping runs for different session keys', () async {
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    var generateCount = 0;
    final harness = await _ExecutorHarness.create(
      modelAdapter: _CountingBlockingModelAdapter(
        onGenerateForCall: (callIndex) {
          generateCount = callIndex;
          return callIndex == 1 ? firstGate.future : secondGate.future;
        },
      ),
    );
    addTearDown(harness.dispose);

    final firstFuture = harness.executor.execute(
      ExecutionRequest.fromUserMessage(
        sessionKey: 'session-a',
        prompt: 'first',
      ),
    );
    final secondFuture = harness.executor.execute(
      ExecutionRequest.fromUserMessage(
        sessionKey: 'session-b',
        prompt: 'second',
      ),
    );

    firstGate.complete();
    secondGate.complete();
    expect((await firstFuture).sessionResult, SessionResult.completed);
    expect((await secondFuture).sessionResult, SessionResult.completed);
    expect(generateCount, 2);
  });
}

class _RecordingExecutor implements AgentTaskExecutor {
  final List<ExecutionRequest> requests = <ExecutionRequest>[];

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
    requests.add(request);
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
        text: 'done',
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

class _ExecutorHarness {
  _ExecutorHarness({
    required this.storage,
    required this.executor,
    required this.logStore,
  });

  final MemoryStorage storage;
  final AgentLoopTaskExecutor executor;
  final InMemoryExecutionLogStore logStore;

  static Future<_ExecutorHarness> create({
    required AgentModelAdapter modelAdapter,
  }) async {
    final storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    final memoryIndex = MemoryIndex(storage);
    final memoryFormer = MemoryFormer(
      storage: storage,
      memoryIndex: memoryIndex,
      embedder: const _FixedSemanticEmbedder(),
    );
    final toolCatalog = InMemoryToolCatalog(<ToolDefinition>[
      ToolDefinition(
        id: 'session_status',
        embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
        execute: _okExecute,
      ),
    ]);
    final loop = AgentLoop(
      contextAssembler: ContextAssembler(
        memoryIndex: memoryIndex,
        embedder: const _FixedIntentEmbedder(),
        toolCatalog: toolCatalog,
        skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
      ),
      compactor: ReefCompactor(summarizer: const _NoopSummarizer()),
      modelAdapter: modelAdapter,
      toolRouter: ToolRouter(
        catalog: toolCatalog,
        mailbox: AgentMailbox(),
        confirmToolCall: (call) async => true,
      ),
      memoryFormer: memoryFormer,
      notifier: const _NoopNotifier(),
    );
    final logStore = InMemoryExecutionLogStore();
    return _ExecutorHarness(
      storage: storage,
      executor: AgentLoopTaskExecutor(
        agentLoop: loop,
        executionLogStore: logStore,
      ),
      logStore: logStore,
    );
  }

  Future<void> dispose() async {
    await storage.close();
  }
}

class _BlockingModelAdapter implements AgentModelAdapter {
  _BlockingModelAdapter({required this.onGenerate});

  final Future<void> Function() onGenerate;

  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    await onGenerate();
    return const AgentResponse(text: 'done');
  }
}

class _CountingBlockingModelAdapter implements AgentModelAdapter {
  _CountingBlockingModelAdapter({required this.onGenerateForCall});

  final Future<void> Function(int callIndex) onGenerateForCall;
  int _callCount = 0;

  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    _callCount += 1;
    await onGenerateForCall(_callCount);
    return const AgentResponse(text: 'done');
  }
}

class _FixedIntentEmbedder implements IntentEmbedder {
  const _FixedIntentEmbedder();

  @override
  Future<List<double>> embed(String text) async => const <double>[
    1,
    0,
    0,
    0,
    0,
    0,
    0,
  ];
}

class _FixedSemanticEmbedder implements SemanticTextEmbedder {
  const _FixedSemanticEmbedder();

  @override
  String get modelId => 'test-semantic';

  @override
  Future<List<double>> embedDocument(String text) async => const <double>[
    1,
    0,
    0,
  ];

  @override
  Future<List<double>> embedQuery(String text) async => const <double>[1, 0, 0];
}

class _NoopSummarizer implements CompactionSummarizer {
  const _NoopSummarizer();

  @override
  Future<String> summarize(
    List<AgentMessage> messages, {
    required int maxTokens,
  }) async {
    return 'summary';
  }
}

class _NoopNotifier implements AgentNotifier {
  const _NoopNotifier();

  @override
  Future<void> freezeSession({
    required String sessionKey,
    required String reason,
    required String title,
    required String body,
  }) async {}
}

class _NoopScheduleBackend implements ScheduleSchedulerBackend {
  @override
  Future<void> cancel(String triggerId) async {}

  @override
  Future<void> registerSchedule(TriggerConfig trigger) async {}
}

class _NoopIntervalBackend implements IntervalSchedulerBackend {
  @override
  Future<void> cancel(String triggerId) async {}

  @override
  Future<void> registerInterval(TriggerConfig trigger) async {}
}

class _NoopTransport implements McpTransport {
  @override
  Stream<McpTransportMessage> get messages =>
      const Stream<McpTransportMessage>.empty();

  @override
  Future<void> close() async {}

  @override
  Future<void> connect() async {}

  @override
  Future<void> sendNotification(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
  }) async {}

  @override
  Future<McpJsonRpcResponse> sendRequest(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    throw UnimplementedError();
  }
}

Future<ToolResult> _okExecute(ToolCall call) async {
  return const ToolResult.success('ok');
}
