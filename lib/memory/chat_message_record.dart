import 'package:openreef/ui/chat_session_port.dart';

class ChatMessageRecord {
  const ChatMessageRecord({
    required this.id,
    required this.sessionId,
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.position,
    required this.isStreaming,
  });

  final String id;
  final String sessionId;
  final ChatMessageSender sender;
  final String text;
  final DateTime timestamp;
  final int position;
  final bool isStreaming;

  Map<String, Object?> toDatabaseMap() {
    return <String, Object?>{
      'id': id,
      'session_id': sessionId,
      'sender': sender.name,
      'text': text,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'position': position,
      'is_streaming': isStreaming ? 1 : 0,
    };
  }

  ChatTranscriptMessage toTranscriptMessage() {
    return ChatTranscriptMessage(
      id: id,
      sender: sender,
      text: text,
      timestamp: timestamp,
      isStreaming: isStreaming,
    );
  }

  factory ChatMessageRecord.fromTranscriptMessage({
    required String sessionId,
    required int position,
    required ChatTranscriptMessage message,
  }) {
    return ChatMessageRecord(
      id: message.id,
      sessionId: sessionId,
      sender: message.sender,
      text: message.text,
      timestamp: message.timestamp,
      position: position,
      isStreaming: message.isStreaming,
    );
  }

  factory ChatMessageRecord.fromDatabaseMap(Map<String, Object?> map) {
    return ChatMessageRecord(
      id: map['id']! as String,
      sessionId: map['session_id']! as String,
      sender: ChatMessageSender.values.byName(map['sender']! as String),
      text: map['text']! as String,
      timestamp: DateTime.parse(map['timestamp']! as String).toLocal(),
      position: map['position']! as int,
      isStreaming: (map['is_streaming']! as int) == 1,
    );
  }
}
