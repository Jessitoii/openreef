import 'dart:async';
import 'dart:io';

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
import 'package:openreef/memory/memory_former.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('persistent request intake is reachable', () {
    final request = ExecutionRequest.persistent(
      sessionKey: 'system_main',
      prompt: 'persistent work',
      id: 'persistent-1',
    );

    expect(request.source, ExecutionSource.system);
    expect(request.mode, ExecutionLifecycleMode.persistentRequest);
  });

  test('restart resume restores continuation and affects execution', () async {
    final path = await _tempDatabasePath();
    final createdAt = DateTime.utc(2026, 4, 11, 10);
    final firstStore = SqliteRunStateStore(
      path: path,
      databaseFactory: databaseFactoryFfi,
    );
    await firstStore.initialize();
    await firstStore.save(
      RunState(
        runId: 'run-resume',
        requestIdOrigin: 'request-origin',
        status: ExecutionLifecycleStatus.suspended,
        mode: ExecutionLifecycleMode.persistentRequest,
        currentStepIndex: 7,
        variables: const <String, Object?>{'branch': 'restored'},
        createdAt: createdAt,
        updatedAt: createdAt,
        sessionId: 'system_main',
        waitingReason: 'waiting_event',
        waitingMetadata: const <String, Object?>{'event': 'network_back'},
      ),
    );
    await firstStore.saveTransition(
      RunStateTransition(
        runId: 'run-resume',
        from: ExecutionLifecycleStatus.running,
        to: ExecutionLifecycleStatus.suspended,
        reason: 'explicit_suspend',
        occurredAt: createdAt,
        requestId: 'request-origin',
      ),
    );
    await firstStore.saveStandingOrderEvaluations(
      <StandingOrderEvaluationRecord>[
        StandingOrderEvaluationRecord(
          evaluationId: 'eval-resume',
          runId: 'run-resume',
          ruleId: 'rule-resume',
          triggerType: 'manual',
          condition: const <String, Object?>{'scope': 'manual'},
          action: const <String, Object?>{'type': 'apply_structured_directive'},
          priority: 1,
          status: StandingOrderEvaluationStatus.matchedApplied,
          reason: 'matched',
          evaluatedAt: createdAt,
        ),
      ],
    );
    await firstStore.close();

    final secondStore = SqliteRunStateStore(
      path: path,
      databaseFactory: databaseFactoryFfi,
    );
    final harness = await _Harness.create(
      store: secondStore,
      modelAdapter: _ContinuationAwareModelAdapter(),
    );
    addTearDown(harness.dispose);

    final result = await harness.executor.execute(
      ExecutionRequest.resume(
        sessionKey: 'system_main',
        prompt: 'continue',
        runId: 'run-resume',
        id: 'resume-request',
      ),
    );

    expect(result.terminalStatus, ExecutionLifecycleStatus.completed);
    expect(result.text, contains('restored'));
    expect(result.text, contains('step=7'));
    final run = await secondStore.byId('run-resume');
    expect(
      run!.transitions.map((entry) => entry.reason),
      contains('resume_request'),
    );
    expect(
      run.transitions.map((entry) => entry.to),
      isNot(contains(ExecutionLifecycleStatus.rejected)),
    );
    expect(
      (await secondStore.standingOrderEvaluationsForRun(
        'run-resume',
      )).single.ruleId,
      'rule-resume',
    );
  });

  test('max tool call policy is enforced by the shared loop', () async {
    final harness = await _Harness.create(
      modelAdapter: _QueueModelAdapter(<AgentResponse>[
        const AgentResponse(
          text: '',
          toolCall: ToolCall(id: 'call-1', toolId: 'ok'),
        ),
        const AgentResponse(
          text: '',
          toolCall: ToolCall(id: 'call-2', toolId: 'ok'),
        ),
      ]),
    );
    addTearDown(harness.dispose);

    final request = ExecutionRequest.persistent(
      sessionKey: 'system_main',
      prompt: 'use tools',
      id: 'policy-tools',
    );
    final limited = ExecutionRequest(
      id: request.id,
      source: request.source,
      sessionKey: request.sessionKey,
      prompt: request.prompt,
      visibility: request.visibility,
      createdAt: request.createdAt,
      classification: request.classification,
      metadata: request.metadata,
      runContext: request.runContext,
      policy: const ExecutionPolicy(
        allowToolUse: true,
        allowPersistence: true,
        allowSuspend: true,
        maxSteps: 12,
        maxToolCalls: 1,
        timeoutMs: 30000,
        duplicatePolicy: DuplicateExecutionPolicy.allow,
        queuePolicy: QueueExecutionPolicy.fifo,
        failurePolicy: FailureExecutionPolicy.failRun,
        completionPolicy: CompletionExecutionPolicy.both,
      ),
    );

    final result = await harness.executor.execute(limited);

    expect(result.terminalStatus, ExecutionLifecycleStatus.failed);
    expect(result.reason, 'tool_call_cap');
  });

  test('max step policy is enforced by the shared loop', () async {
    final harness = await _Harness.create(
      modelAdapter: _QueueModelAdapter(<AgentResponse>[
        const AgentResponse(
          text: '',
          toolCall: ToolCall(id: 'call-1', toolId: 'ok'),
        ),
        const AgentResponse(
          text: '',
          toolCall: ToolCall(id: 'call-2', toolId: 'ok'),
        ),
      ]),
    );
    addTearDown(harness.dispose);

    final result = await harness.executor.execute(
      _policyRequest(id: 'policy-steps', maxSteps: 1, maxToolCalls: 8),
    );

    expect(result.terminalStatus, ExecutionLifecycleStatus.failed);
    expect(result.reason, 'iteration_cap');
  });

  test('timeout policy is enforced by the shared loop', () async {
    final harness = await _Harness.create(
      modelAdapter: _DelayedModelAdapter(
        const Duration(milliseconds: 20),
        const AgentResponse(
          text: '',
          toolCall: ToolCall(id: 'call-1', toolId: 'ok'),
        ),
      ),
    );
    addTearDown(harness.dispose);

    final result = await harness.executor.execute(
      _policyRequest(id: 'policy-timeout', timeoutMs: 1),
    );

    expect(result.terminalStatus, ExecutionLifecycleStatus.failed);
    expect(result.reason, 'timeout');
  });

  test('coalesced request records event ref durably', () async {
    final gate = Completer<void>();
    final harness = await _Harness.create(
      modelAdapter: _BlockingModelAdapter(gate.future),
    );
    addTearDown(harness.dispose);
    final first = ExecutionRequest.fromMcpEvent(
      sessionKey: 'system_main',
      prompt: 'first event',
      id: 'mcp-1',
      metadata: const <String, dynamic>{
        'runId': 'mcp-run',
        'duplicateKey': 'repo:update',
      },
    );
    final firstFuture = harness.executor.execute(first);
    await Future<void>.delayed(Duration.zero);

    final duplicate = await harness.executor.execute(
      ExecutionRequest.fromMcpEvent(
        sessionKey: 'system_main',
        prompt: 'second event',
        id: 'mcp-2',
        metadata: const <String, dynamic>{
          'runId': 'mcp-run',
          'duplicateKey': 'repo:update',
          'eventId': 'event-2',
        },
      ),
    );
    gate.complete();
    await firstFuture;

    expect(duplicate.admissionOutcome, ExecutionAdmissionOutcome.coalesced);
    final run = await harness.store.byId('mcp-run');
    expect(run!.coalescedEventRefs, contains('event-2'));
  });

  test('replace running sends cancellation and records supersession', () async {
    final gate = Completer<void>();
    final harness = await _Harness.create(
      modelAdapter: _BlockingModelAdapter(gate.future),
    );
    addTearDown(harness.dispose);
    final first = ExecutionRequest.persistent(
      sessionKey: 'system_main',
      prompt: 'first',
      id: 'replace-run',
      runId: 'replace-run',
    );
    final firstFuture = harness.executor.execute(first);
    await Future<void>.delayed(Duration.zero);

    final replacement = ExecutionRequest(
      id: 'replacement',
      source: ExecutionSource.system,
      sessionKey: 'system_main',
      prompt: 'replacement',
      visibility: ExecutionVisibility.chatAndBackground,
      createdAt: DateTime.now().toUtc(),
      classification: const ExecutionClassifierOutput(
        mode: ExecutionLifecycleMode.persistentRequest,
        classificationReason: 'system_persistent',
      ),
      runContext: const RunContext(runId: 'replacement'),
      policy: const ExecutionPolicy(
        allowToolUse: true,
        allowPersistence: true,
        allowSuspend: true,
        maxSteps: 12,
        maxToolCalls: 8,
        timeoutMs: 30000,
        duplicatePolicy: DuplicateExecutionPolicy.replaceRunning,
        queuePolicy: QueueExecutionPolicy.fifo,
        failurePolicy: FailureExecutionPolicy.failRun,
        completionPolicy: CompletionExecutionPolicy.both,
      ),
    );
    final replacementFuture = harness.executor.execute(replacement);
    await Future<void>.delayed(Duration.zero);
    gate.complete();

    final firstResult = await firstFuture;
    final replacementResult = await replacementFuture;

    expect(firstResult.terminalStatus, ExecutionLifecycleStatus.cancelled);
    expect(
      replacementResult.admissionOutcome,
      ExecutionAdmissionOutcome.replacedRunning,
    );
    final cancelled = await harness.store.byId('replace-run');
    expect(cancelled!.supersededByRequestId, 'replacement');
  });
}

