import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/runtime_transcript_event.dart';
import 'package:openreef/ui/chat/composer_models.dart';
import 'package:openreef/ui/chat_session_port.dart';

class MainAgentApprovalController extends ChangeNotifier {
  MainAgentApprovalController({AgentMailbox? mailbox}) : _mailbox = mailbox {
    _mailboxRequestSubscription = _mailbox?.approvalRequests.listen(
      _handleMailboxApprovalRequest,
    );
    _mailboxResolutionSubscription = _mailbox?.approvalResolutions.listen(
      _handleMailboxApprovalResolution,
    );
  }

  final AgentMailbox? _mailbox;
  final Queue<_PendingApprovalEntry> _approvalQueue =
      Queue<_PendingApprovalEntry>();
  _PendingApprovalEntry? _activeApproval;
  StreamSubscription<ApprovalRequest>? _mailboxRequestSubscription;
  StreamSubscription<ApprovalResolution>? _mailboxResolutionSubscription;

  PendingToolApproval? get pendingApproval => _activeApproval?.presentation;

  Future<bool> confirmToolCall(ToolCall call) {
    final completer = Completer<bool>();
    _approvalQueue.add(
      _PendingApprovalEntry.main(call: call, completer: completer),
    );
    _promoteNextApproval();
    return completer.future;
  }

  void approvePendingApproval() {
    _resolveActiveApproval(approved: true);
  }

  void rejectPendingApproval() {
    _resolveActiveApproval(approved: false);
  }

  @override
  void dispose() {
    _mailboxRequestSubscription?.cancel();
    _mailboxResolutionSubscription?.cancel();
    super.dispose();
  }

  void _handleMailboxApprovalRequest(ApprovalRequest request) {
    _approvalQueue.add(_PendingApprovalEntry.mailbox(request));
    _promoteNextApproval();
  }

  void _handleMailboxApprovalResolution(ApprovalResolution resolution) {
    if (_activeApproval case final _PendingApprovalEntry active
        when active.requestId == resolution.requestId) {
      _activeApproval = null;
      notifyListeners();
      _promoteNextApproval();
      return;
    }

    _approvalQueue.removeWhere(
      (entry) => entry.requestId == resolution.requestId,
    );
  }

  void _resolveActiveApproval({required bool approved}) {
    final entry = _activeApproval;
    if (entry == null) {
      return;
    }

    if (entry.isMailboxRequest) {
      final requestId = entry.requestId;
      if (requestId != null) {
        _mailbox?.resolve(
          requestId,
          approved
              ? const MailboxDecision.approved()
              : const MailboxDecision.rejected(reason: 'user_denied'),
        );
      }
    } else {
      final completer = entry.mainDecision;
      if (completer != null && !completer.isCompleted) {
        completer.complete(approved);
      }
    }

    _activeApproval = null;
    notifyListeners();
    _promoteNextApproval();
  }

  void _promoteNextApproval() {
    if (_activeApproval != null || _approvalQueue.isEmpty) {
      return;
    }

    _activeApproval = _approvalQueue.removeFirst();
    notifyListeners();
  }
}

class _PendingApprovalEntry {
  _PendingApprovalEntry.main({
    required ToolCall call,
    required Completer<bool> completer,
  }) : presentation = PendingToolApproval(
         toolCallId: call.id,
         toolId: call.toolId,
         arguments: Map<String, Object?>.unmodifiable(call.arguments),
       ),
       requestId = null,
       mainDecision = completer;

  _PendingApprovalEntry.mailbox(ApprovalRequest request)
    : presentation = PendingToolApproval(
        toolCallId: request.call.id,
        toolId: request.call.toolId,
        arguments: Map<String, Object?>.unmodifiable(request.call.arguments),
      ),
      requestId = request.requestId,
      mainDecision = null;

  final PendingToolApproval presentation;
  final String? requestId;
  final Completer<bool>? mainDecision;

  bool get isMailboxRequest => requestId != null;
}

class _RuntimeRequestProjection {
  _RuntimeRequestProjection({
    required this.requestId,
    required this.sessionKey,
  });

  final String requestId;
  final String sessionKey;
  String? assistantMessageId;
  bool isFinalized = false;
  bool hasVisibleAssistantText = false;
  int? lastSequence;
}

