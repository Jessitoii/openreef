import 'package:flutter/foundation.dart';
import 'package:openreef/agent/agent_loop.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/ui/chat_session_port.dart';

class AgentLoopChatSession extends ChangeNotifier
    implements ChatSessionPort, ChatSessionFactory {
  AgentLoopChatSession({
    required AgentLoop agentLoop,
    this.sessionKey = 'agent:main',
    List<ChatTranscriptMessage> initialMessages = const <ChatTranscriptMessage>[],
  }) : _agentLoop = agentLoop,
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
    _conversationHistory.addAll(_buildConversationHistory(_messages));
    _nextId = _deriveNextId(_messages);
  }

  final AgentLoop _agentLoop;
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
  List<ChatTranscriptMessage> get messages =>
      List<ChatTranscriptMessage>.unmodifiable(_messages);

  @override
  ChatSessionStatus get status => _status;

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
      _conversationHistory.add(
        AgentMessage(
          role: AgentMessageRole.assistant,
          content: responseText,
          turnNumber: userTurnNumber,
        ),
      );
      _appendMessage(ChatMessageSender.assistant, responseText);

      _setActivities(<SubAgentActivity>[
        SubAgentActivity(
          id: 'agent-loop',
          label: 'agent.loop',
          summary: result.sessionResult == SessionResult.completed
              ? 'Agent loop completed successfully.'
              : 'Agent loop entered a protected frozen state.',
          details: <String>[
            'Result: ${result.sessionResult.name}',
            if (responseText.isNotEmpty)
              'Response length: ${responseText.length} chars',
          ],
          status: result.sessionResult == SessionResult.completed
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
      return 'The agent session was frozen after repeated execution errors.';
    }
    return 'LiteRT completed the turn but returned no visible text.';
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
    super.dispose();
  }

  @override
  ChatSessionPort createSession({
    required String sessionId,
    List<ChatTranscriptMessage> initialMessages = const <ChatTranscriptMessage>[],
  }) {
    return AgentLoopChatSession(
      agentLoop: _agentLoop,
      sessionKey: sessionId,
      initialMessages: initialMessages,
    );
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
