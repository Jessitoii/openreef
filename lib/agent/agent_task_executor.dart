import 'dart:async';
import 'dart:convert';

import 'package:openreef/agent/agent_loop.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/execution_log.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/run_state.dart';

enum AgentTaskExecutionStatus { completed, frozen, failed, rejected }

enum ExecutionAdmissionOutcome {
  admitted,
  queued,
  rejected,
  coalesced,
  replacedRunning,
}

class ExecutionResult {
  const ExecutionResult({
    required this.requestId,
    required this.sessionKey,
    required this.source,
    required this.mode,
    required this.terminalStatus,
    required this.admissionOutcome,
    required this.policyReason,
    required this.visibility,
    required this.loopResult,
    this.runId,
    this.supersedesRunId,
    this.supersededByRequestId,
    this.transitions = const <RunStateTransition>[],
    this.standingOrderEvaluationIds = const <String>[],
  });

  final String requestId;
  final String sessionKey;
  final ExecutionSource source;
  final ExecutionLifecycleMode mode;
  final ExecutionLifecycleStatus terminalStatus;
  final ExecutionAdmissionOutcome admissionOutcome;
  final String policyReason;
  final ExecutionVisibility visibility;
  final AgentLoopResult loopResult;
  final String? runId;
  final String? supersedesRunId;
  final String? supersededByRequestId;
  final List<RunStateTransition> transitions;
  final List<String> standingOrderEvaluationIds;

  AgentLoopResult toAgentLoopResult() => loopResult;

  SessionResult get sessionResult => loopResult.sessionResult;

  String get text => loopResult.text;

  String? get reason => loopResult.reason;

  List<String> get toolsUsed => loopResult.toolsUsed;

  List<ToolResult> get toolResults => loopResult.toolResults;
}

class AgentTaskTriggerMetadata {
  const AgentTaskTriggerMetadata({
    required this.triggerId,
    required this.triggerName,
    required this.triggerType,
    required this.deliveryType,
    required this.payload,
    required this.deliveredAt,
    this.scheduledAt,
    this.appliedStandingOrderIds = const <String>[],
    this.standingOrderDirectives = const <String, Object?>{},
    this.standingOrderEvaluations = const <StandingOrderEvaluationRecord>[],
  });

  final String triggerId;
  final String triggerName;
  final String triggerType;
  final String deliveryType;
  final Map<String, Object?> payload;
  final DateTime deliveredAt;
  final DateTime? scheduledAt;
  final List<String> appliedStandingOrderIds;
  final Map<String, Object?> standingOrderDirectives;
  final List<StandingOrderEvaluationRecord> standingOrderEvaluations;

  String? get standingOrderInstructions {
    final display = standingOrderEvaluations
        .map((evaluation) => evaluation.displayText?.trim() ?? '')
        .where((entry) => entry.isNotEmpty)
        .join('\n');
    return display.isEmpty ? null : display;
  }

  Map<String, dynamic> toMetadataMap() {
    return <String, dynamic>{
      'triggerId': triggerId,
      'triggerName': triggerName,
      'triggerType': triggerType,
      'deliveryType': deliveryType,
      'payload': payload,
      'deliveredAt': deliveredAt.toIso8601String(),
      if (scheduledAt != null) 'scheduledAt': scheduledAt!.toIso8601String(),
      if (appliedStandingOrderIds.isNotEmpty)
        'appliedStandingOrderIds': appliedStandingOrderIds,
      if (standingOrderDirectives.isNotEmpty)
        'standingOrderDirectives': standingOrderDirectives,
      if (standingOrderEvaluations.isNotEmpty)
        'standingOrderEvaluations': standingOrderEvaluations
            .map(_standingOrderEvaluationToMetadata)
            .toList(growable: false),
      'duplicateKey': triggerId,
    };
  }

  Map<String, Object?> _standingOrderEvaluationToMetadata(
    StandingOrderEvaluationRecord evaluation,
  ) {
    return <String, Object?>{
      'evaluationId': evaluation.evaluationId,
      'runId': evaluation.runId,
      'ruleId': evaluation.ruleId,
      'triggerType': evaluation.triggerType,
      'condition': evaluation.condition,
      'action': evaluation.action,
      'priority': evaluation.priority,
      'status': evaluation.status.name,
      'reason': evaluation.reason,
      'evaluatedAt': evaluation.evaluatedAt.toUtc().toIso8601String(),
      if (evaluation.displayText != null) 'displayText': evaluation.displayText,
    };
  }
}