class AgentLoopChatSession extends ChangeNotifier
    implements
        ChatSessionPort,
        ChatSessionFactory,
        ApprovalCapableChatSession,
        ChatExecutionSink,
        RuntimeTranscriptSink,
        PersistentChatSession,
        SystemAssistantInjectableChatSession {
  AgentLoopChatSession({
    required AgentTaskExecutor taskExecutor,
    MainAgentApprovalController? approvalController,
    this.sessionKey = 'agent:main',
    List<ChatTranscriptMessage> initialMessages =
        const <ChatTranscriptMessage>[],
  }) : _taskExecutor = taskExecutor,
       _approvalController = approvalController,
       _messages = initialMessages.isEmpty
           ? <ChatTranscriptMessage>[
               ChatTranscriptMessage(
                 id: 'boot-1',
                 sender: ChatMessageSender.system,
                 text:
                     'OPENREEF READY\nOffline agent shell initialized. AgentLoop bridge is live.',
                 timestamp: DateTime.now(),
               ),
             ]
           : List<ChatTranscriptMessage>.from(initialMessages) {
    _approvalController?.addListener(_handleApprovalChanged);
    _conversationHistory.addAll(_buildConversationHistory(_messages));
    _nextId = _deriveNextId(_messages);
  }

  final AgentTaskExecutor _taskExecutor;
  final MainAgentApprovalController? _approvalController;
  final String sessionKey;
  final List<ChatTranscriptMessage> _messages;
  final List<AgentMessage> _conversationHistory = <AgentMessage>[];

  ChatSessionStatus _status = ChatSessionStatus.idle;
  List<SubAgentActivity> _activities = const <SubAgentActivity>[];
  int _nextId = 0;
  bool _isRunning = false;
  bool _isDisposed = false;
  final Set<String> _runtimeMessageIds = <String>{};
  final Map<String, SubAgentActivity> _runtimeActivities =
      <String, SubAgentActivity>{};
  final Map<String, _RuntimeRequestProjection> _projectionsByRequestId =
      <String, _RuntimeRequestProjection>{};
  ChatTranscriptPersistencePort? _persistencePort;

  @override
  List<SubAgentActivity> get activities =>
      List<SubAgentActivity>.unmodifiable(_activities);

  @override
  PendingToolApproval? get pendingApproval =>
      _approvalController?.pendingApproval;

  @override
  List<ChatTranscriptMessage> get messages =>
      List<ChatTranscriptMessage>.unmodifiable(_messages);

  @override
  ChatSessionStatus get status => _status;

  @override
  void approvePendingApproval() {
    _approvalController?.approvePendingApproval();
  }

  @override
  void rejectPendingApproval() {
    _approvalController?.rejectPendingApproval();
  }

  @override
  Future<void> sendMessage(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || _isRunning) {
      return;
    }

    _isRunning = true;
    _runtimeActivities.clear();
    _appendMessage(ChatMessageSender.user, trimmed);
    _setStatus(ChatSessionStatus.planning);
    _setActivities(<SubAgentActivity>[
      SubAgentActivity(
        id: 'agent-loop',
        label: 'agent.loop',
        summary: 'Assembling context and running the offline agent loop.',
        details: <String>[
          'Session key: $sessionKey',
          'Prompt length: ${trimmed.length} chars',
        ],
        status: SubAgentActivityStatus.running,
      ),
    ]);

    final userTurnNumber = _nextTurnNumber();
    _conversationHistory.add(
      AgentMessage(
        role: AgentMessageRole.user,
        content: trimmed,
        turnNumber: userTurnNumber,
      ),
    );

    try {
      final request = ExecutionRequest.fromUserMessage(
        sessionKey: sessionKey,
        prompt: trimmed,
        metadata: <String, dynamic>{
          'conversationHistory': _conversationHistory
              .map(
                (message) => <String, Object?>{
                  'role': message.role.name,
                  'content': message.content,
                  'turnNumber': message.turnNumber,
                },
              )
              .toList(growable: false),
        },
      );
      final result = await _taskExecutor.execute(request);
      await appendExecutionResult(request, result);

      final loopResult = result.toAgentLoopResult();
      final responseText = _normalizeResponse(loopResult);
      if (_shouldTrackAssistantTurn(loopResult)) {
        _conversationHistory.add(
          AgentMessage(
            role: AgentMessageRole.assistant,
            content: responseText,
            turnNumber: userTurnNumber,
          ),
        );
      }

      if (_runtimeActivities.isEmpty && loopResult.toolResults.isNotEmpty) {
        _setActivities(
          loopResult.toolResults.map(_activityFromToolResult).toList(),
        );
      } else if (_runtimeActivities.isEmpty) {
        _setActivities(const <SubAgentActivity>[]);
      }
      await _emitTerminalStatus(
        requestId: result.requestId,
        status: _statusForResult(loopResult.sessionResult),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'OpenReef.AgentLoopChatSession: sendMessage.failed ${error.runtimeType}: $error',
      );
      debugPrintStack(stackTrace: stackTrace, label: 'chat sendMessage');
      final failureText = 'AgentLoop failed: $error';
      _conversationHistory.add(
        AgentMessage(
          role: AgentMessageRole.assistant,
          content: failureText,
          turnNumber: userTurnNumber,
        ),
      );
      _appendMessage(ChatMessageSender.system, failureText);
      _setActivities(<SubAgentActivity>[
        SubAgentActivity(
          id: 'agent-loop',
          label: 'agent.loop',
          summary: 'Agent loop execution failed.',
          details: <String>[error.toString()],
          status: SubAgentActivityStatus.failed,
        ),
      ]);
      await _persistBeforeTerminal(
        requestId: 'local-exception-${DateTime.now().microsecondsSinceEpoch}',
        terminalStatus: ChatSessionStatus.failed,
      );
      _setStatus(ChatSessionStatus.failed);
    } finally {
      _isRunning = false;
    }
  }

  @override
  Future<void> sendComposerSubmission(ComposerSubmission submission) async {
    if (submission.attachments.isEmpty) {
      return sendMessage(submission.text);
    }

    if (submission.text.trim().isNotEmpty) {
      _appendMessage(
        ChatMessageSender.system,
        'Attachments are not available in this chat yet. Sending the text only.',
      );
      return sendMessage(submission.text);
    }

    _appendMessage(
      ChatMessageSender.system,
      'Attachments are not available in this chat yet.',
    );
  }

  String _normalizeResponse(AgentLoopResult result) {
    final trimmedText = result.text.trim();
    if (trimmedText.isNotEmpty && !_isProtocolOnlyAssistantText(trimmedText)) {
      return trimmedText;
    }
    if (result.sessionResult == SessionResult.frozen) {
      return switch (result.reason) {
        'rejection_loop' =>
          'The agent session was frozen after repeating the same blocked tool request.',
        'iteration_cap' =>
          'The agent session was frozen after hitting a safety iteration cap.',
        _ => 'The agent session was frozen after repeated execution errors.',
      };
    }
    if (result.sessionResult == SessionResult.failed) {
      if (kDebugMode &&
          (result.exceptionType != null || result.errorMessage != null)) {
        final details = <String>[
          if (result.reason != null) 'reason=${result.reason}',
          if (result.exceptionType != null) 'exception=${result.exceptionType}',
          if (result.errorMessage != null) 'message=${result.errorMessage}',
        ].join(' ');
        if (details.isNotEmpty) {
          return 'The agent turn failed. $details';
        }
      }
      return switch (result.reason) {
        'session_busy' =>
          'Another execution is already running for this session.',
        'compaction_failure' =>
          'The agent turn failed while compacting context.',
        'context_assembly_failure' =>
          'The agent turn failed while assembling context.',
        'semantic_embedding_model_not_ready' =>
          'Semantic retrieval needs an embedding model before the agent can choose tools and skills. Open Settings > Semantic Retrieval to install or activate one.',
        'generation_failure' =>
          'The agent turn failed during model generation.',
        'executor_failure' =>
          'The agent turn failed before execution completed.',
        _ => 'The agent turn failed before completion.',
      };
    }
    return 'LiteRT completed the turn but returned no visible text.';
  }

  ChatMessageSender _responseSenderForText(String responseText) {
    if (_isProtectivePauseMessage(responseText)) {
      return ChatMessageSender.system;
    }
    return ChatMessageSender.assistant;
  }

  SubAgentActivity _activityFromToolResult(ToolResult result) {
    final toolId = result.toolId ?? 'unknown';
    final callId = result.callId ?? 'unknown';
    return SubAgentActivity(
      id: 'tool-$callId',
      label: toolId,
      summary: result.userVisibleMessage ?? result.summary,
      details: <String>[
        'Call: $callId',
        'Status: ${result.statusName}',
        'Result: ${result.statusName}: ${result.userVisibleMessage ?? result.summary}',
      ],
      status: result.isError
          ? SubAgentActivityStatus.failed
          : SubAgentActivityStatus.completed,
    );
  }

  bool _shouldTrackAssistantTurn(AgentLoopResult result) {
    final responseText = _normalizeResponse(result);
    if (_isProtocolOnlyAssistantText(responseText)) {
      return false;
    }
    if (_hasUnstableToolProtocolFailure(result)) {
      return false;
    }
    if (result.reason == 'post_tool_completion_missing') {
      return false;
    }
    return result.sessionResult != SessionResult.completed ||
        responseText.trim().isNotEmpty;
  }

  bool _isProtocolOnlyAssistantText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (trimmed.startsWith('<|tool_call>') &&
        trimmed.endsWith('<tool_call|>')) {
      return true;
    }
    final parsed = const AgentResponseParser().parse(trimmed);
    return parsed.hasParserFailure ||
        (parsed.hasToolCall && parsed.text.trim().isEmpty);
  }

  bool _isProtectivePauseMessage(String text) {
    final lowered = text.toLowerCase();
    return lowered.contains('openreef paused generation') ||
        lowered.contains('low free ram detected');
  }

  int _nextTurnNumber() {
    return _conversationHistory.fold<int>(
          0,
          (current, message) =>
              message.turnNumber != null && message.turnNumber! > current
              ? message.turnNumber!
              : current,
        ) +
        1;
  }

  void _appendMessage(ChatMessageSender sender, String text) {
    if (_isDisposed) {
      return;
    }
    if (sender == ChatMessageSender.assistant &&
        _isProtocolOnlyAssistantText(text)) {
      return;
    }

    _messages.add(
      ChatTranscriptMessage(
        id: 'msg-${_nextId++}',
        sender: sender,
        text: text,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void _upsertMessage(ChatTranscriptMessage message) {
    if (_isDisposed) {
      return;
    }

    final index = _messages.indexWhere((entry) => entry.id == message.id);
    if (index == -1) {
      _messages.add(message);
    } else {
      _messages[index] = message;
    }
    notifyListeners();
  }

  void _replaceMessage(
    String id,
    ChatTranscriptMessage Function(ChatTranscriptMessage current) transform,
  ) {
    if (_isDisposed) {
      return;
    }

    final index = _messages.indexWhere((message) => message.id == id);
    if (index == -1) {
      return;
    }
    _messages[index] = transform(_messages[index]);
    notifyListeners();
  }

  void _setActivities(List<SubAgentActivity> nextActivities) {
    if (_isDisposed) {
      return;
    }

    _activities = nextActivities;
    notifyListeners();
  }

  void _setStatus(ChatSessionStatus nextStatus) {
    if (_isDisposed || _status == nextStatus) {
      return;
    }

    _status = nextStatus;
    notifyListeners();
  }

  @override
  void attachTranscriptPersistencePort(ChatTranscriptPersistencePort port) {
    _persistencePort = port;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _approvalController?.removeListener(_handleApprovalChanged);
    super.dispose();
  }

  @override
  void injectSystemAssistantEntry(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _appendMessage(ChatMessageSender.assistant, trimmed);
  }

  @override
  Future<void> appendExecutionResult(
    ExecutionRequest request,
    ExecutionResult result,
  ) async {
    if (request.sessionKey != sessionKey ||
        result.sessionKey != sessionKey ||
        request.sessionKey != result.sessionKey) {
      return;
    }
    if (!_isVisibleInChat(result.visibility)) {
      return;
    }
    final loopResult = result.toAgentLoopResult();
    final responseText = _normalizeResponse(loopResult);
    if (_hasUnstableToolProtocolFailure(loopResult)) {
      await _emitTerminalStatus(
        requestId: result.requestId,
        status: _statusForLifecycle(result.terminalStatus),
      );
      return;
    }
    if (responseText.trim().isEmpty ||
        _isProtocolOnlyAssistantText(responseText)) {
      return;
    }
    final messageId = '${result.requestId}-assistant-final';
    final projection = _projectionsByRequestId[result.requestId];
    if (projection != null &&
        projection.isFinalized &&
        projection.hasVisibleAssistantText) {
      return;
    }
    final sequence = (projection?.lastSequence ?? -1) + 1;
    await applyRuntimeTranscriptEvent(
      RuntimeTranscriptEvent(
        kind: RuntimeTranscriptEventKind.assistantMessageFinalized,
        requestId: result.requestId,
        sessionKey: sessionKey,
        sequence: sequence,
        occurredAt: DateTime.now().toUtc(),
        messageId: messageId,
        finalText: responseText,
        status: result.terminalStatus.name,
      ),
    );
    await _emitTerminalStatus(
      requestId: result.requestId,
      status: _statusForLifecycle(result.terminalStatus),
    );
  }

  @override
  Future<void> applyRuntimeTranscriptEvent(RuntimeTranscriptEvent event) async {
    if (event.sessionKey != sessionKey || _isDisposed) {
      return;
    }
    final projection = _projectionFor(event);
    if (!_acceptSequence(projection, event.sequence)) {
      return;
    }

    switch (event.kind) {
      case RuntimeTranscriptEventKind.assistantMessageStarted:
        final messageId = event.messageId ?? '${event.requestId}-assistant';
        _runtimeMessageIds.add(messageId);
        projection.assistantMessageId = messageId;
        _upsertMessage(
          ChatTranscriptMessage(
            id: messageId,
            sender: ChatMessageSender.assistant,
            text: '',
            timestamp: event.occurredAt.toLocal(),
            isStreaming: true,
          ),
        );
        _setStatus(ChatSessionStatus.streaming);
      case RuntimeTranscriptEventKind.assistantMessageDelta:
        final messageId = event.messageId ?? '${event.requestId}-assistant';
        _runtimeMessageIds.add(messageId);
        projection.assistantMessageId = messageId;
        if (!_messages.any((message) => message.id == messageId)) {
          _upsertMessage(
            ChatTranscriptMessage(
              id: messageId,
              sender: ChatMessageSender.assistant,
              text: event.deltaText ?? '',
              timestamp: event.occurredAt.toLocal(),
              isStreaming: true,
            ),
          );
        } else {
          _replaceMessage(
            messageId,
            (message) => message.copyWith(
              text: '${message.text}${event.deltaText ?? ''}',
              isStreaming: true,
            ),
          );
        }
        _setStatus(ChatSessionStatus.streaming);
      case RuntimeTranscriptEventKind.assistantMessageFinalized:
        await _finalizeRuntimeMessage(event, failed: false);
      case RuntimeTranscriptEventKind.assistantMessageFailed:
        await _finalizeRuntimeMessage(event, failed: true);
      case RuntimeTranscriptEventKind.toolStepStarted:
      case RuntimeTranscriptEventKind.toolStepUpdated:
      case RuntimeTranscriptEventKind.toolStepFinished:
        _applyToolStepEvent(event);
    }
  }

  Future<void> _finalizeRuntimeMessage(
    RuntimeTranscriptEvent event, {
    required bool failed,
  }) async {
    final projection = _projectionsByRequestId[event.requestId]!;
    final messageId = event.messageId ?? '${event.requestId}-assistant';
    final normalizedText = (event.finalText ?? '').trim();
    if (_isProtocolOnlyAssistantText(normalizedText)) {
      projection.isFinalized = true;
      projection.hasVisibleAssistantText = false;
      return;
    }
    final text = normalizedText.isEmpty
        ? _fallbackTextForEvent(event, failed: failed)
        : normalizedText;
    _runtimeMessageIds.add(messageId);
    projection.assistantMessageId = messageId;
    projection.isFinalized = true;
    projection.hasVisibleAssistantText = text.trim().isNotEmpty;
    final sender = failed
        ? ChatMessageSender.system
        : _responseSenderForText(text);
    if (!_messages.any((message) => message.id == messageId)) {
      if (text.isEmpty) {
        return;
      }
      _upsertMessage(
        ChatTranscriptMessage(
          id: messageId,
          sender: sender,
          text: text,
          timestamp: event.occurredAt.toLocal(),
        ),
      );
      await _persistBeforeTerminal(
        requestId: event.requestId,
        terminalStatus: failed
            ? ChatSessionStatus.failed
            : ChatSessionStatus.completed,
      );
      return;
    }
    _replaceMessage(
      messageId,
      (message) => message.copyWith(
        sender: sender,
        text: text.isEmpty ? message.text : text,
        isStreaming: false,
      ),
    );
    await _persistBeforeTerminal(
      requestId: event.requestId,
      terminalStatus: failed
          ? ChatSessionStatus.failed
          : ChatSessionStatus.completed,
    );
  }

  void _applyToolStepEvent(RuntimeTranscriptEvent event) {
    final stepId =
        event.stepId ?? event.toolCallId ?? '${event.requestId}-tool';
    final existing = _runtimeActivities[stepId];
    final status = switch (event.kind) {
      RuntimeTranscriptEventKind.toolStepStarted ||
      RuntimeTranscriptEventKind.toolStepUpdated =>
        SubAgentActivityStatus.running,
      RuntimeTranscriptEventKind.toolStepFinished =>
        event.toolResult?.isError ?? false
            ? SubAgentActivityStatus.failed
            : SubAgentActivityStatus.completed,
      _ => SubAgentActivityStatus.running,
    };
    final details = <String>[
      ...?existing?.details,
      if (event.toolCallId != null) 'Call: ${event.toolCallId}',
      if (event.status != null) 'Status: ${event.status}',
      if (event.toolResult != null)
        'Result: ${event.toolResult!.statusName}: ${event.toolResult!.userVisibleMessage ?? event.toolResult!.summary}',
    ];
    _runtimeActivities[stepId] = SubAgentActivity(
      id: stepId,
      label: event.toolId ?? 'tool',
      summary: event.summary ?? existing?.summary ?? 'Tool step updated.',
      details: List<String>.unmodifiable(details.toSet()),
      status: status,
    );
    _setActivities(_runtimeActivities.values.toList(growable: false));
    _setStatus(ChatSessionStatus.toolRouting);
  }

  _RuntimeRequestProjection _projectionFor(RuntimeTranscriptEvent event) {
    return _projectionsByRequestId.putIfAbsent(
      event.requestId,
      () => _RuntimeRequestProjection(
        requestId: event.requestId,
        sessionKey: event.sessionKey,
      ),
    );
  }

  bool _acceptSequence(_RuntimeRequestProjection projection, int sequence) {
    final last = projection.lastSequence;
    if (last != null && sequence <= last) {
      return false;
    }
    projection.lastSequence = sequence;
    return true;
  }

  String _fallbackTextForEvent(
    RuntimeTranscriptEvent event, {
    required bool failed,
  }) {
    if (failed) {
      return event.summary?.trim().isNotEmpty ?? false
          ? event.summary!.trim()
          : 'The agent turn failed before completion.';
    }
    return 'LiteRT completed the turn but returned no visible text.';
  }

  Future<void> _emitTerminalStatus({
    required String requestId,
    required ChatSessionStatus status,
  }) async {
    final persisted = await _persistBeforeTerminal(
      requestId: requestId,
      terminalStatus: status,
    );
    if (!persisted) {
      _setStatus(ChatSessionStatus.persistenceFailed);
      return;
    }
    _setStatus(status);
  }

  Future<bool> _persistBeforeTerminal({
    required String requestId,
    required ChatSessionStatus terminalStatus,
  }) async {
    final port = _persistencePort;
    if (port == null) {
      return true;
    }
    final result = await port.persistTranscriptBeforeTerminal(
      ChatTranscriptPersistenceRequest(
        sessionKey: sessionKey,
        requestId: requestId,
        terminalStatus: terminalStatus,
        messages: List<ChatTranscriptMessage>.unmodifiable(_messages),
      ),
    );
    if (result.isSuccess) {
      return true;
    }
    _appendPersistenceFailureMessage(result);
    return false;
  }

  void _appendPersistenceFailureMessage(
    ChatTranscriptPersistenceResult result,
  ) {
    final text =
        'The agent completed, but OpenReef could not save the final transcript. ${result.errorMessage ?? result.errorCode ?? ''}'
            .trim();
    final id = 'persist-failed-${DateTime.now().microsecondsSinceEpoch}';
    _upsertMessage(
      ChatTranscriptMessage(
        id: id,
        sender: ChatMessageSender.system,
        text: text,
        timestamp: DateTime.now(),
      ),
    );
  }

  ChatSessionStatus _statusForResult(SessionResult result) {
    return switch (result) {
      SessionResult.completed => ChatSessionStatus.completed,
      SessionResult.failed => ChatSessionStatus.failed,
      SessionResult.frozen => ChatSessionStatus.frozen,
      SessionResult.cancelled => ChatSessionStatus.cancelled,
      SessionResult.suspended => ChatSessionStatus.suspended,
    };
  }

  ChatSessionStatus _statusForLifecycle(ExecutionLifecycleStatus status) {
    return switch (status) {
      ExecutionLifecycleStatus.completed => ChatSessionStatus.completed,
      ExecutionLifecycleStatus.failed ||
      ExecutionLifecycleStatus.rejected => ChatSessionStatus.failed,
      ExecutionLifecycleStatus.cancelled => ChatSessionStatus.cancelled,
      ExecutionLifecycleStatus.suspended => ChatSessionStatus.suspended,
      ExecutionLifecycleStatus.queued ||
      ExecutionLifecycleStatus.running => ChatSessionStatus.streaming,
    };
  }

  bool _isVisibleInChat(ExecutionVisibility visibility) {
    return visibility == ExecutionVisibility.chat ||
        visibility == ExecutionVisibility.chatAndBackground;
  }

  bool _hasUnstableToolProtocolFailure(AgentLoopResult result) {
    if (result.reason == 'malformed_tool_call' ||
        result.reason == 'post_tool_completion_missing') {
      return true;
    }
    for (final toolResult in result.toolResults) {
      if (toolResult.status != ToolResultStatus.validationError) {
        continue;
      }
      if (toolResult.metadata['visibleSuppressed'] == true) {
        return true;
      }
      final reason =
          toolResult.metadata['reason'] as String? ??
          toolResult.metadata['errorCode'] as String?;
      if (reason == 'malformed_tool_call' ||
          reason == 'schema_passed_as_args' ||
          reason == 'typed_tool_call_without_dispatch') {
        return true;
      }
    }
    return false;
  }

  @override
  ChatSessionPort createSession({
    required String sessionId,
    List<ChatTranscriptMessage> initialMessages =
        const <ChatTranscriptMessage>[],
  }) {
    return AgentLoopChatSession(
      taskExecutor: _taskExecutor,
      approvalController: _approvalController,
      sessionKey: sessionId,
      initialMessages: initialMessages,
    );
  }

  void _handleApprovalChanged() {
    if (_isDisposed) {
      return;
    }
    notifyListeners();
  }

  List<AgentMessage> _buildConversationHistory(
    List<ChatTranscriptMessage> messages,
  ) {
    final history = <AgentMessage>[];
    var turnNumber = 0;
    for (final message in messages) {
      if (message.sender == ChatMessageSender.user) {
        turnNumber += 1;
        history.add(
          AgentMessage(
            role: AgentMessageRole.user,
            content: message.text,
            turnNumber: turnNumber,
          ),
        );
        continue;
      }

      if (message.sender == ChatMessageSender.assistant) {
        if (_isProtocolOnlyAssistantText(message.text)) {
          continue;
        }
        final assistantTurn = turnNumber == 0 ? 1 : turnNumber;
        history.add(
          AgentMessage(
            role: AgentMessageRole.assistant,
            content: message.text,
            turnNumber: assistantTurn,
          ),
        );
      }
    }
    return history;
  }

  int _deriveNextId(List<ChatTranscriptMessage> messages) {
    var highest = -1;
    for (final message in messages) {
      final id = message.id;
      if (!id.startsWith('msg-')) {
        continue;
      }
      final parsed = int.tryParse(id.substring(4));
      if (parsed != null && parsed > highest) {
        highest = parsed;
      }
    }
    return highest + 1;
  }
}
