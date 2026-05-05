import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:openreef/agent/agent_execution_event.dart';
import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/runtime_transcript_event.dart';
import 'package:openreef/models/model_capabilities.dart';
import 'package:openreef/ui/chat/attachment_runtime_support.dart';
import 'package:openreef/ui/chat/composer_capability_resolver.dart';
import 'package:openreef/ui/chat/composer_models.dart';
import 'package:openreef/ui/chat/composer_submission_validator.dart';
import 'package:openreef/ui/chat_session_port.dart';

class MainAgentApprovalController extends ChangeNotifier {
  MainAgentApprovalController({AgentMailbox? mailbox, DateTime Function()? now})
    : _mailbox = mailbox,
      _now = now ?? DateTime.now {
    _mailboxRequestSubscription = _mailbox?.approvalRequests.listen(
      _handleMailboxApprovalRequest,
    );
    _mailboxResolutionSubscription = _mailbox?.approvalResolutions.listen(
      _handleMailboxApprovalResolution,
    );
  }

  static const Duration approvalTtl = Duration(minutes: 2);

  final AgentMailbox? _mailbox;
  final DateTime Function() _now;
  final Queue<_PendingApprovalEntry> _approvalQueue =
      Queue<_PendingApprovalEntry>();
  _PendingApprovalEntry? _activeApproval;
  StreamSubscription<ApprovalRequest>? _mailboxRequestSubscription;
  StreamSubscription<ApprovalResolution>? _mailboxResolutionSubscription;

  PendingToolApproval? get pendingApproval {
    _expireActiveApprovalIfNeeded();
    return _activeApproval?.presentation;
  }

