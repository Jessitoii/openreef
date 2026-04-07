import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:openreef/agent/agent_loop.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/agent_models.dart';
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
      _PendingApprovalEntry.main(
        call: call,
        completer: completer,
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
  })  : presentation = PendingToolApproval(
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

class AgentLoopChatSession extends ChangeNotifier
    implements ChatSessionPort, ChatSessionFactory, ApprovalCapableChatSession {
  AgentLoopChatSession({
    required AgentLoop agentLoop,
    MainAgentApprovalController? approvalController,
    this.sessionKey = 'agent:main',
    List<ChatTranscriptMessage> initialMessages =
        const <ChatTranscriptMessage>[],
  }) : _agentLoop = agentLoop,
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

  final AgentLoop _agentLoop;
  final MainAgentApprovalController? _approvalController;
  final String sessionKey;
  final List<ChatTranscriptMessage> _messages;
  final List<AgentMessage> _conversationHistory = <AgentMessage>[];

  ChatSessionStatus _status = ChatSessionStatus.idle;
  List<SubAgentActivity> _activities = const <SubAgentActivity>[];
  int _nextId = 0;
  bool _isRunning = false;
  bool _isDisposed = false;

  @override
  List<SubAgentActivity> get activities =>
      List<SubAgentActivity>.unmodifiable(_activities);

  @override
  PendingToolApproval? get pendingApproval => _approvalController?.pendingApproval;

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
      final result = await _agentLoop.run(
        trimmed,
        sessionKey: sessionKey,
        conversationHistory: List<AgentMessage>.unmodifiable(
          _conversationHistory,
        ),
      );

      final responseText = _normalizeResponse(result);
      final responseSender = _responseSenderForText(responseText);
      _conversationHistory.add(
        AgentMessage(
          role: AgentMessageRole.assistant,
          content: responseText,
          turnNumber: userTurnNumber,
        ),
      );
      _appendMessage(responseSender, responseText);

      _setActivities(<SubAgentActivity>[
        SubAgentActivity(
          id: 'agent-loop',
          label: 'agent.loop',
          summary: _activitySummaryForResult(result, responseText),
          details: <String>[
            'Result: ${result.sessionResult.name}',
            if (responseText.isNotEmpty)
              'Response length: ${responseText.length} chars',
          ],
          status: _isProtectivePauseMessage(responseText)
              ? SubAgentActivityStatus.completed
              : result.sessionResult == SessionResult.completed
                  ? SubAgentActivityStatus.completed
                  : SubAgentActivityStatus.failed,
        ),
      ]);
      _setStatus(ChatSessionStatus.completed);
    } catch (error) {
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
      _setStatus(ChatSessionStatus.completed);
    } finally {
      _isRunning = false;
    }
  }

  String _normalizeResponse(AgentLoopResult result) {
    if (result.text.trim().isNotEmpty) {
      return result.text.trim();
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
      return switch (result.reason) {
        'compaction_failure' =>
          'The agent turn failed while compacting context.',
        'generation_failure' =>
          'The agent turn failed during model generation.',
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

  String _activitySummaryForResult(
    AgentLoopResult result,
    String responseText,
  ) {
    if (_isProtectivePauseMessage(responseText)) {
      return 'Generation paused to protect the device from low-memory crashes.';
    }
    return switch (result.sessionResult) {
      SessionResult.completed => 'Agent loop completed successfully.',
      SessionResult.frozen => 'Agent loop entered a protected frozen state.',
      SessionResult.failed => 'Agent loop ended with a runtime failure.',
    };
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
  void dispose() {
    _isDisposed = true;
    _approvalController?.removeListener(_handleApprovalChanged);
    super.dispose();
  }

  @override
  ChatSessionPort createSession({
    required String sessionId,
    List<ChatTranscriptMessage> initialMessages =
        const <ChatTranscriptMessage>[],
  }) {
    return AgentLoopChatSession(
      agentLoop: _agentLoop,
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
