enum ChatMessageSender { user, assistant, system }

enum ChatSessionStatus {
  idle,
  planning,
  toolRouting,
  completed,
}

class ChatTranscriptMessage {
  const ChatTranscriptMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
  });

  final String id;
  final ChatMessageSender sender;
  final String text;
  final DateTime timestamp;
}

abstract class ChatSessionPort {
  List<ChatTranscriptMessage> get messages;
  ChatSessionStatus get status;

  Future<void> sendMessage(String message);
}