  Future<bool> confirmToolCall(ToolCall call) {
    final completer = Completer<bool>();
    _approvalQueue.add(
      _PendingApprovalEntry.main(
        call: _canonicalizeApprovalCall(call),
        completer: completer,
        createdAt: _now(),
      ),
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

  bool resolvePendingApprovalIntent(bool approved) {
    if (_activeApproval == null) {
      return false;
    }
    _resolveActiveApproval(approved: approved);
    return true;
  }

  @override
  void dispose() {
    _mailboxRequestSubscription?.cancel();
    _mailboxResolutionSubscription?.cancel();
    super.dispose();
  }

  void _handleMailboxApprovalRequest(ApprovalRequest request) {
    _approvalQueue.add(
      _PendingApprovalEntry.mailbox(
        request,
        createdAt: _now(),
        call: _canonicalizeApprovalCall(request.call),
      ),
    );
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
    if (_expireActiveApprovalIfNeeded()) {
      return;
    }
    final entry = _activeApproval;
    if (entry == null) {
      return;
    }

    _activeApproval = null;
    notifyListeners();
    _promoteNextApproval();
    _completeEntry(
      entry,
      approved: approved,
      rejectionReason: approved ? null : 'user_denied',
    );
  }

  bool _expireActiveApprovalIfNeeded() {
    final entry = _activeApproval;
    if (entry == null || !_isExpired(entry)) {
      return false;
    }
    _activeApproval = null;
    notifyListeners();
    _completeEntry(entry, approved: false, rejectionReason: 'approval_expired');
    _promoteNextApproval();
    return true;
  }

  bool _isExpired(_PendingApprovalEntry entry) {
    return _now().difference(entry.presentation.createdAt) > approvalTtl;
  }

  void _completeEntry(
    _PendingApprovalEntry entry, {
    required bool approved,
    String? rejectionReason,
  }) {
    if (entry.isMailboxRequest) {
      final requestId = entry.requestId;
      if (requestId != null) {
        _mailbox?.resolve(
          requestId,
          approved
              ? const MailboxDecision.approved()
              : MailboxDecision.rejected(
                  reason: rejectionReason ?? 'user_denied',
                ),
        );
      }
    } else {
      final completer = entry.mainDecision;
      if (completer != null && !completer.isCompleted) {
        completer.complete(approved);
      }
    }
  }

  void _promoteNextApproval() {
    if (_activeApproval != null) {
      return;
    }

    while (_approvalQueue.isNotEmpty) {
      final next = _approvalQueue.removeFirst();
      if (_isExpired(next)) {
        _completeEntry(
          next,
          approved: false,
          rejectionReason: 'approval_expired',
        );
        continue;
      }
      _activeApproval = next;
      notifyListeners();
      return;
    }
  }

  ToolCall _canonicalizeApprovalCall(ToolCall call) {
    final canonicalToolId = _canonicalToolId(call.toolId);
    if (canonicalToolId == call.toolId) {
      return call;
    }
    return ToolCall(
      id: call.id,
      toolId: canonicalToolId,
      arguments: call.arguments,
      rawArguments: call.rawArguments,
      hasRawArguments: call.hasRawArguments,
      source: call.source,
    );
  }

  String _canonicalToolId(String toolId) {
    return switch (toolId) {
      'communication_sms_send' => 'sms_send',
      'communication_phone_call' => 'phone_call',
      'communication_phone_dial' => 'phone_dial',
      _ => toolId,
    };
  }
}

class _PendingApprovalEntry {
  _PendingApprovalEntry.main({
    required ToolCall call,
    required Completer<bool> completer,
    required DateTime createdAt,
  }) : presentation = PendingToolApproval(
         toolCallId: call.id,
         toolId: call.toolId,
         arguments: Map<String, Object?>.unmodifiable(call.arguments),
         createdAt: createdAt,
       ),
       requestId = null,
       mainDecision = completer;

  _PendingApprovalEntry.mailbox(
    ApprovalRequest request, {
    required DateTime createdAt,
    required ToolCall call,
  }) : presentation = PendingToolApproval(
         toolCallId: call.id,
         toolId: call.toolId,
         arguments: Map<String, Object?>.unmodifiable(call.arguments),
         createdAt: createdAt,
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
  int? lastExecutionSequence;
}

class AgentLoopChatSession extends ChangeNotifier
    implements
        ChatSessionPort,
        ChatSessionFactory,
        ApprovalCapableChatSession,
        ChatExecutionSink,
        RuntimeTranscriptSink,
        AgentExecutionEventSink,
        ExecutionTraceCapableChatSession,
        PersistentChatSession,
        CancellableChatSession,
        SystemAssistantInjectableChatSession {
  AgentLoopChatSession({
    required AgentTaskExecutor taskExecutor,
    MainAgentApprovalController? approvalController,
    ComposerCapabilityResolver? composerCapabilityResolver,
    this.sessionKey = 'agent:main',
    List<ChatTranscriptMessage> initialMessages =
        const <ChatTranscriptMessage>[],
  }) : _taskExecutor = taskExecutor,
       _approvalController = approvalController,
       _composerCapabilityResolver =
           composerCapabilityResolver ??
           const ComposerCapabilityResolver(
             modelCapabilityProvider: StaticActiveModelCapabilityProvider(
               ModelInputCapabilities.textOnly,
             ),
             runtimeSupport: DefaultAttachmentRuntimeSupport(),
           ),
       _messages = List<ChatTranscriptMessage>.from(initialMessages) {
    _approvalController?.addListener(_handleApprovalChanged);
    _conversationHistory.addAll(_buildConversationHistory(_messages));
    _nextId = _deriveNextId(_messages);
  }

  final AgentTaskExecutor _taskExecutor;
  final MainAgentApprovalController? _approvalController;
  final ComposerCapabilityResolver _composerCapabilityResolver;
  final ComposerSubmissionValidator _composerSubmissionValidator =
      const ComposerSubmissionValidator();
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
  final Set<String> _terminalExecutionRequestIds = <String>{};
  final Map<String, _RuntimeRequestProjection> _projectionsByRequestId =
      <String, _RuntimeRequestProjection>{};
  final Map<String, ExecutionTraceStep> _executionTraceSteps =
      <String, ExecutionTraceStep>{};
  ChatTranscriptPersistencePort? _persistencePort;
  String? _activeRequestId;
  ExecutionTrace? _executionTrace;

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
  ExecutionTrace? get executionTrace => _executionTrace;

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
    if (trimmed.isEmpty) {
      return;
    }
    if (_resolvePendingApprovalFromText(trimmed)) {
      _appendMessage(ChatMessageSender.user, trimmed);
      return;
    }
    if (_isRunning) {
      return;
    }

    _isRunning = true;
    _runtimeActivities.clear();
    _executionTraceSteps.clear();
    _executionTrace = null;
    _appendMessage(ChatMessageSender.user, trimmed);
    _setStatus(ChatSessionStatus.planning);
    _setActivities(const <SubAgentActivity>[]);

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
      _activeRequestId = request.id;
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
      const failureText = 'The agent turn failed before completion.';
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
          details: const <String>['The runtime raised an internal error.'],
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
      _activeRequestId = null;
    }
  }

  @override
  Future<bool> cancelActiveRun() async {
    if (!_isRunning) {
      return false;
    }
    rejectPendingApproval();
    final cancelled = await _taskExecutor.cancelActiveRun(
      runId: _activeRequestId,
      sessionKey: sessionKey,
      reason: RunCancellationReason.userRequested,
    );
    if (cancelled) {
      _setStatus(ChatSessionStatus.cancelled);
    }
    return cancelled;
  }

  @override
  Future<void> sendComposerSubmission(ComposerSubmission submission) async {
    if (submission.attachments.isEmpty) {
      return sendMessage(submission.text);
    }

    final trimmed = submission.text.trim();
    if (submission.isEmpty) {
      return;
    }
    if (_isRunning) {
      return;
    }

    final validation = _composerSubmissionValidator.validate(
      submission,
      _composerCapabilityResolver.resolve(),
    );
    if (validation.hasRejectedAttachments) {
      final rejected = validation.rejectedAttachments.first;
      _appendMessage(
        ChatMessageSender.system,
        _unsupportedAttachmentMessage(
          rejected.attachment.type,
          rejected.availability,
        ),
      );
      return;
    }
    if (validation.submission.attachments.isEmpty) {
      return sendMessage(validation.submission.text);
    }

    _isRunning = true;
    _runtimeActivities.clear();
    _executionTraceSteps.clear();
    _executionTrace = null;
    _appendMessage(ChatMessageSender.user, trimmed);
    _setStatus(ChatSessionStatus.planning);
    _setActivities(const <SubAgentActivity>[]);

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
        attachments: validation.submission.attachments
            .map(_executionAttachmentFromComposer)
            .toList(growable: false),
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
      _activeRequestId = request.id;
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
        'OpenReef.AgentLoopChatSession: sendComposerSubmission.failed ${error.runtimeType}: $error',
      );
      debugPrintStack(
        stackTrace: stackTrace,
        label: 'chat sendComposerSubmission',
      );
      const failureText = 'The agent turn failed before completion.';
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
          details: const <String>['The runtime raised an internal error.'],
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
      _activeRequestId = null;
    }
  }

  ExecutionAttachment _executionAttachmentFromComposer(
    ComposerAttachmentDescriptor attachment,
  ) {
    return ExecutionAttachment(
      id: attachment.id,
      type: switch (attachment.type) {
        ComposerAttachmentType.image => ExecutionAttachmentType.image,
        ComposerAttachmentType.audio => ExecutionAttachmentType.audio,
        ComposerAttachmentType.document => ExecutionAttachmentType.document,
        ComposerAttachmentType.voiceMessage =>
          ExecutionAttachmentType.voiceMessage,
      },
      displayName: attachment.displayName,
      sizeBytes: attachment.sizeBytes,
      mimeType: attachment.mimeType,
      sourceUri: attachment.sourceUri,
    );
  }

  String _unsupportedAttachmentMessage(
    ComposerAttachmentType type,
    ComposerAttachmentAvailability availability,
  ) {
    final label = switch (type) {
      ComposerAttachmentType.image => 'Image',
      ComposerAttachmentType.audio => 'Audio',
      ComposerAttachmentType.document => 'Document',
      ComposerAttachmentType.voiceMessage => 'Voice message',
    };
    return switch (availability) {
      ComposerAttachmentAvailability.unsupportedByModel =>
        '$label attachments are not supported by the selected model.',
      ComposerAttachmentAvailability.unsupportedByRuntime =>
        '$label attachments are supported by the model, but the required runtime preprocessing is unavailable.',
      ComposerAttachmentAvailability.unavailable =>
        '$label attachments are unavailable for the selected model and current runtime.',
      ComposerAttachmentAvailability.available =>
        '$label attachments are unavailable.',
    };
  }

  String _normalizeResponse(AgentLoopResult result) {
    final trimmedText = result.text.trim();
    if (trimmedText.isNotEmpty && !_isInternalOnlyText(trimmedText)) {
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
    if (result.sessionResult == SessionResult.cancelled) {
      return 'Agent turn was cancelled.';
    }
    if (result.sessionResult == SessionResult.failed) {
      if (kDebugMode &&
          result.reason != 'generation_failure' &&
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
    if (_isInternalOnlyText(responseText)) {
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

  bool _isInternalOnlyText(String text) {
    final trimmed = text.trim();
    if (_isProtocolOnlyAssistantText(trimmed)) {
      return true;
    }
    if (trimmed.startsWith('[TOOL]') ||
        trimmed.startsWith('[TOOL_ERROR]') ||
        trimmed.startsWith('toolId:') ||
        trimmed.startsWith('callId:') ||
        trimmed.startsWith('status:') ||
        trimmed.startsWith('summary:') ||
        trimmed.startsWith('reason:') ||
        trimmed.contains('\ntoolId:') ||
        trimmed.contains('\ncallId:') ||
        trimmed.contains('\nstatus:') ||
        trimmed.contains('missing_argument:') ||
        trimmed.contains('validation_error')) {
      return true;
    }
    return false;
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
    if ((sender == ChatMessageSender.assistant ||
            sender == ChatMessageSender.system) &&
        _isInternalOnlyText(text)) {
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

  bool _resolvePendingApprovalFromText(String text) {
    final controller = _approvalController;
    final intent = _approvalIntentFor(text);
    if (intent == null) {
      return false;
    }
    if (controller == null) {
      return false;
    }
    return controller.resolvePendingApprovalIntent(intent);
  }

  bool? _approvalIntentFor(String text) {
    final normalized = text.toLowerCase().trim();
    if (<String>{
      'yes',
      'y',
      'yeah',
      'yep',
      'ok',
      'okay',
      'confirm',
      'approved',
      'approve',
      'do it',
      'send it',
      'send it now',
      'yes send it',
      'yes send it now',
      'go ahead',
    }.contains(normalized)) {
      return true;
    }
    if (<String>{
      'no',
      'n',
      'nope',
      'cancel',
      'stop',
      'reject',
      'deny',
      'do not',
      "don't",
      'dont',
    }.contains(normalized)) {
      return false;
    }
    return null;
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
    if (responseText.trim().isEmpty || _isInternalOnlyText(responseText)) {
      return;
    }
    final projection = _projectionsByRequestId[result.requestId];
    if (projection != null &&
        projection.isFinalized &&
        projection.hasVisibleAssistantText) {
      return;
    }
    final messageId =
        projection?.assistantMessageId ?? '${result.requestId}-assistant-final';
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
        final deltaText = event.deltaText ?? '';
        if (_isInternalOnlyText(deltaText)) {
          _setStatus(ChatSessionStatus.streaming);
          return;
        }
        final messageId = event.messageId ?? '${event.requestId}-assistant';
        _runtimeMessageIds.add(messageId);
        projection.assistantMessageId = messageId;
        if (!_messages.any((message) => message.id == messageId)) {
          _upsertMessage(
            ChatTranscriptMessage(
              id: messageId,
              sender: ChatMessageSender.assistant,
              text: deltaText,
              timestamp: event.occurredAt.toLocal(),
              isStreaming: true,
            ),
          );
        } else {
          _replaceMessage(
            messageId,
            (message) => message.copyWith(
              text: '${message.text}$deltaText',
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

  @override
  Future<void> applyAgentExecutionEvent(AgentExecutionEvent event) async {
    if (event.sessionId != sessionKey || _isDisposed) {
      return;
    }
    final projection = _projectionsByRequestId.putIfAbsent(
      event.requestId,
      () => _RuntimeRequestProjection(
        requestId: event.requestId,
        sessionKey: event.sessionId,
      ),
    );
    if (_terminalExecutionRequestIds.contains(event.requestId)) {
      return;
    }
    if (!_acceptExecutionSequence(projection, event.sequence)) {
      return;
    }

    switch (event) {
      case TokenDeltaEvent():
        _applyTokenDeltaEvent(event);
      case StepStartedEvent():
        _upsertExecutionStep(
          requestId: event.requestId,
          status: ExecutionTraceStatus.running,
          step: ExecutionTraceStep(
            id: event.stepId,
            kind: ExecutionStepKind.step,
            title: event.label,
            status: ExecutionStepStatus.running,
            summary: 'Running',
            timestamp: event.occurredAt.toLocal(),
          ),
        );
        _setStatus(ChatSessionStatus.toolRouting);
      case StepUpdatedEvent():
        final existing = _executionTraceSteps[event.stepId];
        _upsertExecutionStep(
          requestId: event.requestId,
          status: ExecutionTraceStatus.running,
          step:
              (existing ??
                      ExecutionTraceStep(
                        id: event.stepId,
                        kind: ExecutionStepKind.step,
                        title: 'Step',
                        status: ExecutionStepStatus.running,
                        summary: 'Running',
                        timestamp: event.occurredAt.toLocal(),
                      ))
                  .copyWith(
                    status: _stepStatusForRuntimeStatus(event.status),
                    summary: _sentenceCaseStatus(event.status),
                    timestamp: event.occurredAt.toLocal(),
                  ),
        );
        _setStatus(ChatSessionStatus.toolRouting);
      case ToolCallStartedEvent():
        _upsertExecutionStep(
          requestId: event.requestId,
          status: ExecutionTraceStatus.running,
          step: ExecutionTraceStep(
            id: event.callId,
            kind: ExecutionStepKind.tool,
            title: event.displayLabel,
            status: ExecutionStepStatus.running,
            summary: 'Running ${event.toolId}',
            details: _detailsFromPreview(event.safeArgsPreview),
            timestamp: event.occurredAt.toLocal(),
          ),
        );
        _setStatus(ChatSessionStatus.toolRouting);
      case ToolCallResultEvent():
        final existing = _executionTraceSteps[event.callId];
        _upsertExecutionStep(
          requestId: event.requestId,
          status: ExecutionTraceStatus.running,
          step:
              (existing ??
                      ExecutionTraceStep(
                        id: event.callId,
                        kind: ExecutionStepKind.tool,
                        title: event.displayLabel,
                        status: ExecutionStepStatus.running,
                        summary: 'Running ${event.toolId}',
                        timestamp: event.occurredAt.toLocal(),
                      ))
                  .copyWith(
                    title: event.displayLabel,
                    status: ExecutionStepStatus.completed,
                    summary: event.summary.isEmpty ? 'Done' : event.summary,
                    timestamp: event.occurredAt.toLocal(),
                  ),
        );
      case ToolCallFailedEvent():
        final existing = _executionTraceSteps[event.callId];
        _upsertExecutionStep(
          requestId: event.requestId,
          status: ExecutionTraceStatus.running,
          step:
              (existing ??
                      ExecutionTraceStep(
                        id: event.callId,
                        kind: ExecutionStepKind.tool,
                        title: event.displayLabel,
                        status: ExecutionStepStatus.running,
                        summary: 'Running ${event.toolId}',
                        timestamp: event.occurredAt.toLocal(),
                      ))
                  .copyWith(
                    title: event.displayLabel,
                    status: ExecutionStepStatus.failed,
                    summary: event.summary.isEmpty
                        ? 'This step could not finish.'
                        : event.summary,
                    timestamp: event.occurredAt.toLocal(),
                  ),
        );
        _setStatus(ChatSessionStatus.toolRouting);
      case ApprovalRequiredEvent():
        _upsertExecutionStep(
          requestId: event.requestId,
          status: ExecutionTraceStatus.running,
          step: ExecutionTraceStep(
            id: event.callId,
            kind: ExecutionStepKind.approval,
            title: event.displayLabel,
            status: ExecutionStepStatus.approvalRequired,
            summary: 'Waiting for approval',
            details: _detailsFromPreview(event.safeArgsPreview),
            timestamp: event.occurredAt.toLocal(),
          ),
        );
        _setStatus(ChatSessionStatus.toolRouting);
      case RunCompletedEvent():
        _terminalExecutionRequestIds.add(event.requestId);
        _setExecutionTraceTerminal(
          requestId: event.requestId,
          status: ExecutionTraceStatus.completed,
          summary: event.reason,
        );
      case RunFailedEvent():
        _terminalExecutionRequestIds.add(event.requestId);
        _setExecutionTraceTerminal(
          requestId: event.requestId,
          status: ExecutionTraceStatus.failed,
          summary: event.reason,
        );
        _setStatus(ChatSessionStatus.failed);
      case RunCancelledEvent():
        _terminalExecutionRequestIds.add(event.requestId);
        _setExecutionTraceTerminal(
          requestId: event.requestId,
          status: ExecutionTraceStatus.interrupted,
          summary: event.reason,
        );
        _setStatus(ChatSessionStatus.cancelled);
    }
  }

  void _applyTokenDeltaEvent(TokenDeltaEvent event) {
    final projection = _projectionsByRequestId[event.requestId]!;
    final messageId = event.messageId;
    _runtimeMessageIds.add(messageId);
    projection.assistantMessageId = messageId;
    if (!_messages.any((message) => message.id == messageId)) {
      _upsertMessage(
        ChatTranscriptMessage(
          id: messageId,
          sender: ChatMessageSender.assistant,
          text: event.delta,
          timestamp: event.occurredAt.toLocal(),
          isStreaming: true,
        ),
      );
    } else {
      _replaceMessage(
        messageId,
        (message) => message.copyWith(
          text: '${message.text}${event.delta}',
          isStreaming: true,
        ),
      );
    }
    _setStatus(ChatSessionStatus.streaming);
  }

  void _upsertExecutionStep({
    required String requestId,
    required ExecutionTraceStatus status,
    required ExecutionTraceStep step,
  }) {
    _executionTraceSteps[step.id] = step;
    _executionTrace = ExecutionTrace(
      requestId: requestId,
      status: status,
      steps: List<ExecutionTraceStep>.unmodifiable(_executionTraceSteps.values),
      summary: _executionTrace?.summary,
    );
    notifyListeners();
  }

  void _setExecutionTraceTerminal({
    required String requestId,
    required ExecutionTraceStatus status,
    required String summary,
  }) {
    final currentSteps = _executionTraceSteps.map((id, step) {
      if (step.status == ExecutionStepStatus.running &&
          status == ExecutionTraceStatus.interrupted) {
        return MapEntry(
          id,
          step.copyWith(
            status: ExecutionStepStatus.failed,
            summary: 'Interrupted before completion',
          ),
        );
      }
      return MapEntry(id, step);
    });
    _executionTraceSteps
      ..clear()
      ..addAll(currentSteps);
    _executionTrace = ExecutionTrace(
      requestId: requestId,
      status: status,
      steps: List<ExecutionTraceStep>.unmodifiable(_executionTraceSteps.values),
      summary: summary.trim().isEmpty ? null : summary.trim(),
    );
    notifyListeners();
  }

  Future<void> _finalizeRuntimeMessage(
    RuntimeTranscriptEvent event, {
    required bool failed,
  }) async {
    final projection = _projectionsByRequestId[event.requestId]!;
    final messageId = event.messageId ?? '${event.requestId}-assistant';
    final normalizedText = (event.finalText ?? '').trim();
    if (_isInternalOnlyText(normalizedText)) {
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

  bool _acceptExecutionSequence(
    _RuntimeRequestProjection projection,
    int sequence,
  ) {
    final last = projection.lastExecutionSequence;
    if (last != null && sequence <= last) {
      return false;
    }
    projection.lastExecutionSequence = sequence;
    return true;
  }

  List<ExecutionTraceDetail> _detailsFromPreview(
    List<ToolArgumentPreview> preview,
  ) {
    return preview
        .map(
          (arg) =>
              ExecutionTraceDetail(name: arg.name, value: arg.displayValue),
        )
        .toList(growable: false);
  }

  ExecutionStepStatus _stepStatusForRuntimeStatus(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'completed' ||
        normalized == 'complete' ||
        normalized == 'success' ||
        normalized == 'done') {
      return ExecutionStepStatus.completed;
    }
    if (normalized == 'failed' || normalized == 'error') {
      return ExecutionStepStatus.failed;
    }
    return ExecutionStepStatus.running;
  }

  String _sentenceCaseStatus(String status) {
    final trimmed = status.trim();
    if (trimmed.isEmpty) {
      return 'Updated';
    }
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
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
    if (result.reason == 'malformed_tool_call') {
      final responseText = _normalizeResponse(result);
      if (responseText.trim().isNotEmpty &&
          !_isInternalOnlyText(responseText)) {
        return false;
      }
      return true;
    }
    if (result.reason == 'post_tool_completion_missing') {
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
      composerCapabilityResolver: _composerCapabilityResolver,
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
        if (_isInternalOnlyText(message.text)) {
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