ExecutionRequest _policyRequest({
  required String id,
  int maxSteps = 12,
  int maxToolCalls = 8,
  int timeoutMs = 30000,
}) {
  final base = ExecutionRequest.persistent(
    sessionKey: 'system_main',
    prompt: 'policy test',
    id: id,
    runId: id,
  );
  return ExecutionRequest(
    id: base.id,
    source: base.source,
    sessionKey: base.sessionKey,
    prompt: base.prompt,
    visibility: base.visibility,
    createdAt: base.createdAt,
    classification: base.classification,
    metadata: base.metadata,
    runContext: base.runContext,
    policy: ExecutionPolicy(
      allowToolUse: true,
      allowPersistence: true,
      allowSuspend: true,
      maxSteps: maxSteps,
      maxToolCalls: maxToolCalls,
      timeoutMs: timeoutMs,
      duplicatePolicy: DuplicateExecutionPolicy.allow,
      queuePolicy: QueueExecutionPolicy.fifo,
      failurePolicy: FailureExecutionPolicy.failRun,
      completionPolicy: CompletionExecutionPolicy.both,
    ),
  );
}

class _Harness {
  _Harness({
    required this.storage,
    required this.store,
    required this.executor,
  });

  final MemoryStorage storage;
  final RunStateStore store;
  final AgentLoopTaskExecutor executor;

