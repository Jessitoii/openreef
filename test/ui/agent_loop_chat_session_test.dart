import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/mailbox.dart';
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
      config: const MailboxDispatchConfig(
        approvalTimeout: Duration(milliseconds: 10),
      ),
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
      expect(
        completedSession.activities.single.status,
        SubAgentActivityStatus.completed,
      );

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
      expect(
        frozenSession.activities.single.status,
        SubAgentActivityStatus.failed,
      );

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
      expect(
        failedSession.activities.single.status,
        SubAgentActivityStatus.failed,
      );
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

    expect(session.messages.last.text, 'Background finished.');
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
      contains('Tool battery_info [call-1] success: Battery at 42%.'),
    );
  });
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