class AgentTaskRequest {
  const AgentTaskRequest({
    required this.sessionKey,
    required this.prompt,
    required this.source,
    this.visibility = ExecutionVisibility.background,
    this.triggerMetadata,
    this.metadata = const <String, dynamic>{},
  });

  final String sessionKey;
  final String prompt;
  final ExecutionSource source;
  final ExecutionVisibility visibility;
  final AgentTaskTriggerMetadata? triggerMetadata;
  final Map<String, dynamic> metadata;

  ExecutionRequest toExecutionRequest() {
    final timestamp = DateTime.now().toUtc();
    final mergedMetadata = <String, dynamic>{
      ...metadata,
      ...?triggerMetadata?.toMetadataMap(),
    };
    final requestId = '${source.name}_${timestamp.microsecondsSinceEpoch}';
    final effectiveMetadata = mergedMetadata.isEmpty ? null : mergedMetadata;
    return switch (source) {
      ExecutionSource.user => ExecutionRequest.fromUserMessage(
        sessionKey: sessionKey,
        prompt: prompt,
        id: requestId,
        createdAt: timestamp,
        visibility: visibility,
        metadata: effectiveMetadata,
      ),
      ExecutionSource.mcpEvent => ExecutionRequest.fromMcpEvent(
        sessionKey: sessionKey,
        prompt: prompt,
        id: requestId,
        createdAt: timestamp,
        visibility: visibility,
        metadata: effectiveMetadata,
      ),
      ExecutionSource.trigger ||
      ExecutionSource.schedule => ExecutionRequest.fromTrigger(
        sessionKey: sessionKey,
        prompt: prompt,
        source: source,
        id: requestId,
        createdAt: timestamp,
        visibility: visibility,
        metadata: effectiveMetadata,
      ),
      ExecutionSource.resumeSignal => ExecutionRequest.resume(
        sessionKey: sessionKey,
        prompt: prompt,
        runId: effectiveMetadata?['runId'] as String? ?? requestId,
        id: requestId,
        createdAt: timestamp,
        visibility: visibility,
        metadata: effectiveMetadata,
      ),
      ExecutionSource.system => ExecutionRequest.persistent(
        sessionKey: sessionKey,
        prompt: prompt,
        id: requestId,
        createdAt: timestamp,
        visibility: visibility,
        metadata: effectiveMetadata,
      ),
    };
  }
}

class AgentTaskExecutionResult {
  const AgentTaskExecutionResult({
    required this.status,
    required this.text,
    required this.reason,
    required this.toolsUsed,
  });

  final AgentTaskExecutionStatus status;
  final String text;
  final String reason;
  final List<String> toolsUsed;

  factory AgentTaskExecutionResult.fromLoopResult(AgentLoopResult result) {
    return AgentTaskExecutionResult(
      status: switch (result.sessionResult) {
        SessionResult.completed => AgentTaskExecutionStatus.completed,
        SessionResult.frozen => AgentTaskExecutionStatus.frozen,
        SessionResult.failed ||
        SessionResult.cancelled ||
        SessionResult.suspended => AgentTaskExecutionStatus.failed,
      },
      text: result.text,
      reason: result.reason ?? '',
      toolsUsed: result.toolsUsed,
    );
  }
}

abstract class ChatExecutionSink {
  Future<void> appendExecutionResult(
    ExecutionRequest request,
    ExecutionResult result,
  );
}

abstract class BackgroundExecutionSink {
  Future<void> recordExecution(
    ExecutionRequest request,
    ExecutionResult result,
  );
}

abstract class AgentTaskExecutor {
  Future<ExecutionResult> execute(ExecutionRequest request);

  Future<AgentTaskExecutionResult> executeTask(AgentTaskRequest request);
}

class AgentLoopTaskExecutor implements AgentTaskExecutor {
  AgentLoopTaskExecutor({
    required AgentLoop agentLoop,
    required ExecutionLogStore executionLogStore,
    ChatExecutionSink? chatSink,
    BackgroundExecutionSink? backgroundSink,
    RunStateStore? runStateStore,
    DateTime Function()? clock,
  }) : _agentLoop = agentLoop,
       _executionLogStore = executionLogStore,
       _chatSink = chatSink,
       _backgroundSink = backgroundSink,
       _runStateStore = runStateStore ?? InMemoryRunStateStore(),
       _clock = clock ?? DateTime.now;

