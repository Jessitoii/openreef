import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_execution_event.dart';
import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/runtime_transcript_event.dart';
import 'package:openreef/models/model_capabilities.dart';
import 'package:openreef/ui/agent_loop_chat_session.dart';
import 'package:openreef/ui/chat/attachment_runtime_support.dart';
import 'package:openreef/ui/chat/composer_capability_resolver.dart';
import 'package:openreef/ui/chat/composer_models.dart';
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

  test('text approval resolves pending tool call without new turn', () async {
    final controller = MainAgentApprovalController();
    final executor = _RecordingTaskExecutor(
      result: const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'should not run',
        reason: 'completed',
      ),
    );
    final session = AgentLoopChatSession(
      taskExecutor: executor,
      approvalController: controller,
    );
    final approvalFuture = controller.confirmToolCall(
      const ToolCall(
        id: 'sms-approval',
        toolId: 'sms_send',
        arguments: <String, Object?>{'number': '+15550100', 'message': 'hello'},
      ),
    );

    await session.sendMessage('Yes send it now');

    await expectLater(approvalFuture, completion(isTrue));
    expect(controller.pendingApproval, isNull);
    expect(executor.requests, isEmpty);
    expect(session.messages.last.sender, ChatMessageSender.user);
    expect(session.messages.last.text, 'Yes send it now');
  });

  test('text rejection cancels pending tool call without new turn', () async {
    final controller = MainAgentApprovalController();
    final executor = _RecordingTaskExecutor(
      result: const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'should not run',
        reason: 'completed',
      ),
    );
    final session = AgentLoopChatSession(
      taskExecutor: executor,
      approvalController: controller,
    );
    final approvalFuture = controller.confirmToolCall(
      const ToolCall(id: 'sms-approval', toolId: 'sms_send'),
    );

    await session.sendMessage('cancel');

    await expectLater(approvalFuture, completion(isFalse));
    expect(controller.pendingApproval, isNull);
    expect(executor.requests, isEmpty);
  });

  test('expired text approval rejects pending tool without new turn', () async {
    var now = DateTime(2026, 4, 12, 10);
    final controller = MainAgentApprovalController(now: () => now);
    final executor = _RecordingTaskExecutor(
      result: const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'should not run',
        reason: 'completed',
      ),
    );
    final session = AgentLoopChatSession(
      taskExecutor: executor,
      approvalController: controller,
    );
    final approvalFuture = controller.confirmToolCall(
      const ToolCall(id: 'sms-expired', toolId: 'sms_send'),
    );

    now = now
        .add(MainAgentApprovalController.approvalTtl)
        .add(const Duration(seconds: 1));
    await session.sendMessage('yes');

    await expectLater(approvalFuture, completion(isFalse));
    expect(controller.pendingApproval, isNull);
    expect(executor.requests, isEmpty);
  });

  test('one approval text resolves only the active queued approval', () async {
    final controller = MainAgentApprovalController();
    final executor = _RecordingTaskExecutor(
      result: const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'should not run',
        reason: 'completed',
      ),
    );
    final session = AgentLoopChatSession(
      taskExecutor: executor,
      approvalController: controller,
    );
    final first = controller.confirmToolCall(
      const ToolCall(id: 'sms-1', toolId: 'sms_send'),
    );
    var secondCompleted = false;
    final second = controller
        .confirmToolCall(const ToolCall(id: 'sms-2', toolId: 'sms_send'))
        .then((value) {
          secondCompleted = true;
          return value;
        });

    await session.sendMessage('yes');

    await expectLater(first, completion(isTrue));
    await Future<void>.delayed(Duration.zero);
    expect(secondCompleted, isFalse);
    expect(controller.pendingApproval?.toolCallId, 'sms-2');

    await session.sendMessage('cancel');
    await expectLater(second, completion(isFalse));
    expect(executor.requests, isEmpty);
  });

  test('legacy communication approval ids are presented canonically', () async {
    final controller = MainAgentApprovalController();

    final approvalFuture = controller.confirmToolCall(
      const ToolCall(id: 'old-sms', toolId: 'communication_sms_send'),
    );

    expect(controller.pendingApproval?.toolId, 'sms_send');
    controller.approvePendingApproval();
    await expectLater(approvalFuture, completion(isTrue));
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

  test('raw tool marker result is not shown or persisted', () async {
    const marker = '<|tool_call>call:battery_info{}<tool_call|>';
    final executor = _RecordingTaskExecutor(
      result: const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'unused',
        reason: 'completed',
      ),
    );
    final persistence = _RecordingPersistencePort();
    final session = AgentLoopChatSession(taskExecutor: executor);
    session.attachTranscriptPersistencePort(persistence);

    await session.appendExecutionResult(
      ExecutionRequest.fromTrigger(
        sessionKey: session.sessionKey,
        prompt: 'battery',
        source: ExecutionSource.trigger,
        visibility: ExecutionVisibility.chat,
      ),
      ExecutionResult(
        requestId: 'raw-marker-1',
        sessionKey: session.sessionKey,
        source: ExecutionSource.trigger,
        mode: ExecutionLifecycleMode.triggeredRequest,
        terminalStatus: ExecutionLifecycleStatus.completed,
        admissionOutcome: ExecutionAdmissionOutcome.admitted,
        policyReason: 'completed',
        visibility: ExecutionVisibility.chat,
        loopResult: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: marker,
          reason: 'completed',
        ),
      ),
    );

    expect(
      session.messages.where((message) => message.text.contains(marker)),
      isEmpty,
    );
    expect(
      persistence.persistedMessages.where(
        (message) => message.text.contains(marker),
      ),
      isEmpty,
    );
  });

  test('raw tool context block is not shown or persisted', () async {
    const rawToolBlock =
        '[TOOL] toolId: bluetooth_toggle\n'
        'callId: tool_call_marker\n'
        'status: validation_error\n'
        'summary: missing_argument:enabled\n'
        'reason: invalid_arguments';
    final executor = _RecordingTaskExecutor(
      result: const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'unused',
        reason: 'completed',
      ),
    );
    final persistence = _RecordingPersistencePort();
    final session = AgentLoopChatSession(taskExecutor: executor);
    session.attachTranscriptPersistencePort(persistence);

    await session.appendExecutionResult(
      ExecutionRequest.fromTrigger(
        sessionKey: session.sessionKey,
        prompt: 'set bluetooth on',
        source: ExecutionSource.trigger,
        visibility: ExecutionVisibility.chat,
      ),
      ExecutionResult(
        requestId: 'raw-tool-block-1',
        sessionKey: session.sessionKey,
        source: ExecutionSource.trigger,
        mode: ExecutionLifecycleMode.triggeredRequest,
        terminalStatus: ExecutionLifecycleStatus.completed,
        admissionOutcome: ExecutionAdmissionOutcome.admitted,
        policyReason: 'completed',
        visibility: ExecutionVisibility.chat,
        loopResult: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: rawToolBlock,
          reason: 'completed',
        ),
      ),
    );

    expect(
      session.messages.where(
        (message) => message.text.contains('toolId: bluetooth_toggle'),
      ),
      isEmpty,
    );
    expect(
      persistence.persistedMessages.where(
        (message) => message.text.contains('missing_argument:enabled'),
      ),
      isEmpty,
    );
  });

  test('unstable malformed tool result is not shown or persisted', () async {
    const fallbackText = 'Fake successful fallback text.';
    final executor = _RecordingTaskExecutor(
      result: const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: fallbackText,
        reason: 'completed',
      ),
    );
    final persistence = _RecordingPersistencePort();
    final session = AgentLoopChatSession(taskExecutor: executor);
    session.attachTranscriptPersistencePort(persistence);

    await session.appendExecutionResult(
      ExecutionRequest.fromTrigger(
        sessionKey: session.sessionKey,
        prompt: 'battery',
        source: ExecutionSource.trigger,
        visibility: ExecutionVisibility.chat,
      ),
      ExecutionResult(
        requestId: 'malformed-tool-1',
        sessionKey: session.sessionKey,
        source: ExecutionSource.trigger,
        mode: ExecutionLifecycleMode.triggeredRequest,
        terminalStatus: ExecutionLifecycleStatus.completed,
        admissionOutcome: ExecutionAdmissionOutcome.admitted,
        policyReason: 'completed',
        visibility: ExecutionVisibility.chat,
        loopResult: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: fallbackText,
          reason: 'completed',
          toolResults: <ToolResult>[
            ToolResult.failure(
              'malformed_tool_call',
              toolId: 'agent_protocol',
              callId: 'parser_failure_1',
              status: ToolResultStatus.validationError,
              metadata: <String, Object?>{
                'reason': 'malformed_tool_call',
                'visibleSuppressed': true,
              },
            ),
          ],
        ),
      ),
    );

    expect(
      session.messages.where((message) => message.text.contains(fallbackText)),
      isEmpty,
    );
    expect(
      persistence.persistedMessages.where(
        (message) => message.text.contains(fallbackText),
      ),
      isEmpty,
    );
  });

  test(
    'sendComposerSubmission delegates text-only submissions to sendMessage',
    () async {
      final executor = _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      );
      final session = AgentLoopChatSession(taskExecutor: executor);

      await session.sendComposerSubmission(
        const ComposerSubmission(text: 'hello'),
      );

      expect(executor.requests, hasLength(1));
      expect(executor.requests.single.prompt, 'hello');
      expect(
        session.messages.where(
          (message) =>
              message.sender == ChatMessageSender.user &&
              message.text == 'hello',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'unsupported attachment-only submissions do not reach execution',
    () async {
      final executor = _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      );
      final session = AgentLoopChatSession(taskExecutor: executor);

      await session.sendComposerSubmission(
        const ComposerSubmission(
          text: '',
          attachments: <ComposerAttachmentDescriptor>[
            ComposerAttachmentDescriptor(
              id: 'image-1',
              type: ComposerAttachmentType.image,
              displayName: 'reef-photo.jpg',
            ),
          ],
        ),
      );

      expect(executor.requests, isEmpty);
      expect(session.messages.last.sender, ChatMessageSender.system);
      expect(
        session.messages.last.text,
        contains('unavailable for the selected model and current runtime'),
      );
    },
  );

  test(
    'unsupported attachments with text are blocked before execution',
    () async {
      final executor = _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      );
      final session = AgentLoopChatSession(taskExecutor: executor);

      await session.sendComposerSubmission(
        const ComposerSubmission(
          text: 'hello',
          attachments: <ComposerAttachmentDescriptor>[
            ComposerAttachmentDescriptor(
              id: 'doc-1',
              type: ComposerAttachmentType.document,
              displayName: 'notes.pdf',
            ),
          ],
        ),
      );

      expect(executor.requests, isEmpty);
      expect(session.messages.last.sender, ChatMessageSender.system);
      expect(
        session.messages.last.text,
        contains('unavailable for the selected model and current runtime'),
      );
    },
  );

  test('supported attachment reaches execution as structured data', () async {
    final executor = _RecordingTaskExecutor(
      result: const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'done',
        reason: 'completed',
      ),
    );
    final session = AgentLoopChatSession(
      taskExecutor: executor,
      composerCapabilityResolver: _composerResolver(
        modelCapabilities: const ModelInputCapabilities(
          supportsImageInput: true,
        ),
        runtimeSupport: const _RuntimeSupport(image: true),
      ),
    );

    await session.sendComposerSubmission(
      const ComposerSubmission(
        text: 'what is in this image?',
        attachments: <ComposerAttachmentDescriptor>[
          ComposerAttachmentDescriptor(
            id: 'image-1',
            type: ComposerAttachmentType.image,
            displayName: 'reef-photo.jpg',
            sizeBytes: 2048,
            mimeType: 'image/jpeg',
            sourceUri: 'file:///tmp/reef-photo.jpg',
          ),
        ],
      ),
    );

    expect(executor.requests, hasLength(1));
    expect(executor.requests.single.prompt, 'what is in this image?');
    expect(executor.requests.single.attachments, hasLength(1));
    expect(executor.requests.single.attachments.single.id, 'image-1');
    expect(
      executor.requests.single.attachments.single.type,
      ExecutionAttachmentType.image,
    );
    expect(
      executor.requests.single.metadata?.containsKey('attachments') ?? false,
      isFalse,
    );
  });

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

    expect(session.messages, isEmpty);
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

  test('runtime protocol deltas are never shown or persisted', () async {
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

    await session.applyRuntimeTranscriptEvent(
      RuntimeTranscriptEvent(
        kind: RuntimeTranscriptEventKind.assistantMessageStarted,
        requestId: 'request-tool-delta',
        sessionKey: session.sessionKey,
        sequence: 0,
        occurredAt: DateTime(2026, 4, 12, 10),
        messageId: 'assistant-tool-delta',
      ),
    );
    await session.applyRuntimeTranscriptEvent(
      RuntimeTranscriptEvent(
        kind: RuntimeTranscriptEventKind.assistantMessageDelta,
        requestId: 'request-tool-delta',
        sessionKey: session.sessionKey,
        sequence: 1,
        occurredAt: DateTime(2026, 4, 12, 10),
        messageId: 'assistant-tool-delta',
        deltaText:
            '[TOOL] toolId: bluetooth_toggle\ncallId: tool_call_marker\n'
            'status: validation_error\nsummary: missing_argument:enabled',
      ),
    );
    await session.applyRuntimeTranscriptEvent(
      RuntimeTranscriptEvent(
        kind: RuntimeTranscriptEventKind.assistantMessageFinalized,
        requestId: 'request-tool-delta',
        sessionKey: session.sessionKey,
        sequence: 2,
        occurredAt: DateTime(2026, 4, 12, 10),
        messageId: 'assistant-tool-delta',
        finalText: 'Please say whether Bluetooth should be on or off.',
      ),
    );

    expect(
      session.messages.where((message) => message.text.contains('[TOOL]')),
      isEmpty,
    );
    expect(
      session.messages.where((message) => message.text.contains('toolId:')),
      isEmpty,
    );
    expect(
      persistence.persistedMessages.where(
        (message) => message.text.contains('missing_argument:enabled'),
      ),
      isEmpty,
    );
    expect(
      persistence.persistedMessages.last.text,
      'Please say whether Bluetooth should be on or off.',
    );
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

  test('TokenDeltaEvent updates assistant streaming bubble state', () async {
    final session = AgentLoopChatSession(
      taskExecutor: _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      ),
    );

    await session.applyAgentExecutionEvent(
      TokenDeltaEvent(
        runId: 'run-1',
        sessionId: session.sessionKey,
        requestId: 'request-events',
        sequence: 0,
        occurredAt: DateTime.utc(2026, 4, 12, 10),
        messageId: 'assistant-events',
        delta: 'Hello',
      ),
    );
    await session.applyAgentExecutionEvent(
      TokenDeltaEvent(
        runId: 'run-1',
        sessionId: session.sessionKey,
        requestId: 'request-events',
        sequence: 1,
        occurredAt: DateTime.utc(2026, 4, 12, 10),
        messageId: 'assistant-events',
        delta: ' reef',
      ),
    );

    expect(session.messages.single.id, 'assistant-events');
    expect(session.messages.single.text, 'Hello reef');
    expect(session.messages.single.isStreaming, isTrue);
    expect(session.status, ChatSessionStatus.streaming);
  });

  test(
    'final assistant result transitions typed stream into normal bubble',
    () async {
      final session = AgentLoopChatSession(
        taskExecutor: _RecordingTaskExecutor(
          result: const AgentLoopResult(
            sessionResult: SessionResult.completed,
            text: 'Hello reef.',
            reason: 'completed',
          ),
        ),
      );
      final request = ExecutionRequest.fromUserMessage(
        sessionKey: session.sessionKey,
        prompt: 'hello',
      );

      await session.applyAgentExecutionEvent(
        TokenDeltaEvent(
          runId: 'run-1',
          sessionId: session.sessionKey,
          requestId: request.id,
          sequence: 0,
          occurredAt: DateTime.utc(2026, 4, 12, 10),
          messageId: 'assistant-stream',
          delta: 'Hello',
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
            text: 'Hello reef.',
            reason: 'completed',
          ),
        ),
      );

      expect(session.messages, hasLength(1));
      expect(session.messages.single.id, 'assistant-stream');
      expect(session.messages.single.text, 'Hello reef.');
      expect(session.messages.single.isStreaming, isFalse);
      expect(session.messages.single.sender, ChatMessageSender.assistant);
    },
  );

  test('ToolCallStartedEvent shows running tool card', () async {
    final session = AgentLoopChatSession(
      taskExecutor: _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      ),
    );

    await session.applyAgentExecutionEvent(
      ToolCallStartedEvent(
        runId: 'run-1',
        sessionId: session.sessionKey,
        requestId: 'request-tool',
        sequence: 0,
        occurredAt: DateTime.utc(2026, 4, 12, 10),
        toolId: 'battery_info',
        callId: 'call-1',
        displayLabel: 'Battery Info',
        safeArgsPreview: const <ToolArgumentPreview>[
          ToolArgumentPreview(name: 'scope', displayValue: 'current'),
        ],
      ),
    );

    final trace = session.executionTrace!;
    expect(trace.status, ExecutionTraceStatus.running);
    expect(trace.steps.single.kind, ExecutionStepKind.tool);
    expect(trace.steps.single.status, ExecutionStepStatus.running);
    expect(trace.steps.single.title, 'Battery Info');
    expect(trace.steps.single.details.single.value, 'current');
  });

  test('ToolCallResultEvent transitions card to done', () async {
    final session = AgentLoopChatSession(
      taskExecutor: _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      ),
    );

    await session.applyAgentExecutionEvent(
      ToolCallStartedEvent(
        runId: 'run-1',
        sessionId: session.sessionKey,
        requestId: 'request-tool',
        sequence: 0,
        occurredAt: DateTime.utc(2026, 4, 12, 10),
        toolId: 'battery_info',
        callId: 'call-1',
        displayLabel: 'Battery Info',
        safeArgsPreview: const <ToolArgumentPreview>[],
      ),
    );
    await session.applyAgentExecutionEvent(
      ToolCallResultEvent(
        runId: 'run-1',
        sessionId: session.sessionKey,
        requestId: 'request-tool',
        sequence: 1,
        occurredAt: DateTime.utc(2026, 4, 12, 10),
        toolId: 'battery_info',
        callId: 'call-1',
        displayLabel: 'Battery Info',
        status: 'success',
        summary: 'Battery at 42%.',
      ),
    );

    expect(
      session.executionTrace!.steps.single.status,
      ExecutionStepStatus.completed,
    );
    expect(session.executionTrace!.steps.single.summary, 'Battery at 42%.');
  });

  test('ToolCallFailedEvent shows calm failure state', () async {
    final session = AgentLoopChatSession(
      taskExecutor: _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      ),
    );

    await session.applyAgentExecutionEvent(
      ToolCallFailedEvent(
        runId: 'run-1',
        sessionId: session.sessionKey,
        requestId: 'request-tool',
        sequence: 0,
        occurredAt: DateTime.utc(2026, 4, 12, 10),
        toolId: 'battery_info',
        callId: 'call-1',
        displayLabel: 'Battery Info',
        status: 'failed',
        summary: 'Battery data was unavailable.',
      ),
    );

    expect(
      session.executionTrace!.steps.single.status,
      ExecutionStepStatus.failed,
    );
    expect(
      session.executionTrace!.steps.single.summary,
      'Battery data was unavailable.',
    );
  });

  test(
    'ApprovalRequiredEvent renders approval card without raw args',
    () async {
      final session = AgentLoopChatSession(
        taskExecutor: _RecordingTaskExecutor(
          result: const AgentLoopResult(
            sessionResult: SessionResult.completed,
            text: 'done',
            reason: 'completed',
          ),
        ),
      );

      await session.applyAgentExecutionEvent(
        ApprovalRequiredEvent(
          runId: 'run-1',
          sessionId: session.sessionKey,
          requestId: 'request-approval',
          sequence: 0,
          occurredAt: DateTime.utc(2026, 4, 12, 10),
          toolId: 'sms_send',
          callId: 'call-approval',
          displayLabel: 'Sms Send',
          safeArgsPreview: const <ToolArgumentPreview>[
            ToolArgumentPreview(name: 'message', displayValue: '11 chars'),
            ToolArgumentPreview(name: 'token', displayValue: 'redacted'),
          ],
        ),
      );

      final step = session.executionTrace!.steps.single;
      expect(step.kind, ExecutionStepKind.approval);
      expect(step.status, ExecutionStepStatus.approvalRequired);
      expect(step.details.map((detail) => detail.value), contains('redacted'));
      expect(
        step.details.map((detail) => detail.value),
        isNot(contains('super secret raw message')),
      );
    },
  );

  test('RunCancelledEvent renders interrupted state if available', () async {
    final session = AgentLoopChatSession(
      taskExecutor: _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      ),
    );

    await session.applyAgentExecutionEvent(
      ToolCallStartedEvent(
        runId: 'run-1',
        sessionId: session.sessionKey,
        requestId: 'request-cancel',
        sequence: 0,
        occurredAt: DateTime.utc(2026, 4, 12, 10),
        toolId: 'battery_info',
        callId: 'call-1',
        displayLabel: 'Battery Info',
        safeArgsPreview: const <ToolArgumentPreview>[],
      ),
    );
    await session.applyAgentExecutionEvent(
      RunCancelledEvent(
        runId: 'run-1',
        sessionId: session.sessionKey,
        requestId: 'request-cancel',
        sequence: 1,
        occurredAt: DateTime.utc(2026, 4, 12, 10),
        reason: 'user_requested',
      ),
    );

    expect(session.executionTrace!.status, ExecutionTraceStatus.interrupted);
    expect(
      session.executionTrace!.steps.single.status,
      ExecutionStepStatus.failed,
    );
    expect(session.status, ChatSessionStatus.cancelled);
  });

  test('late tool result after RunCancelledEvent is ignored', () async {
    final session = AgentLoopChatSession(
      taskExecutor: _RecordingTaskExecutor(
        result: const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      ),
    );

    await session.applyAgentExecutionEvent(
      ToolCallStartedEvent(
        runId: 'run-1',
        sessionId: session.sessionKey,
        requestId: 'request-cancel',
        sequence: 0,
        occurredAt: DateTime.utc(2026, 4, 12, 10),
        toolId: 'battery_info',
        callId: 'call-1',
        displayLabel: 'Battery Info',
        safeArgsPreview: const <ToolArgumentPreview>[],
      ),
    );
    await session.applyAgentExecutionEvent(
      RunCancelledEvent(
        runId: 'run-1',
        sessionId: session.sessionKey,
        requestId: 'request-cancel',
        sequence: 1,
        occurredAt: DateTime.utc(2026, 4, 12, 10),
        reason: 'user_requested',
      ),
    );
    await session.applyAgentExecutionEvent(
      ToolCallResultEvent(
        runId: 'run-1',
        sessionId: session.sessionKey,
        requestId: 'request-cancel',
        sequence: 2,
        occurredAt: DateTime.utc(2026, 4, 12, 10),
        toolId: 'battery_info',
        callId: 'call-1',
        displayLabel: 'Battery Info',
        status: 'success',
        summary: 'Battery at 42%.',
      ),
    );

    expect(session.executionTrace!.status, ExecutionTraceStatus.interrupted);
    expect(
      session.executionTrace!.steps.single.status,
      ExecutionStepStatus.failed,
    );
    expect(
      session.executionTrace!.steps.single.summary,
      'Interrupted before completion',
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

  test('cancelled session accepts a new user request', () async {
    final executor = _CancelableTaskExecutor();
    final session = AgentLoopChatSession(taskExecutor: executor);
    executor.chatSink = session;

    final firstSend = session.sendMessage('first');
    await executor.waitForRequestCount(1);

    expect(await session.cancelActiveRun(), isTrue);
    executor.completeNext(
      const AgentLoopResult(
        sessionResult: SessionResult.cancelled,
        text: '',
        reason: 'user_requested',
      ),
    );
    await firstSend;

    expect(session.status, ChatSessionStatus.cancelled);
    final secondSend = session.sendMessage('second');
    await executor.waitForRequestCount(2);
    executor.completeNext(
      const AgentLoopResult(
        sessionResult: SessionResult.completed,
        text: 'second complete',
        reason: 'completed',
      ),
    );
    await secondSend;

    expect(session.status, ChatSessionStatus.completed);
    expect(executor.cancelCalls, 1);
    expect(executor.requests.map((request) => request.prompt), <String>[
      'first',
      'second',
    ]);
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

class _CancelableTaskExecutor implements AgentTaskExecutor {
  final List<ExecutionRequest> requests = <ExecutionRequest>[];
  final Queue<Completer<AgentLoopResult>> _pendingResults =
      Queue<Completer<AgentLoopResult>>();
  ChatExecutionSink? chatSink;
  var cancelCalls = 0;

  Future<void> waitForRequestCount(int count) async {
    while (requests.length < count) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void completeNext(AgentLoopResult result) {
    _pendingResults.removeFirst().complete(result);
  }

  @override
  Future<bool> cancelActiveRun({
    String? runId,
    String? sessionKey,
    RunCancellationReason reason = RunCancellationReason.userRequested,
  }) async {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<ExecutionResult> execute(ExecutionRequest request) async {
    requests.add(request);
    final completer = Completer<AgentLoopResult>();
    _pendingResults.add(completer);
    final result = await completer.future;
    final executionResult = ExecutionResult(
      requestId: request.id,
      sessionKey: request.sessionKey,
      source: request.source,
      mode: request.mode,
      terminalStatus: switch (result.sessionResult) {
        SessionResult.cancelled => ExecutionLifecycleStatus.cancelled,
        SessionResult.completed => ExecutionLifecycleStatus.completed,
        _ => ExecutionLifecycleStatus.failed,
      },
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

ComposerCapabilityResolver _composerResolver({
  required ModelInputCapabilities modelCapabilities,
  required AttachmentRuntimeSupport runtimeSupport,
}) {
  return ComposerCapabilityResolver(
    modelCapabilityProvider: StaticActiveModelCapabilityProvider(
      modelCapabilities,
    ),
    runtimeSupport: runtimeSupport,
  );
}

class _RuntimeSupport implements AttachmentRuntimeSupport {
  const _RuntimeSupport({this.image = false});

  final bool image;

  @override
  bool get textRuntimeAvailable => true;

  @override
  bool get imagePreprocessingAvailable => image;

  @override
  bool get audioPreprocessingAvailable => false;

  @override
  bool get documentPreprocessingAvailable => false;

  @override
  bool get speechToTextAvailable => false;
}
