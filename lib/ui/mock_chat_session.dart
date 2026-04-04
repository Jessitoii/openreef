import 'package:flutter/foundation.dart';
import 'package:openreef/ui/chat_session_port.dart';

class MockChatSession extends ChangeNotifier implements ChatSessionPort {
  MockChatSession()
      : _messages = <ChatTranscriptMessage>[
          ChatTranscriptMessage(
            id: 'boot-1',
            sender: ChatMessageSender.system,
            text:
                'OPENREEF READY\nOffline agent shell initialized. AgentLoop bridge is mocked for UI work.',
            timestamp: DateTime.now(),
          ),
        ];

  final List<ChatTranscriptMessage> _messages;
  ChatSessionStatus _status = ChatSessionStatus.idle;
  int _nextId = 0;
  bool _isDisposed = false;

  @override
  List<ChatTranscriptMessage> get messages =>
      List<ChatTranscriptMessage>.unmodifiable(_messages);

  @override
  ChatSessionStatus get status => _status;

  @override
  Future<void> sendMessage(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return;
    }

    _appendMessage(ChatMessageSender.user, trimmed);
    _setStatus(ChatSessionStatus.planning);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    _setStatus(ChatSessionStatus.toolRouting);
    await Future<void>.delayed(const Duration(milliseconds: 550));

    _appendMessage(ChatMessageSender.assistant, _buildMockResponse(trimmed));
    _setStatus(ChatSessionStatus.completed);
    await Future<void>.delayed(const Duration(milliseconds: 180));
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
}