  final AgentLoop _agentLoop;
  final ExecutionLogStore _executionLogStore;
  final ChatExecutionSink? _chatSink;
  final BackgroundExecutionSink? _backgroundSink;
  final RunStateStore _runStateStore;
  final DateTime Function() _clock;
  final Set<String> _activeSessionKeys = <String>{};
  final Map<String, CancellationSignal> _activeCancellations =
      <String, CancellationSignal>{};
  final Map<String, Future<ExecutionResult>> _sessionQueue =
      <String, Future<ExecutionResult>>{};
  final Map<String, ExecutionRequest> _queuedById =
      <String, ExecutionRequest>{};

  RunStateStore get runStateStore => _runStateStore;

  @override
  Future<AgentTaskExecutionResult> executeTask(AgentTaskRequest request) async {
    final result = await execute(request.toExecutionRequest());
    return AgentTaskExecutionResult.fromLoopResult(result.toAgentLoopResult());
  }

  @override
  Future<ExecutionResult> execute(ExecutionRequest request) async {
    await _runStateStore.initialize();
    final admission = await _admit(request);
    if (admission.rejectedReason != null) {
      return _reject(request, admission.rejectedReason!, admission.outcome);
    }
    if (admission.queued) {
      return _enqueue(request);
    }
    if (admission.outcome == ExecutionAdmissionOutcome.replacedRunning) {
      await _waitForSessionIdle(request.sessionKey);
    }
    return _executeNow(request, admissionOutcome: admission.outcome);
  }

  Future<ExecutionResult> _executeNow(
    ExecutionRequest request, {
    required ExecutionAdmissionOutcome admissionOutcome,
  }) async {
    final startedAt = _clock().toUtc();
    var runState = await _prepareRunState(request, startedAt);
    final cancellationSignal = CancellationSignal();
    if (runState != null) {
      _activeCancellations[runState.runId] = cancellationSignal;
    }
    _executionLogStore.start(
      ExecutionRecord(
        id: request.id,
        sessionKey: request.sessionKey,
        source: request.source,
        status: ExecutionStatus.running,
        toolsUsed: const <String>[],
        createdAt: request.createdAt.toUtc(),
      ),
    );

    if (!_activeSessionKeys.add(request.sessionKey)) {
      final result = const AgentLoopResult(
        sessionResult: SessionResult.failed,
        text: '',
        reason: 'session_busy',
        toolsUsed: <String>[],
      );
      return _completeExecution(
        request,
        result,
        status: ExecutionStatus.failed,
        errorSummary: 'An execution is already running for this session.',
        runState: runState,
        admissionOutcome: ExecutionAdmissionOutcome.rejected,
        policyReason: 'session_busy',
      );
    }

    try {
      runState = await _transitionRunState(
        runState,
        ExecutionLifecycleStatus.running,
        request.mode == ExecutionLifecycleMode.resumeRequest
            ? 'resume_request'
            : 'executor_started',
        requestId: request.id,
      );
      final continuation = _continuationFor(request, runState);
      final result = await _agentLoop.run(
        _buildPrompt(request),
        sessionKey: request.sessionKey,
        conversationHistory: _conversationHistoryFromMetadata(request.metadata),
        modelContextWindow:
            (request.metadata?['modelContextWindow'] as int?) ?? 8192,
        compactRequested:
            (request.metadata?['compactRequested'] as bool?) ?? false,
        recentFiles:
            (request.metadata?['recentFiles'] as List?)
                ?.map((entry) => entry.toString())
                .toList(growable: false) ??
            const <String>[],
        control: LoopControl(
          maxSteps: request.policy.maxSteps,
          maxToolCalls: request.policy.maxToolCalls,
          timeout: Duration(milliseconds: request.policy.timeoutMs),
          cancellationSignal: cancellationSignal,
        ),
        continuation: continuation,
      );
      if ((request.metadata?['suspendAfterRun'] as bool?) ?? false) {
        runState = await _transitionRunState(
          runState,
          ExecutionLifecycleStatus.suspended,
          'explicit_suspend',
          requestId: request.id,
          currentStepIndex: result.continuation.currentStepIndex,
          variables: result.continuation.variables,
          waitingReason:
              request.metadata?['waitingReason'] as String? ??
              'explicit_suspend',
          waitingMetadata:
              (request.metadata?['waitingMetadata'] as Map?)
                  ?.cast<String, Object?>() ??
              result.continuation.waitingMetadata,
        );
        return _completeExecution(
          request,
          AgentLoopResult(
            sessionResult: SessionResult.suspended,
            text: result.text,
            reason: 'suspended',
            toolsUsed: result.toolsUsed,
            toolResults: result.toolResults,
            stepCount: result.stepCount,
            toolCallCount: result.toolCallCount,
            continuation: result.continuation,
          ),
          status: ExecutionStatus.running,
          runState: runState,
          admissionOutcome: admissionOutcome,
          policyReason: 'suspended',
        );
      }
      return _completeExecution(
        request,
        result,
        status: _mapStatus(result.sessionResult),
        errorSummary: _errorSummaryFor(result),
        runState: runState,
        admissionOutcome: admissionOutcome,
        policyReason: result.reason ?? 'completed',
      );
    } catch (error) {
      final result = AgentLoopResult(
        sessionResult: SessionResult.failed,
        text: '',
        reason: request.policy.failurePolicy == FailureExecutionPolicy.freezeRun
            ? 'executor_frozen'
            : 'executor_failure',
        toolsUsed: const <String>[],
      );
      return _completeExecution(
        request,
        result,
        status: ExecutionStatus.failed,
        errorSummary: error.toString(),
        runState: runState,
        admissionOutcome: admissionOutcome,
        policyReason: result.reason ?? 'executor_failure',
      );
    } finally {
      _activeSessionKeys.remove(request.sessionKey);
      if (runState != null) {
        _activeCancellations.remove(runState.runId);
      }
    }
  }

