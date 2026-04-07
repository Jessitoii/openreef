import 'dart:convert';

enum AgentMessageRole {
  system,
  user,
  assistant,
  tool,
  toolError,
  summary,
  standingOrder,
  memory,
}

class AgentMessage {
  const AgentMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.turnNumber,
    this.metadata = const <String, Object?>{},
  });

  final AgentMessageRole role;
  final String content;
  final String? toolCallId;
  final int? turnNumber;
  final Map<String, Object?> metadata;

  bool get isToolResult => role == AgentMessageRole.tool;
  bool get isToolError => role == AgentMessageRole.toolError;

  AgentMessage copyWith({
    AgentMessageRole? role,
    String? content,
    String? toolCallId,
    int? turnNumber,
    Map<String, Object?>? metadata,
  }) {
    return AgentMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      toolCallId: toolCallId ?? this.toolCallId,
      turnNumber: turnNumber ?? this.turnNumber,
      metadata: metadata ?? this.metadata,
    );
  }

  String toPromptSegment() {
    final roleName = switch (role) {
      AgentMessageRole.system => 'SYSTEM',
      AgentMessageRole.user => 'USER',
      AgentMessageRole.assistant => 'ASSISTANT',
      AgentMessageRole.tool => 'TOOL',
      AgentMessageRole.toolError => 'TOOL_ERROR',
      AgentMessageRole.summary => 'SUMMARY',
      AgentMessageRole.standingOrder => 'STANDING_ORDER',
      AgentMessageRole.memory => 'MEMORY',
    };

    return '[$roleName] $content';
  }
}

class ToolCall {
  const ToolCall({
    required this.id,
    required this.toolId,
    this.arguments = const <String, Object?>{},
  });

  final String id;
  final String toolId;
  final Map<String, Object?> arguments;

  factory ToolCall.fromMap(Map<String, Object?> map) {
    final rawArguments = map['arguments'] ?? map['args'];
    return ToolCall(
      id: map['id'] as String? ?? 'tool_call',
      toolId: map['toolId'] as String? ?? map['tool_id'] as String? ?? '',
      arguments: rawArguments is Map<String, Object?>
          ? rawArguments
          : rawArguments is Map
              ? Map<String, Object?>.from(rawArguments)
              : const <String, Object?>{},
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'tool_id': toolId,
      'arguments': arguments,
    };
  }
}

enum ToolResultStatus {
  success,
  rejected,
}

class ToolResult {
  const ToolResult({
    required this.status,
    required this.content,
    this.metadata = const <String, Object?>{},
  });

  const ToolResult.success(
    this.content, {
    this.metadata = const <String, Object?>{},
  }) : status = ToolResultStatus.success;

  const ToolResult.rejected({
    this.content = 'rejected',
    this.metadata = const <String, Object?>{},
  }) : status = ToolResultStatus.rejected;

  final ToolResultStatus status;
  final String content;
  final Map<String, Object?> metadata;

  bool get isRejected => status == ToolResultStatus.rejected;

  String toContextString() => content;

  factory ToolResult.fromMap(Map<String, Object?> map) {
    final rawMetadata = map['metadata'];
    return ToolResult(
      status: map['status'] == 'rejected'
          ? ToolResultStatus.rejected
          : ToolResultStatus.success,
      content: map['content'] as String? ?? '',
      metadata: rawMetadata is Map<String, Object?>
          ? rawMetadata
          : rawMetadata is Map
              ? Map<String, Object?>.from(rawMetadata)
              : const <String, Object?>{},
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'status': switch (status) {
        ToolResultStatus.success => 'success',
        ToolResultStatus.rejected => 'rejected',
      },
      'content': content,
      'metadata': metadata,
    };
  }
}

class AgentResponse {
  const AgentResponse({
    required this.text,
    this.toolCall,
    this.rawOutput,
  });

  final String text;
  final ToolCall? toolCall;
  final String? rawOutput;

  bool get hasToolCall => toolCall != null;
}

enum SessionResult {
  completed,
  frozen,
  failed,
}

class AgentLoopResult {
  const AgentLoopResult({
    required this.sessionResult,
    required this.text,
    this.reason,
  });

  final SessionResult sessionResult;
  final String text;
  final String? reason;
}

class AgentResponseParser {
  const AgentResponseParser();

  AgentResponse parse(String output) {
    final trimmed = output.trim();
    final decoded = _tryDecodeObject(trimmed);
    if (decoded != null) {
      return AgentResponse(
        text: decoded['text'] as String? ?? '',
        toolCall: _parseToolCall(decoded),
        rawOutput: output,
      );
    }

    return AgentResponse(
      text: trimmed,
      rawOutput: output,
    );
  }

  ToolCall? _parseToolCall(Map<String, Object?> decoded) {
    final rawToolCall = decoded['toolCall'] ?? decoded['tool_call'];
    if (rawToolCall is Map<String, Object?>) {
      return ToolCall.fromMap(rawToolCall);
    }
    if (rawToolCall is Map) {
      return ToolCall.fromMap(Map<String, Object?>.from(rawToolCall));
    }
    return null;
  }

  Map<String, Object?>? _tryDecodeObject(String output) {
    try {
      final decoded = jsonDecode(output);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } on FormatException {
      return null;
    }

    return null;
  }
}
