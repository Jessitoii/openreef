import 'package:flutter/foundation.dart';
import 'package:openreef/ui/chat/composer_models.dart';

enum ChatMessageSender { user, assistant, system }

enum ChatSessionStatus {
  idle,
  planning,
  toolRouting,
  streaming,
  completed,
  failed,
  frozen,
  cancelled,
  suspended,
  persistenceFailed,
}

enum SubAgentActivityStatus { running, completed, failed }

enum ExecutionTraceStatus { running, completed, failed, interrupted }

enum ExecutionStepKind { step, tool, approval }

enum ExecutionStepStatus { running, completed, failed, approvalRequired }

class PendingToolApproval {
  const PendingToolApproval({
    required this.toolCallId,
    required this.toolId,
    required this.arguments,
    required this.createdAt,
  });

  final String toolCallId;
  final String toolId;
  final Map<String, Object?> arguments;
  final DateTime createdAt;
}

class ExecutionTraceDetail {
  const ExecutionTraceDetail({required this.name, required this.value});

  final String name;
  final String value;
}

class ExecutionTraceStep {
  const ExecutionTraceStep({
    required this.id,
    required this.kind,
    required this.title,
    required this.status,
    required this.summary,
    this.details = const <ExecutionTraceDetail>[],
    this.timestamp,
  });

  final String id;
  final ExecutionStepKind kind;
  final String title;
  final ExecutionStepStatus status;
  final String summary;
  final List<ExecutionTraceDetail> details;
  final DateTime? timestamp;

  ExecutionTraceStep copyWith({
    String? id,
    ExecutionStepKind? kind,
    String? title,
    ExecutionStepStatus? status,
    String? summary,
    List<ExecutionTraceDetail>? details,
    DateTime? timestamp,
  }) {
    return ExecutionTraceStep(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      details: details ?? this.details,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

class ExecutionTrace {
  const ExecutionTrace({
    required this.requestId,
    required this.status,
    required this.steps,
    this.summary,
  });

  final String requestId;
  final ExecutionTraceStatus status;
  final List<ExecutionTraceStep> steps;
  final String? summary;

  bool get isEmpty => steps.isEmpty && (summary == null || summary!.isEmpty);
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
  Future<void> sendComposerSubmission(ComposerSubmission submission);
}

abstract class ExecutionTraceCapableChatSession {
  ExecutionTrace? get executionTrace;
}

abstract class ChatSessionFactory {
  ChatSessionPort createSession({
    required String sessionId,
    List<ChatTranscriptMessage> initialMessages =
        const <ChatTranscriptMessage>[],
  });
}

class ChatTranscriptPersistenceRequest {
  const ChatTranscriptPersistenceRequest({
    required this.sessionKey,
    required this.requestId,
    required this.terminalStatus,
    required this.messages,
  });

  final String sessionKey;
  final String requestId;
  final ChatSessionStatus terminalStatus;
  final List<ChatTranscriptMessage> messages;
}

class ChatTranscriptPersistenceResult {
  const ChatTranscriptPersistenceResult.success({required this.persistedAt})
    : errorCode = null,
      errorMessage = null;

  const ChatTranscriptPersistenceResult.failure({
    required this.errorCode,
    required this.errorMessage,
  }) : persistedAt = null;

  final DateTime? persistedAt;
  final String? errorCode;
  final String? errorMessage;

  bool get isSuccess => persistedAt != null;
}

abstract class ChatTranscriptPersistencePort {
  Future<ChatTranscriptPersistenceResult> persistTranscriptBeforeTerminal(
    ChatTranscriptPersistenceRequest request,
  );
}

abstract class PersistentChatSession {
  void attachTranscriptPersistencePort(ChatTranscriptPersistencePort port);
}

abstract class ApprovalCapableChatSession {
  PendingToolApproval? get pendingApproval;
  void approvePendingApproval();
  void rejectPendingApproval();
}

abstract class CancellableChatSession {
  Future<bool> cancelActiveRun();
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

  Future<bool> cancelActiveRunIfSupported() {
    if (this is CancellableChatSession) {
      return (this as CancellableChatSession).cancelActiveRun();
    }
    return Future<bool>.value(false);
  }

  void injectSystemAssistantEntryIfSupported(String text) {
    if (this is SystemAssistantInjectableChatSession) {
      (this as SystemAssistantInjectableChatSession).injectSystemAssistantEntry(
        text,
      );
    }
  }
}