  Future<ExecutionResult> _completeExecution(
    ExecutionRequest request,
    AgentLoopResult result, {
    required ExecutionStatus status,
    String? errorSummary,
    RunState? runState,
    required ExecutionAdmissionOutcome admissionOutcome,
    required String policyReason,
  }) async {
    _executionLogStore.complete(
      request.id,
      status: status,
      toolsUsed: result.toolsUsed,
      toolResults: result.toolResults,
      finishedAt: _clock().toUtc(),
      failureReason: result.sessionResult == SessionResult.completed
          ? null
          : result.reason,
      errorSummary: errorSummary,
    );
    if (runState != null) {
      runState = await _transitionRunState(
        runState,
        _lifecycleStatusFor(result),
        result.reason ?? status.name,
        terminalReason: result.reason,
        requestId: request.id,
        currentStepIndex: result.continuation.currentStepIndex,
        variables: result.continuation.variables,
      );
    }
    final executionResult = ExecutionResult(
      requestId: request.id,
      sessionKey: request.sessionKey,
      source: request.source,
      mode: request.mode,
      terminalStatus: runState?.status ?? _lifecycleStatusFor(result),
      admissionOutcome: admissionOutcome,
      policyReason: policyReason,
      visibility: request.visibility,
      loopResult: result,
      runId: runState?.runId,
      supersededByRequestId: runState?.supersededByRequestId,
      supersedesRunId: runState?.supersedesRunId,
      transitions: runState?.transitions ?? const <RunStateTransition>[],
      standingOrderEvaluationIds:
          (request.metadata?['standingOrderEvaluationIds'] as List?)
              ?.map((entry) => entry.toString())
              .toList(growable: false) ??
          const <String>[],
    );
    await _routeOutput(request, executionResult);
    return executionResult;
  }

  Future<_AdmissionDecision> _admit(ExecutionRequest request) async {
    if (request.mode == ExecutionLifecycleMode.resumeRequest) {
      final runId = request.runContext?.runId;
      final run = runId == null ? null : await _runStateStore.byId(runId);
      if (run == null || !run.isResumable) {
        return const _AdmissionDecision.reject(
          'missing_resumable_run',
          ExecutionAdmissionOutcome.rejected,
        );
      }
      return const _AdmissionDecision.run();
    }
    final activeRun = await _activeRunFor(request);
    if (activeRun != null) {
      switch (request.policy.duplicatePolicy) {
        case DuplicateExecutionPolicy.allow:
          return const _AdmissionDecision.run();
        case DuplicateExecutionPolicy.queue:
          return const _AdmissionDecision.queue();
        case DuplicateExecutionPolicy.reject:
          return const _AdmissionDecision.reject(
            'duplicate_active_run',
            ExecutionAdmissionOutcome.rejected,
          );
        case DuplicateExecutionPolicy.replaceRunning:
          await _requestCancellation(
            activeRun,
            supersededByRequestId: request.id,
            reason: 'replace_running',
          );
          return const _AdmissionDecision.replaceRunning();
        case DuplicateExecutionPolicy.coalesce:
          await _coalesceInto(activeRun, request);
          return const _AdmissionDecision.reject(
            'duplicate_coalesced',
            ExecutionAdmissionOutcome.coalesced,
          );
      }
    }

    if (_activeSessionKeys.contains(request.sessionKey)) {
      if (request.source == ExecutionSource.user) {
        await _dropQueuedBackgroundForSession(request.sessionKey);
        return const _AdmissionDecision.reject(
          'session_busy',
          ExecutionAdmissionOutcome.rejected,
        );
      }
      if (request.policy.queuePolicy == QueueExecutionPolicy.noneReject) {
        return const _AdmissionDecision.reject(
          'session_busy',
          ExecutionAdmissionOutcome.rejected,
        );
      }
      return const _AdmissionDecision.queue();
    }

    if (request.source == ExecutionSource.user) {
      await _dropQueuedBackgroundForSession(request.sessionKey);
    }
    return const _AdmissionDecision.run();
  }

