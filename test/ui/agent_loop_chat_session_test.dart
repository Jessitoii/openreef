import 'package:openreef/agent/agent_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/runtime_transcript_event.dart';
import 'package:openreef/ui/agent_loop_chat_session.dart';
import 'package:openreef/ui/chat_session_port.dart';

void main() {
  test(
    'controller exposes pending approval and resolves it through approve',
    () async {
      final controller = MainAgentApprovalController();

      final approvalFuture = controller.confirmToolCall(
        const ToolCall(
          id: 'call-1',
          toolId: 'volume_set',
          arguments: <String, Object?>{'level': 0.25},
        ),
      );

      expect(controller.pendingApproval?.toolId, 'volume_set');
      expect(controller.pendingApproval?.arguments['level'], 0.25);

      controller.approvePendingApproval();
      await expectLater(approvalFuture, completion(isTrue));
      expect(controller.pendingApproval, isNull);
    },
  );

  test('controller can reject a pending approval', () async {
    final controller = MainAgentApprovalController();

    final approvalFuture = controller.confirmToolCall(
      const ToolCall(id: 'call-2', toolId: 'volume_set'),
    );

    controller.rejectPendingApproval();

    await expectLater(approvalFuture, completion(isFalse));
    expect(controller.pendingApproval, isNull);
  });

  test(
    'controller surfaces mailbox approval and clears it after approve',
    () async {
      final mailbox = AgentMailbox(idGenerator: () => 'mailbox-1');
      addTearDown(mailbox.dispose);
      final controller = MainAgentApprovalController(mailbox: mailbox);

      final decisionFuture = mailbox.requestApproval(
        workerSessionKey: 'agent:main:sub:worker-1',
        call: const ToolCall(
          id: 'call-mailbox',
          toolId: 'volume_set',
          arguments: <String, Object?>{'level': 0.3},
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(controller.pendingApproval?.toolId, 'volume_set');

      controller.approvePendingApproval();

      final decision = await decisionFuture;
      expect(decision.isApproved, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(controller.pendingApproval, isNull);
    },
  );

  test('controller clears mailbox approval after timeout resolution', () async {
    final mailbox = AgentMailbox(
      idGenerator: () => 'mailbox-timeout',
      approvalTimeout: Duration(milliseconds: 10),
    );
    addTearDown(mailbox.dispose);
    final controller = MainAgentApprovalController(mailbox: mailbox);

    await mailbox.requestApproval(
      workerSessionKey: 'agent:main:sub:worker-timeout',
      call: const ToolCall(id: 'call-timeout', toolId: 'volume_set'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.pendingApproval, isNull);
  });

  test(
    'chat session maps completed / frozen / failed results distinctly',
    () async {
      final completedSession = await _runSessionWithResult(
        const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      );
      expect(
        completedSession.messages.last.sender,
        ChatMessageSender.assistant,
      );
      expect(completedSession.messages.last.text, 'done');
      expect(completedSession.activities, isEmpty);

      final frozenSession = await _runSessionWithResult(
        const AgentLoopResult(
          sessionResult: SessionResult.frozen,
          text: '',
          reason: 'rejection_loop',
        ),
      );
      expect(frozenSession.messages.last.sender, ChatMessageSender.assistant);
      expect(
        frozenSession.messages.last.text,
        contains('same blocked tool request'),
      );
      expect(frozenSession.activities, isEmpty);

      final failedSession = await _runSessionWithResult(
        const AgentLoopResult(
          sessionResult: SessionResult.failed,
          text: '',
          reason: 'generation_failure',
        ),
      );
      expect(failedSession.messages.last.sender, ChatMessageSender.assistant);
      expect(
        failedSession.messages.last.text,
        'The agent turn failed during model generation.',
      );
      expect(failedSession.activities, isEmpty);
    },
  );

  test(
    'sendMessage projects final result when executor has no chat sink',
    () async {
      final executor = _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'Visible without executor sink.',
          reason: 'completed',
        ),
      );
      final session = AgentLoopChatSession(taskExecutor: executor);

      await session.sendMessage('hello');

      expect(session.messages.last.sender, ChatMessageSender.assistant);
      expect(session.messages.last.text, 'Visible without executor sink.');
      expect(
        session.messages.where(
          (message) => message.sender == ChatMessageSender.assistant,
        ),
        hasLength(1),
      );
    },
  );

  test('failed result surfaces concrete exception details in debug', () async {
    final session = await _runSessionWithResult(
      const AgentLoopResult(
        sessionResult: SessionResult.failed,
        text: '',
        reason: 'context_assembly_failure',
        exceptionType: 'SemanticEmbeddingUnavailableException',
        errorMessage: 'No active embedding model set',
      ),
    );

    expect(session.messages.last.sender, ChatMessageSender.assistant);
    expect(session.messages.last.text, contains('context_assembly_failure'));
    expect(
      session.messages.last.text,
      contains('SemanticEmbeddingUnavailableException'),
    );
    expect(
      session.messages.last.text,
      contains('No active embedding model set'),
    );
  });

  test('missing semantic embedder maps to actionable setup message', () async {
    final session = await _runSessionWithResult(
      const AgentLoopResult(
        sessionResult: SessionResult.failed,
        text: '',
        reason: 'semantic_embedding_model_not_ready',
      ),
    );

    expect(
      session.messages.last.text,
      contains('Semantic retrieval needs an embedding model'),
    );
    expect(session.messages.last.text, contains('Settings'));
  });

  test(
    'final fallback replaces empty runtime bubble for same request',
    () async {
      final executor = _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      );
      final session = AgentLoopChatSession(taskExecutor: executor);
      final request = ExecutionRequest.fromUserMessage(
        sessionKey: session.sessionKey,
        prompt: 'hello',
      );

      await session.applyRuntimeTranscriptEvent(
        RuntimeTranscriptEvent(
          kind: RuntimeTranscriptEventKind.assistantMessageStarted,
          requestId: request.id,
          sessionKey: session.sessionKey,
          sequence: 0,
          occurredAt: DateTime(2026, 4, 12, 10),
          messageId: '${request.id}-assistant-final',
        ),
      );
      await session.appendExecutionResult(
        request,
        ExecutionResult(
          requestId: request.id,
          sessionKey: session.sessionKey,
          source: request.source,
          mode: request.mode,
          terminalStatus: ExecutionLifecycleStatus.completed,
          admissionOutcome: ExecutionAdmissionOutcome.admitted,
          policyReason: 'completed',
          visibility: request.visibility,
          loopResult: const AgentLoopResult(
            sessionResult: SessionResult.completed,
            text: '',
            reason: 'completed',
          ),
        ),
      );

      final assistantMessages = session.messages
          .where((message) => message.sender == ChatMessageSender.assistant)
          .toList();
      expect(assistantMessages, hasLength(1));
      expect(
        assistantMessages.single.text,
        'LiteRT completed the turn but returned no visible text.',
      );
      expect(assistantMessages.single.isStreaming, isFalse);
    },
  );

  test(
    'system assistant injection appends assistant output without user turn',
    () async {
      final executor = _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      );
      final session = AgentLoopChatSession(taskExecutor: executor);

      session.injectSystemAssistantEntry('Trigger output ready.');

      expect(session.messages.last.sender, ChatMessageSender.assistant);
      expect(session.messages.last.text, 'Trigger output ready.');
      expect(
        session.messages.where(
          (message) => message.sender == ChatMessageSender.user,
        ),
        isEmpty,
      );
      expect(executor.requests, isEmpty);
    },
  );

  test('chat execution sink appends directly without recursive send', () async {
    final executor = _RecordingTaskExecutor(
      result: const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'done',
        reason: 'completed',
      ),
    );
    final session = AgentLoopChatSession(taskExecutor: executor);

    await session.appendExecutionResult(
      ExecutionRequest.fromTrigger(
        sessionKey: 'system_main',
        prompt: 'Run background task.',
        source: ExecutionSource.trigger,
      ),
      ExecutionResult(
        requestId: 'background',
        sessionKey: 'system_main',
        source: ExecutionSource.trigger,
        mode: ExecutionLifecycleMode.triggeredRequest,
        terminalStatus: ExecutionLifecycleStatus.completed,
        admissionOutcome: ExecutionAdmissionOutcome.admitted,
        policyReason: 'completed',
        visibility: ExecutionVisibility.chat,
        loopResult: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'Background finished.',
          reason: 'completed',
        ),
      ),
    );

    expect(session.messages.last.text, isNot('Background finished.'));
    expect(
      session.messages.where(
        (message) => message.sender == ChatMessageSender.user,
      ),
      isEmpty,
    );
    expect(executor.requests, isEmpty);
  });

  test('normalized tool result renders in activity details', () async {
    final session = await _runSessionWithResult(
      const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'done',
        reason: 'completed',
        toolResults: <ToolResult>[
          ToolResult(
            toolId: 'battery_info',
            callId: 'call-1',
            status: ToolResultStatus.success,
            summary: 'Battery at 42%.',
          ),
        ],
      ),
    );

    expect(
      session.activities.single.details,
      contains('Result: success: Battery at 42%.'),
    );
  });

  test('runtime transcript events stream into one assistant bubble', () async {
    final executor = _RecordingTaskExecutor(
      result: const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'Hello reef.',
        reason: 'completed',
      ),
    );
    final session = AgentLoopChatSession(taskExecutor: executor);

    await session.applyRuntimeTranscriptEvent(
      RuntimeTranscriptEvent(
        kind: RuntimeTranscriptEventKind.assistantMessageStarted,
        requestId: 'request-1',
        sessionKey: session.sessionKey,
        sequence: 0,
        occurredAt: DateTime(2026, 4, 12, 10),
        messageId: 'assistant-1',
      ),
    );
    await session.applyRuntimeTranscriptEvent(
      RuntimeTranscriptEvent(
        kind: RuntimeTranscriptEventKind.assistantMessageDelta,
        requestId: 'request-1',
        sessionKey: session.sessionKey,
        sequence: 1,
        occurredAt: DateTime(2026, 4, 12, 10),
        messageId: 'assistant-1',
        deltaText: 'Hello',
      ),
    );
    await session.applyRuntimeTranscriptEvent(
      RuntimeTranscriptEvent(
        kind: RuntimeTranscriptEventKind.assistantMessageDelta,
        requestId: 'request-1',
        sessionKey: session.sessionKey,
        sequence: 2,
        occurredAt: DateTime(2026, 4, 12, 10),
        messageId: 'assistant-1',
        deltaText: ' reef.',
      ),
    );
    await session.applyRuntimeTranscriptEvent(
      RuntimeTranscriptEvent(
        kind: RuntimeTranscriptEventKind.assistantMessageFinalized,
        requestId: 'request-1',
        sessionKey: session.sessionKey,
        sequence: 3,
        occurredAt: DateTime(2026, 4, 12, 10),
        messageId: 'assistant-1',
        finalText: 'Hello reef.',
      ),
    );

    final assistantMessages = session.messages
        .where((message) => message.id == 'assistant-1')
        .toList();
    expect(assistantMessages, hasLength(1));
    expect(assistantMessages.single.text, 'Hello reef.');
    expect(assistantMessages.single.isStreaming, isFalse);
  });

  test('runtime tool events drive structured activity state', () async {
    final executor = _RecordingTaskExecutor(
      result: const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'done',
        reason: 'completed',
      ),
    );
    final session = AgentLoopChatSession(taskExecutor: executor);

    await session.applyRuntimeTranscriptEvent(
      RuntimeTranscriptEvent(
        kind: RuntimeTranscriptEventKind.toolStepStarted,
        requestId: 'request-2',
        sessionKey: session.sessionKey,
        sequence: 0,
        occurredAt: DateTime(2026, 4, 12, 10),
        stepId: 'step-1',
        toolCallId: 'call-1',
        toolId: 'battery_info',
        status: 'running',
        summary: 'Battery lookup started.',
      ),
    );
    await session.applyRuntimeTranscriptEvent(
      RuntimeTranscriptEvent(
        kind: RuntimeTranscriptEventKind.toolStepFinished,
        requestId: 'request-2',
        sessionKey: session.sessionKey,
        sequence: 1,
        occurredAt: DateTime(2026, 4, 12, 10),
        stepId: 'step-1',
        toolCallId: 'call-1',
        toolId: 'battery_info',
        status: 'success',
        summary: 'Battery at 42%.',
        toolResult: const ToolResult.success(
          'Battery at 42%.',
          toolId: 'battery_info',
          callId: 'call-1',
        ),
      ),
    );

    expect(session.activities.single.id, 'step-1');
    expect(session.activities.single.label, 'battery_info');
    expect(session.activities.single.status, SubAgentActivityStatus.completed);
    expect(
      session.activities.single.details,
      contains('Result: success: Battery at 42%.'),
    );
  });

  test(
    'visible trigger execution finalizes through unified transcript path',
    () async {
      final executor = _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      );
      final session = AgentLoopChatSession(taskExecutor: executor);

      await session.appendExecutionResult(
        ExecutionRequest.fromTrigger(
          sessionKey: session.sessionKey,
          prompt: 'Scheduled check',
          source: ExecutionSource.schedule,
          visibility: ExecutionVisibility.chatAndBackground,
        ),
        ExecutionResult(
          requestId: 'schedule-1',
          sessionKey: session.sessionKey,
          source: ExecutionSource.schedule,
          mode: ExecutionLifecycleMode.triggeredRequest,
          terminalStatus: ExecutionLifecycleStatus.completed,
          admissionOutcome: ExecutionAdmissionOutcome.admitted,
          policyReason: 'completed',
          visibility: ExecutionVisibility.chatAndBackground,
          loopResult: const AgentLoopResult(
            sessionResult: SessionResult.completed,
            text: 'Scheduled check finished.',
            reason: 'completed',
          ),
        ),
      );

      expect(session.messages.last.sender, ChatMessageSender.assistant);
      expect(session.messages.last.text, 'Scheduled check finished.');
      expect(
        session.messages.where(
          (message) => message.sender == ChatMessageSender.user,
        ),
        isEmpty,
      );
    },
  );

  test('terminal status emits after transcript persistence succeeds', () async {
    final executor = _RecordingTaskExecutor(
      result: const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'done',
        reason: 'completed',
      ),
    );
    final persistence = _RecordingPersistencePort();
    final session = AgentLoopChatSession(taskExecutor: executor);
    session.attachTranscriptPersistencePort(persistence);
    var completedObservedAfterPersistence = false;
    session.addListener(() {
      if (session.status == ChatSessionStatus.completed) {
        completedObservedAfterPersistence = persistence.persistedMessages.any(
          (message) => message.text == 'Persisted final.',
        );
      }
    });

    await session.appendExecutionResult(
      ExecutionRequest.fromTrigger(
        sessionKey: session.sessionKey,
        prompt: 'visible work',
        source: ExecutionSource.trigger,
        visibility: ExecutionVisibility.chat,
      ),
      ExecutionResult(
        requestId: 'persist-1',
        sessionKey: session.sessionKey,
        source: ExecutionSource.trigger,
        mode: ExecutionLifecycleMode.triggeredRequest,
        terminalStatus: ExecutionLifecycleStatus.completed,
        admissionOutcome: ExecutionAdmissionOutcome.admitted,
        policyReason: 'completed',
        visibility: ExecutionVisibility.chat,
        loopResult: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'Persisted final.',
          reason: 'completed',
        ),
      ),
    );

    expect(completedObservedAfterPersistence, isTrue);
  });

  test(
    'persistence failure emits save-failed status instead of completed',
    () async {
      final executor = _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      );
      final session = AgentLoopChatSession(taskExecutor: executor);
      session.attachTranscriptPersistencePort(
        _RecordingPersistencePort(fail: true),
      );

      await session.appendExecutionResult(
        ExecutionRequest.fromTrigger(
          sessionKey: session.sessionKey,
          prompt: 'visible work',
          source: ExecutionSource.trigger,
          visibility: ExecutionVisibility.chat,
        ),
        ExecutionResult(
          requestId: 'persist-fail-1',
          sessionKey: session.sessionKey,
          source: ExecutionSource.trigger,
          mode: ExecutionLifecycleMode.triggeredRequest,
          terminalStatus: ExecutionLifecycleStatus.completed,
          admissionOutcome: ExecutionAdmissionOutcome.admitted,
          policyReason: 'completed',
          visibility: ExecutionVisibility.chat,
          loopResult: const AgentLoopResult(
            sessionResult: SessionResult.completed,
            text: 'Unsaved final.',
            reason: 'completed',
          ),
        ),
      );

      expect(session.status, ChatSessionStatus.persistenceFailed);
      expect(session.messages.last.sender, ChatMessageSender.system);
      expect(session.messages.last.text, contains('could not save'));
    },
  );
}