  static Future<_Harness> create({
    required AgentModelAdapter modelAdapter,
    RunStateStore? store,
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
      ToolDefinition(
        id: 'ok',
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
    final runStateStore = store ?? InMemoryRunStateStore();
    await runStateStore.initialize();
    return _Harness(
      storage: storage,
      store: runStateStore,
      executor: AgentLoopTaskExecutor(
        agentLoop: loop,
        executionLogStore: InMemoryExecutionLogStore(),
        runStateStore: runStateStore,
      ),
    );
  }

  Future<void> dispose() async {
    await storage.close();
    await store.close();
  }
}

class _ContinuationAwareModelAdapter implements AgentModelAdapter {
  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    final continuation = context.messages
        .where((message) => message.metadata.containsKey('currentStepIndex'))
        .last;
    return AgentResponse(
      text:
          'resumed ${continuation.metadata['variables']} step=${continuation.metadata['currentStepIndex']}',
    );
  }
}

class _QueueModelAdapter implements AgentModelAdapter {
  _QueueModelAdapter(this._responses);

  final List<AgentResponse> _responses;
  var _index = 0;

  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    final response = _responses[_index];
    _index += 1;
    return response;
  }
}

class _BlockingModelAdapter implements AgentModelAdapter {
  _BlockingModelAdapter(this._gate);

  final Future<void> _gate;

  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    await _gate;
    return const AgentResponse(text: 'done');
  }
}

class _DelayedModelAdapter implements AgentModelAdapter {
  _DelayedModelAdapter(this._delay, this._response);

  final Duration _delay;
  final AgentResponse _response;

  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    await Future<void>.delayed(_delay);
    return _response;
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

Future<ToolResult> _okExecute(ToolCall call) async {
  return const ToolResult.success('ok');
}

Future<String> _tempDatabasePath() async {
  final directory = await Directory.systemTemp.createTemp(
    'openreef_execution_policy_',
  );
  return '${directory.path}${Platform.pathSeparator}execution.sqlite';
}