  Future<ExecutionResult> _enqueue(ExecutionRequest request) async {
    _queuedById[request.id] = request;
    final queuedRun = await _prepareRunState(request, _clock().toUtc());
    await _runStateStore.enqueue(
      QueueAdmissionRecord(
        requestId: request.id,
        runId: queuedRun?.runId ?? request.id,
        sessionId: request.sessionKey,
        status: QueueAdmissionStatus.queued,
        priority: _priorityFor(request),
        createdAt: _clock().toUtc(),
        coalesceKey: request.policy.coalesceKey,
        payload: <String, Object?>{
          'source': request.source.name,
          'mode': request.mode.name,
          'prompt': request.prompt,
        },
      ),
    );
    final previous =
        _sessionQueue[request.sessionKey] ??
        Future<ExecutionResult>.value(
          ExecutionResult(
            requestId: 'queue_seed',
            sessionKey: request.sessionKey,
            source: request.source,
            mode: request.mode,
            terminalStatus: ExecutionLifecycleStatus.completed,
            admissionOutcome: ExecutionAdmissionOutcome.admitted,
            policyReason: 'queue_seed',
            visibility: request.visibility,
            loopResult: const AgentLoopResult(
              sessionResult: SessionResult.completed,
              text: '',
              reason: 'queue_seed',
            ),
          ),
        );
    final next = previous.then((_) {
      if (!_queuedById.containsKey(request.id)) {
        return _reject(
          request,
          'preempted_by_chat',
          ExecutionAdmissionOutcome.rejected,
        );
      }
      return _waitForSessionIdle(request.sessionKey).then((_) {
        if (!_queuedById.containsKey(request.id)) {
          return _reject(
            request,
            'preempted_by_chat',
            ExecutionAdmissionOutcome.rejected,
          );
        }
        _queuedById.remove(request.id);
        return _runStateStore
            .updateQueueStatus(
              request.id,
              QueueAdmissionStatus.claimed,
              claimedAt: _clock().toUtc(),
            )
            .then(
              (_) => _executeNow(
                request,
                admissionOutcome: ExecutionAdmissionOutcome.queued,
              ),
            );
      });
    });
    _sessionQueue[request.sessionKey] = next.whenComplete(() {
      if (_sessionQueue[request.sessionKey] == next) {
        _sessionQueue.remove(request.sessionKey);
      }
    });
    return next;
  }