Future<AgentLoopChatSession> _runSessionWithResult(
  AgentLoopResult result,
) async {
  final executor = _RecordingTaskExecutor(result: result);
  final session = AgentLoopChatSession(taskExecutor: executor);
  executor.chatSink = session;
  await session.sendMessage('hello');
  return session;
}

class _RecordingTaskExecutor implements AgentTaskExecutor {
  _RecordingTaskExecutor({required this.result});

  final AgentLoopResult result;
  final List<ExecutionRequest> requests = <ExecutionRequest>[];
  ChatExecutionSink? chatSink;

  @override
  Future<ExecutionResult> execute(ExecutionRequest request) async {
    requests.add(request);
    final executionResult = ExecutionResult(
      requestId: request.id,
      sessionKey: request.sessionKey,
      source: request.source,
      mode: request.mode,
      terminalStatus: ExecutionLifecycleStatus.completed,
      admissionOutcome: ExecutionAdmissionOutcome.admitted,
      policyReason: result.reason ?? 'completed',
      visibility: request.visibility,
      loopResult: result,
    );
    await chatSink?.appendExecutionResult(request, executionResult);
    return executionResult;
  }

  @override
  Future<AgentTaskExecutionResult> executeTask(AgentTaskRequest request) async {
    final loopResult = await execute(request.toExecutionRequest());
    return AgentTaskExecutionResult.fromLoopResult(
      loopResult.toAgentLoopResult(),
    );
  }
}

class _RecordingPersistencePort implements ChatTranscriptPersistencePort {
  _RecordingPersistencePort({this.fail = false});

  final bool fail;
  List<ChatTranscriptMessage> persistedMessages =
      const <ChatTranscriptMessage>[];

  @override
  Future<ChatTranscriptPersistenceResult> persistTranscriptBeforeTerminal(
    ChatTranscriptPersistenceRequest request,
  ) async {
    if (fail) {
      return const ChatTranscriptPersistenceResult.failure(
        errorCode: 'test_failure',
        errorMessage: 'test failure',
      );
    }
    persistedMessages = request.messages;
    return ChatTranscriptPersistenceResult.success(
      persistedAt: DateTime(2026, 4, 12, 10),
    );
  }
}
