import 'package:flutter/foundation.dart';
import 'package:openreef/ui/chat_session_port.dart';

class MockChatSession extends ChangeNotifier
    implements ChatSessionPort, ChatSessionFactory {
  MockChatSession({
    String? sessionId,
    List<ChatTranscriptMessage> initialMessages = const <ChatTranscriptMessage>[],
  }) : sessionId = sessionId ?? 'mock:main',
       _messages = initialMessages.isEmpty
           ? <ChatTranscriptMessage>[
               ChatTranscriptMessage(
                 id: 'boot-1',
                 sender: ChatMessageSender.system,
                 text:
                     'OPENREEF READY\nOffline agent shell initialized. AgentLoop bridge is mocked for UI work.',
                 timestamp: DateTime.now(),
               ),
             ]
           : List<ChatTranscriptMessage>.from(initialMessages),
       _activities = const <SubAgentActivity>[];

  final String sessionId;

  final List<ChatTranscriptMessage> _messages;
  List<SubAgentActivity> _activities;
  ChatSessionStatus _status = ChatSessionStatus.idle;
  int _nextId = 0;
  bool _isDisposed = false;

  @override
  List<ChatTranscriptMessage> get messages =>
      List<ChatTranscriptMessage>.unmodifiable(_messages);

  @override
  ChatSessionStatus get status => _status;

  @override
  List<SubAgentActivity> get activities =>
      List<SubAgentActivity>.unmodifiable(_activities);

  @override
  Future<void> sendMessage(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return;
    }

    _appendMessage(ChatMessageSender.user, trimmed);
    _setStatus(ChatSessionStatus.planning);
    _setActivities(_buildPlanningActivities(trimmed));
    await Future<void>.delayed(const Duration(milliseconds: 450));
    _setStatus(ChatSessionStatus.toolRouting);
    _setActivities(_buildRoutingActivities(trimmed));
    await Future<void>.delayed(const Duration(milliseconds: 550));

    final assistantId = 'msg-${_nextId++}';
    _messages.add(
      ChatTranscriptMessage(
        id: assistantId,
        sender: ChatMessageSender.assistant,
        text: '',
        timestamp: DateTime.now(),
        isStreaming: true,
      ),
    );
    notifyListeners();

    _setStatus(ChatSessionStatus.streaming);
    _setActivities(_buildStreamingActivities(trimmed));
    await _streamAssistantResponse(
      assistantId: assistantId,
      response: _buildMockResponse(trimmed),
    );
    _setActivities(_buildCompletedActivities(trimmed));
    _setStatus(ChatSessionStatus.completed);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    _setActivities(const <SubAgentActivity>[]);
    _setStatus(ChatSessionStatus.idle);
  }

  String _buildMockResponse(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('voice')) {
      return 'Voice settings are available in the settings panel. Wake word and TTS are mocked but wired for future agent tools.';
    }
    if (lower.contains('theme')) {
      return 'Theme changes are live. The UI currently supports dark, light, and system mode from the settings registry.';
    }
    return 'Mock AgentLoop reply: received "$prompt". UI contract is ready for a future real session adapter.';
  }

  List<SubAgentActivity> _buildPlanningActivities(String prompt) {
    return <SubAgentActivity>[
      SubAgentActivity(
        id: 'planner',
        label: 'planner.daemon',
        summary: 'Interpreting user intent and mapping terminal session goals.',
        details: <String>[
          'Input classified as offline chat request.',
          'Prompt fingerprint: ${prompt.length} chars / JetBrains console mode.',
        ],
        status: SubAgentActivityStatus.running,
      ),
      const SubAgentActivity(
        id: 'memory',
        label: 'memory.index',
        summary: 'Checking whether local memory context should be prefetched.',
        details: <String>[
          'Mock memory retrieval only. No durable writes triggered.',
          'Context handoff will stay inside the UI seam for now.',
        ],
        status: SubAgentActivityStatus.running,
      ),
    ];
  }

  List<SubAgentActivity> _buildRoutingActivities(String prompt) {
    return <SubAgentActivity>[
      const SubAgentActivity(
        id: 'planner',
        label: 'planner.daemon',
        summary: 'Intent normalized. Session is ready for mock tool routing.',
        details: <String>[
          'Result: conversational response path selected.',
          'No real AgentLoop or tool dispatch invoked.',
        ],
        status: SubAgentActivityStatus.completed,
      ),
      SubAgentActivity(
        id: 'router',
        label: 'router.bridge',
        summary: 'Simulating tool and skill selection for "$prompt".',
        details: const <String>[
          'Mock tool shortlist: settings_read, memory_search, notify.',
          'Sub-agent handoff remains visual only in this UI pass.',
        ],
        status: SubAgentActivityStatus.running,
      ),
    ];
  }

  List<SubAgentActivity> _buildStreamingActivities(String prompt) {
    return <SubAgentActivity>[
      const SubAgentActivity(
        id: 'router',
        label: 'router.bridge',
        summary: 'Routing complete. Assistant stream is opening.',
        details: <String>[
          'Response channel switched to token-style incremental output.',
          'Activity block remains visible until the stream finishes.',
        ],
        status: SubAgentActivityStatus.completed,
      ),
      SubAgentActivity(
        id: 'stream',
        label: 'stream.console',
        summary: 'Streaming response frames for "$prompt".',
        details: const <String>[
          'Chunk size tuned for terminal readability.',
          'Cursor remains active until the final token lands.',
        ],
        status: SubAgentActivityStatus.running,
      ),
    ];
  }

  List<SubAgentActivity> _buildCompletedActivities(String prompt) {
    return <SubAgentActivity>[
      const SubAgentActivity(
        id: 'router',
        label: 'router.bridge',
        summary: 'Route resolved successfully.',
        details: <String>[
          'Future AgentLoop adapter can replace this mock step.',
          'No domain logic currently crosses into the UI layer.',
        ],
        status: SubAgentActivityStatus.completed,
      ),
      SubAgentActivity(
        id: 'stream',
        label: 'stream.console',
        summary: 'Streaming complete for "$prompt".',
        details: const <String>[
          'Transcript committed to the local chat view.',
          'Session returned to idle after visual confirmation.',
        ],
        status: SubAgentActivityStatus.completed,
      ),
    ];
  }

  Future<void> _streamAssistantResponse({
    required String assistantId,
    required String response,
  }) async {
    var index = 0;
    const chunkSize = 4;
    while (!_isDisposed && index < response.length) {
      final nextIndex = (index + chunkSize).clamp(0, response.length);
      _replaceMessage(
        assistantId,
        (message) => message.copyWith(
          text: response.substring(0, nextIndex),
          isStreaming: nextIndex < response.length,
        ),
      );
      index = nextIndex;
      await Future<void>.delayed(const Duration(milliseconds: 32));
    }
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
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  ChatSessionPort createSession({
    required String sessionId,
    List<ChatTranscriptMessage> initialMessages = const <ChatTranscriptMessage>[],
  }) {
    return MockChatSession(
      sessionId: sessionId,
      initialMessages: initialMessages,
    );
  }
}