  Future<void> _waitForSessionIdle(String sessionKey) async {
    while (_activeSessionKeys.contains(sessionKey)) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  LoopContinuation _continuationFor(ExecutionRequest request, RunState? run) {
    final context = request.runContext;
    return LoopContinuation(
      currentStepIndex: run?.currentStepIndex ?? context?.currentStepIndex ?? 0,
      variables:
          run?.variables ?? context?.variables ?? const <String, Object?>{},
      waitingReason: run?.waitingReason ?? context?.waitingReason,
      waitingMetadata:
          run?.waitingMetadata ??
          context?.waitingMetadata ??
          const <String, Object?>{},
      resumeToken: run?.resumeToken ?? context?.resumeToken,
    );
  }

  int _priorityFor(ExecutionRequest request) {
    final explicit = request.metadata?['priority'];
    if (explicit is int) {
      return explicit;
    }
    return switch (request.policy.queuePolicy) {
      QueueExecutionPolicy.priority => 100,
      QueueExecutionPolicy.fifo || QueueExecutionPolicy.noneReject => 0,
    };
  }

  Future<void> _requestCancellation(
    RunState activeRun, {
    required String supersededByRequestId,
    required String reason,
  }) async {
    _activeCancellations[activeRun.runId]?.cancel(reason);
    final latest = await _runStateStore.byId(activeRun.runId) ?? activeRun;
    await _runStateStore.save(
      latest.copyWith(
        cancelRequested: true,
        supersededByRequestId: supersededByRequestId,
        updatedAt: _clock().toUtc(),
      ),
    );
  }

  Future<void> _coalesceInto(
    RunState activeRun,
    ExecutionRequest request,
  ) async {
    final latest = await _runStateStore.byId(activeRun.runId) ?? activeRun;
    final eventRef =
        request.metadata?['eventId'] as String? ??
        request.policy.coalesceKey ??
        request.id;
    await _runStateStore.save(
      latest.copyWith(
        coalescedEventRefs: <String>{
          ...latest.coalescedEventRefs,
          eventRef,
        }.toList(growable: false),
        updatedAt: _clock().toUtc(),
      ),
    );
  }

  Future<ExecutionResult> _reject(
    ExecutionRequest request,
    String reason,
    ExecutionAdmissionOutcome outcome,
  ) async {
    final runState = await _prepareRunState(request, _clock().toUtc());
    final shouldTransitionRejection =
        runState != null &&
        !(runState.isActive && runState.requestIdOrigin != request.id);
    final transitioned = shouldTransitionRejection
        ? await _transitionRunState(
            runState,
            ExecutionLifecycleStatus.rejected,
            reason,
            terminalReason: reason,
            requestId: request.id,
          )
        : runState;
    final result = AgentLoopResult(
      sessionResult: SessionResult.failed,
      text: '',
      reason: reason,
      toolsUsed: const <String>[],
    );
    _executionLogStore.start(
      ExecutionRecord(
        id: request.id,
        sessionKey: request.sessionKey,
        source: request.source,
        status: ExecutionStatus.failed,
        toolsUsed: const <String>[],
        createdAt: request.createdAt.toUtc(),
        finishedAt: _clock().toUtc(),
        failureReason: reason,
        errorSummary: reason,
      ),
    );
    return ExecutionResult(
      requestId: request.id,
      sessionKey: request.sessionKey,
      source: request.source,
      mode: request.mode,
      terminalStatus: transitioned?.status ?? ExecutionLifecycleStatus.rejected,
      admissionOutcome: outcome,
      policyReason: reason,
      visibility: request.visibility,
      loopResult: result,
      runId: transitioned?.runId,
      transitions: transitioned?.transitions ?? const <RunStateTransition>[],
    );
  }

  Future<RunState?> _prepareRunState(
    ExecutionRequest request,
    DateTime at,
  ) async {
    if (!request.policy.allowPersistence ||
        request.mode == ExecutionLifecycleMode.ephemeralRequest) {
      return null;
    }
    if (request.mode == ExecutionLifecycleMode.resumeRequest) {
      final runId = request.runContext?.runId;
      final existing = runId == null ? null : await _runStateStore.byId(runId);
      if (existing == null || !existing.isResumable) {
        return RunState(
          runId: runId ?? request.id,
          requestIdOrigin: request.id,
          status: ExecutionLifecycleStatus.queued,
          mode: request.mode,
          currentStepIndex: 0,
          variables: const <String, Object?>{},
          createdAt: at,
          updatedAt: at,
          sessionId: request.sessionKey,
          terminalReason: 'missing_resumable_run',
        );
      }
      return existing;
    }
    final context = request.runContext;
    final runId = context?.runId ?? request.id;
    final existing = await _runStateStore.byId(runId);
    if (existing != null) {
      return existing;
    }
    final runState = RunState(
      runId: runId,
      requestIdOrigin: request.id,
      status: ExecutionLifecycleStatus.queued,
      mode: request.mode,
      currentStepIndex: context?.currentStepIndex ?? 0,
      variables: Map<String, Object?>.unmodifiable(
        context?.variables ?? const <String, Object?>{},
      ),
      createdAt: at,
      updatedAt: at,
      sessionId: request.sessionKey,
      workflowId: context?.workflowId,
      resumeToken: context?.resumeToken,
      waitingReason: context?.waitingReason,
      waitingMetadata: context?.waitingMetadata ?? const <String, Object?>{},
    );
    await _runStateStore.save(runState);
    await _persistStandingOrderEvaluations(request, runState.runId);
    return runState;
  }

  Future<void> _persistStandingOrderEvaluations(
    ExecutionRequest request,
    String runId,
  ) async {
    final raw = request.metadata?['standingOrderEvaluations'];
    if (raw is! List) {
      return;
    }
    final evaluations = raw
        .whereType<Map>()
        .map((entry) {
          final map = Map<String, Object?>.from(entry);
          return StandingOrderEvaluationRecord(
            evaluationId: map['evaluationId'] as String,
            runId: runId,
            ruleId: map['ruleId'] as String,
            triggerType: map['triggerType'] as String,
            condition:
                (map['condition'] as Map?)?.cast<String, Object?>() ??
                const <String, Object?>{},
            action:
                (map['action'] as Map?)?.cast<String, Object?>() ??
                const <String, Object?>{},
            priority: map['priority'] as int? ?? 0,
            status: StandingOrderEvaluationStatus.values.firstWhere(
              (status) => status.name == map['status'],
              orElse: () => StandingOrderEvaluationStatus.notMatched,
            ),
            reason: map['reason'] as String? ?? 'unknown',
            evaluatedAt: DateTime.parse(map['evaluatedAt'] as String).toUtc(),
            displayText: map['displayText'] as String?,
          );
        })
        .toList(growable: false);
    await _runStateStore.saveStandingOrderEvaluations(evaluations);
  }

  Future<RunState?> _activeRunFor(ExecutionRequest request) async {
    final runId = request.runContext?.runId;
    if (runId != null) {
      final run = await _runStateStore.byId(runId);
      if (run != null && run.isActive) {
        return run;
      }
    }
    for (final run in await _runStateStore.activeForSession(
      request.sessionKey,
    )) {
      if (request.policy.duplicatePolicy ==
          DuplicateExecutionPolicy.replaceRunning) {
        return run;
      }
      if (request.policy.coalesceKey != null &&
          run.runId == request.policy.coalesceKey) {
        return run;
      }
    }
    if (request.policy.coalesceKey != null) {
      final active = await _runStateStore.activeByCoalesceKey(
        request.policy.coalesceKey!,
      );
      if (active.isNotEmpty) {
        return active.first;
      }
    }
    return null;
  }

  Future<void> _dropQueuedBackgroundForSession(String sessionKey) async {
    final queued = _queuedById.values
        .where(
          (request) =>
              request.sessionKey == sessionKey &&
              request.visibility != ExecutionVisibility.chat,
        )
        .toList(growable: false);
    for (final request in queued) {
      _queuedById.remove(request.id);
      final runId = request.runContext?.runId ?? request.id;
      final run = await _runStateStore.byId(runId);
      if (run != null) {
        await _transitionRunState(
          run,
          ExecutionLifecycleStatus.rejected,
          'preempted_by_chat',
          terminalReason: 'preempted_by_chat',
          requestId: request.id,
        );
      }
      await _runStateStore.updateQueueStatus(
        request.id,
        QueueAdmissionStatus.cancelled,
        reason: 'preempted_by_chat',
      );
    }
  }

  Future<RunState?> _transitionRunState(
    RunState? runState,
    ExecutionLifecycleStatus status,
    String reason, {
    String? terminalReason,
    String? requestId,
    int? currentStepIndex,
    Map<String, Object?>? variables,
    String? waitingReason,
    Map<String, Object?>? waitingMetadata,
  }) {
    if (runState == null) {
      return Future<RunState?>.value();
    }
    return _transitionRunStateAsync(
      runState,
      status,
      reason,
      terminalReason: terminalReason,
      requestId: requestId,
      currentStepIndex: currentStepIndex,
      variables: variables,
      waitingReason: waitingReason,
      waitingMetadata: waitingMetadata,
    );
  }

  Future<RunState?> _transitionRunStateAsync(
    RunState runState,
    ExecutionLifecycleStatus status,
    String reason, {
    String? terminalReason,
    String? requestId,
    int? currentStepIndex,
    Map<String, Object?>? variables,
    String? waitingReason,
    Map<String, Object?>? waitingMetadata,
  }) async {
    final latest = await _runStateStore.byId(runState.runId) ?? runState;
    if (latest.status == status) {
      return latest;
    }
    final next = const ExecutionLifecycleMachine().transition(
      run: latest,
      to: status,
      reason: reason,
      at: _clock().toUtc(),
      requestId: requestId,
      currentStepIndex: currentStepIndex,
      variables: variables,
      waitingReason: waitingReason,
      waitingMetadata: waitingMetadata,
      terminalReason: terminalReason,
      clearWaitingReason: status == ExecutionLifecycleStatus.running,
    );
    await _runStateStore.save(next);
    await _runStateStore.saveTransition(next.transitions.last);
    return next;
  }

  Future<void> _routeOutput(
    ExecutionRequest request,
    ExecutionResult result,
  ) async {
    switch (request.visibility) {
      case ExecutionVisibility.chat:
        final chatSink = _chatSink;
        if (chatSink != null) {
          await chatSink.appendExecutionResult(request, result);
        }
      case ExecutionVisibility.background:
        final backgroundSink = _backgroundSink;
        if (backgroundSink != null) {
          await backgroundSink.recordExecution(request, result);
        }
      case ExecutionVisibility.chatAndBackground:
        final chatSink = _chatSink;
        if (chatSink != null) {
          await chatSink.appendExecutionResult(request, result);
        }
        final backgroundSink = _backgroundSink;
        if (backgroundSink != null) {
          await backgroundSink.recordExecution(request, result);
        }
    }
  }

  ExecutionStatus _mapStatus(SessionResult result) {
    return switch (result) {
      SessionResult.completed => ExecutionStatus.completed,
      SessionResult.frozen => ExecutionStatus.frozen,
      SessionResult.cancelled => ExecutionStatus.cancelled,
      SessionResult.suspended => ExecutionStatus.suspended,
      SessionResult.failed => ExecutionStatus.failed,
    };
  }

  String? _errorSummaryFor(AgentLoopResult result) {
    if (result.sessionResult == SessionResult.completed) {
      return null;
    }
    final trimmed = result.text.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return result.reason;
  }

  String _buildPrompt(ExecutionRequest request) {
    final trimmedPrompt = request.prompt.trim();
    if (request.metadata == null || request.metadata!.isEmpty) {
      return trimmedPrompt;
    }

    final sourceLabel = switch (request.source) {
      ExecutionSource.user => 'USER',
      ExecutionSource.trigger => 'TRIGGER',
      ExecutionSource.schedule => 'SCHEDULE',
      ExecutionSource.mcpEvent => 'MCP_EVENT',
      ExecutionSource.resumeSignal => 'RESUME',
      ExecutionSource.system => 'SYSTEM',
    };
    final metadata = Map<String, dynamic>.from(request.metadata!)
      ..remove('conversationHistory')
      ..remove('modelContextWindow')
      ..remove('compactRequested')
      ..remove('recentFiles');
    metadata['executionMode'] = request.mode.name;
    metadata['lifecycleStatus'] = ExecutionLifecycleStatus.running.name;
    if (metadata.isEmpty) {
      return trimmedPrompt;
    }
    return '$sourceLabel EXECUTION\nmetadata: ${_canonicalJson(metadata)}\n\n$trimmedPrompt';
  }

  ExecutionLifecycleStatus _lifecycleStatusFor(AgentLoopResult result) {
    return switch (result.sessionResult) {
      SessionResult.completed => ExecutionLifecycleStatus.completed,
      SessionResult.cancelled => ExecutionLifecycleStatus.cancelled,
      SessionResult.suspended => ExecutionLifecycleStatus.suspended,
      SessionResult.frozen ||
      SessionResult.failed => ExecutionLifecycleStatus.failed,
    };
  }

  String _canonicalJson(Map<String, dynamic> value) {
    final sortedKeys = value.keys.toList()..sort();
    return jsonEncode(<String, dynamic>{
      for (final key in sortedKeys) key: value[key],
    });
  }

  List<AgentMessage> _conversationHistoryFromMetadata(
    Map<String, dynamic>? metadata,
  ) {
    final rawHistory = metadata?['conversationHistory'];
    if (rawHistory is! List) {
      return const <AgentMessage>[];
    }
    return rawHistory
        .whereType<Map>()
        .map(
          (entry) => AgentMessage(
            role: _roleFromName(entry['role'] as String?),
            content: entry['content'] as String? ?? '',
            turnNumber: entry['turnNumber'] as int?,
          ),
        )
        .toList(growable: false);
  }

  AgentMessageRole _roleFromName(String? value) {
    return switch (value) {
      'system' => AgentMessageRole.system,
      'assistant' => AgentMessageRole.assistant,
      'tool' => AgentMessageRole.tool,
      'toolError' => AgentMessageRole.toolError,
      'summary' => AgentMessageRole.summary,
      'standingOrder' => AgentMessageRole.standingOrder,
      'memory' => AgentMessageRole.memory,
      _ => AgentMessageRole.user,
    };
  }
}

class _AdmissionDecision {
  const _AdmissionDecision.run()
    : queued = false,
      rejectedReason = null,
      outcome = ExecutionAdmissionOutcome.admitted;

  const _AdmissionDecision.queue()
    : queued = true,
      rejectedReason = null,
      outcome = ExecutionAdmissionOutcome.queued;

  const _AdmissionDecision.replaceRunning()
    : queued = false,
      rejectedReason = null,
      outcome = ExecutionAdmissionOutcome.replacedRunning;

  const _AdmissionDecision.reject(this.rejectedReason, this.outcome)
    : queued = false;

  final bool queued;
  final String? rejectedReason;
  final ExecutionAdmissionOutcome outcome;
}
