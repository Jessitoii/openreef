import 'package:flutter/foundation.dart';

enum ChatMessageSender { user, assistant, system }

enum ChatSessionStatus {
  idle,
  planning,
  toolRouting,
  streaming,
  completed,
}

enum SubAgentActivityStatus {
  running,
  completed,
  failed,
}

class PendingToolApproval {
  const PendingToolApproval({
    required this.toolCallId,
    required this.toolId,
    required this.arguments,
  });

  final String toolCallId;
  final String toolId;
  final Map<String, Object?> arguments;
}

class ChatTranscriptMessage {
  const ChatTranscriptMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.isStreaming = false,
  });

  final String id;
  final ChatMessageSender sender;
  final String text;
  final DateTime timestamp;
  final bool isStreaming;

  ChatTranscriptMessage copyWith({
    String? id,
    ChatMessageSender? sender,
    String? text,
    DateTime? timestamp,
    bool? isStreaming,
  }) {
    return ChatTranscriptMessage(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}

class SubAgentActivity {
  const SubAgentActivity({
    required this.id,
    required this.label,
    required this.summary,
    required this.details,
    required this.status,
  });

  final String id;
  final String label;
  final String summary;
  final List<String> details;
  final SubAgentActivityStatus status;

  SubAgentActivity copyWith({
    String? id,
    String? label,
    String? summary,
    List<String>? details,
    SubAgentActivityStatus? status,
  }) {
    return SubAgentActivity(
      id: id ?? this.id,
      label: label ?? this.label,
      summary: summary ?? this.summary,
      details: details ?? this.details,
      status: status ?? this.status,
    );
  }
}

abstract class ChatSessionPort extends Listenable {
  List<ChatTranscriptMessage> get messages;
  ChatSessionStatus get status;
  List<SubAgentActivity> get activities;

  Future<void> sendMessage(String message);
}

abstract class ChatSessionFactory {
  ChatSessionPort createSession({
    required String sessionId,
    List<ChatTranscriptMessage> initialMessages = const <ChatTranscriptMessage>[],
  });
}

abstract class ApprovalCapableChatSession {
  PendingToolApproval? get pendingApproval;
  void approvePendingApproval();
  void rejectPendingApproval();
}

abstract class SystemAssistantInjectableChatSession {
  void injectSystemAssistantEntry(String text);
}

extension ChatSessionApprovalState on ChatSessionPort {
  PendingToolApproval? get pendingApprovalOrNull =>
      this is ApprovalCapableChatSession
          ? (this as ApprovalCapableChatSession).pendingApproval
          : null;

  void approvePendingApprovalIfSupported() {
    if (this is ApprovalCapableChatSession) {
      (this as ApprovalCapableChatSession).approvePendingApproval();
    }
  }

  void rejectPendingApprovalIfSupported() {
    if (this is ApprovalCapableChatSession) {
      (this as ApprovalCapableChatSession).rejectPendingApproval();
    }
  }

  void injectSystemAssistantEntryIfSupported(String text) {
    if (this is SystemAssistantInjectableChatSession) {
      (this as SystemAssistantInjectableChatSession)
          .injectSystemAssistantEntry(text);
    }
  }
}
