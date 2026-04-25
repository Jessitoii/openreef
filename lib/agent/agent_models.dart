import 'dart:convert';

import 'package:flutter/foundation.dart';

enum ToolCallSource { textParsed, flutterGemmaTyped }

enum AgentResponseParserStatus { visibleText, toolCall, protocolFailure }

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
    this.rawArguments,
    this.hasRawArguments = false,
    this.source = ToolCallSource.textParsed,
  });

  final String id;
  final String toolId;
  final Map<String, Object?> arguments;
  final Object? rawArguments;
  final bool hasRawArguments;
  final ToolCallSource source;

  factory ToolCall.fromMap(Map<String, Object?> map) {
    final hasArguments =
        map.containsKey('arguments') || map.containsKey('args');
    final rawArguments = map.containsKey('arguments')
        ? map['arguments']
        : map.containsKey('args')
        ? map['args']
        : map.containsKey('parameters')
        ? <String, Object?>{'parameters': map['parameters']}
        : null;
    return ToolCall(
      id: map['id'] as String? ?? 'tool_call',
      toolId:
          map['toolId'] as String? ??
          map['tool_id'] as String? ??
          map['name'] as String? ??
          '',
      arguments: rawArguments is Map<String, Object?>
          ? rawArguments
          : rawArguments is Map
          ? Map<String, Object?>.from(rawArguments)
          : const <String, Object?>{},
      rawArguments: rawArguments,
      hasRawArguments: hasArguments || map.containsKey('parameters'),
      source: ToolCallSource.textParsed,
    );
  }

  ToolCall withSource(ToolCallSource source) {
    if (this.source == source) {
      return this;
    }
    return ToolCall(
      id: id,
      toolId: toolId,
      arguments: arguments,
      rawArguments: rawArguments,
      hasRawArguments: hasRawArguments,
      source: source,
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

class NormalizedToolRequest {
  const NormalizedToolRequest({
    required this.callId,
    required this.toolId,
    required this.normalizedArgs,
    required this.requiresConfirmation,
    required this.sessionKey,
    required this.source,
  });

  final String callId;
  final String toolId;
  final Map<String, Object?> normalizedArgs;
  final bool requiresConfirmation;
  final String sessionKey;
  final ToolCallSource source;

  ToolCall toToolCall() {
    return ToolCall(
      id: callId,
      toolId: toolId,
      arguments: normalizedArgs,
      rawArguments: normalizedArgs,
      hasRawArguments: true,
      source: source,
    );
  }
}

enum ToolResultStatus {
  success,
  rejected,
  validationError,
  permissionDenied,
  unavailable,
  timeout,
  executionError,
  cancelled,
}

class ToolResult {
  const ToolResult({
    required this.status,
    required this.summary,
    this.toolId,
    this.callId,
    this.payload = const <String, Object?>{},
    this.retryable = false,
    this.userVisibleMessage,
    this.metadata = const <String, Object?>{},
  });

  const ToolResult.success(
    String content, {
    String? toolId,
    String? callId,
    Map<String, Object?> payload = const <String, Object?>{},
    String? userVisibleMessage,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status: ToolResultStatus.success,
         summary: content,
         toolId: toolId,
         callId: callId,
         payload: payload,
         userVisibleMessage: userVisibleMessage,
         metadata: metadata,
       );

  const ToolResult.rejected({
    String summary = 'rejected',
    String? toolId,
    String? callId,
    Map<String, Object?> payload = const <String, Object?>{},
    String? userVisibleMessage,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status: ToolResultStatus.rejected,
         summary: summary,
         toolId: toolId,
         callId: callId,
         payload: payload,
         userVisibleMessage: userVisibleMessage,
         metadata: metadata,
       );

  const ToolResult.failure(
    String content, {
    String? toolId,
    String? callId,
    ToolResultStatus status = ToolResultStatus.executionError,
    Map<String, Object?> payload = const <String, Object?>{},
    bool retryable = false,
    String? userVisibleMessage,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status: status,
         summary: content,
         toolId: toolId,
         callId: callId,
         payload: payload,
         retryable: retryable,
         userVisibleMessage: userVisibleMessage,
         metadata: metadata,
       );

  final String? toolId;
  final String? callId;
  final ToolResultStatus status;
  final String summary;
  final Map<String, Object?> payload;
  final bool retryable;
  final String? userVisibleMessage;
  final Map<String, Object?> metadata;

  String get content => summary;
  bool get isRejected => status == ToolResultStatus.rejected;
  bool get isFailure => status != ToolResultStatus.success && !isRejected;
  bool get isError => status != ToolResultStatus.success;
  String get statusName => _statusToWire(status);

  ToolResult withCall(ToolCall call) {
    return ToolResult(
      status: status,
      summary: summary,
      toolId: toolId ?? call.toolId,
      callId: callId ?? call.id,
      payload: payload,
      retryable: retryable,
      userVisibleMessage: userVisibleMessage,
      metadata: metadata,
    );
  }

  String toContextString() {
    final buffer = StringBuffer()
      ..writeln('toolId: ${toolId ?? 'unknown'}')
      ..writeln('callId: ${callId ?? 'unknown'}')
      ..writeln('status: $statusName')
      ..write('summary: ${userVisibleMessage ?? summary}');
    if (isError) {
      final reason =
          metadata['reason'] ??
          metadata['errorCode'] ??
          metadata['outcome_reason'];
      if (reason != null) {
        buffer.write('\nreason: $reason');
      }
    }
    return buffer.toString();
  }

  factory ToolResult.fromMap(Map<String, Object?> map) {
    final rawMetadata = map['metadata'];
    final rawPayload = map['payload'] ?? map['structuredPayload'];
    final fallbackContent = map['content'] as String?;
    final parsedStatus = _statusFromWire(map['status']);
    final metadata = _mapOrEmpty(rawMetadata);
    final normalizedMetadata = _isKnownStatusWire(map['status'])
        ? metadata
        : <String, Object?>{
            ...metadata,
            'reason': 'invalid_status',
            'errorCode': 'invalid_status',
            'rawStatus': map['status']?.toString(),
          };
    return ToolResult(
      toolId: map['toolId'] as String? ?? map['tool_id'] as String?,
      callId: map['callId'] as String? ?? map['call_id'] as String?,
      status: parsedStatus,
      summary: map['summary'] as String? ?? fallbackContent ?? '',
      payload: _mapOrEmpty(rawPayload),
      retryable: map['retryable'] as bool? ?? false,
      userVisibleMessage:
          map['userVisibleMessage'] as String? ??
          map['user_visible_message'] as String?,
      metadata: normalizedMetadata,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'toolId': toolId,
      'callId': callId,
      'status': statusName,
      'summary': summary,
      'content': content,
      'payload': payload,
      'retryable': retryable,
      'userVisibleMessage': userVisibleMessage,
      'metadata': metadata,
    };
  }

  static Map<String, Object?> _mapOrEmpty(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    return const <String, Object?>{};
  }

  static ToolResultStatus _statusFromWire(Object? status) {
    return switch (status) {
      'rejected' => ToolResultStatus.rejected,
      'validation_error' => ToolResultStatus.validationError,
      'permission_denied' ||
      'blocked_by_policy' => ToolResultStatus.permissionDenied,
      'unavailable' => ToolResultStatus.unavailable,
      'timeout' => ToolResultStatus.timeout,
      'execution_error' || 'failure' => ToolResultStatus.executionError,
      'cancelled' => ToolResultStatus.cancelled,
      null => ToolResultStatus.executionError,
      _ => ToolResultStatus.executionError,
    };
  }

  static bool _isKnownStatusWire(Object? status) {
    return status == 'success' ||
        status == 'rejected' ||
        status == 'validation_error' ||
        status == 'permission_denied' ||
        status == 'blocked_by_policy' ||
        status == 'unavailable' ||
        status == 'timeout' ||
        status == 'execution_error' ||
        status == 'failure' ||
        status == 'cancelled';
  }

  static String _statusToWire(ToolResultStatus status) {
    return switch (status) {
      ToolResultStatus.success => 'success',
      ToolResultStatus.rejected => 'rejected',
      ToolResultStatus.validationError => 'validation_error',
      ToolResultStatus.permissionDenied => 'permission_denied',
      ToolResultStatus.unavailable => 'unavailable',
      ToolResultStatus.timeout => 'timeout',
      ToolResultStatus.executionError => 'execution_error',
      ToolResultStatus.cancelled => 'cancelled',
    };
  }
}

class AgentResponse {
  const AgentResponse({
    required this.text,
    this.toolCall,
    this.toolCalls = const <ToolCall>[],
    this.toolCallSource = ToolCallSource.textParsed,
    this.rawOutput,
    this.parserStatus = AgentResponseParserStatus.visibleText,
    this.parserError,
  });

  final String text;
  final ToolCall? toolCall;
  final List<ToolCall> toolCalls;
  final ToolCallSource toolCallSource;
  final String? rawOutput;
  final AgentResponseParserStatus parserStatus;
  final String? parserError;

  bool get hasToolCall => effectiveToolCalls.isNotEmpty;
  bool get hasTypedToolCall =>
      toolCallSource == ToolCallSource.flutterGemmaTyped;
  bool get hasParserFailure =>
      parserStatus == AgentResponseParserStatus.protocolFailure;

  List<ToolCall> get effectiveToolCalls {
    final first = toolCall;
    late final List<ToolCall> calls;
    if (first == null) {
      calls = toolCalls;
    } else if (toolCalls.isEmpty) {
      calls = <ToolCall>[first];
    } else if (identical(toolCalls.first, first) ||
        toolCalls.first.id == first.id) {
      calls = toolCalls;
    } else {
      calls = <ToolCall>[first, ...toolCalls];
    }
    if (toolCallSource == ToolCallSource.textParsed) {
      return calls;
    }
    return calls
        .map((call) => call.withSource(toolCallSource))
        .toList(growable: false);
  }
}

class CancellationSignal {
  var _isCancelled = false;
  String? _reason;

  bool get isCancelled => _isCancelled;

  String? get reason => _reason;

  void cancel([String reason = 'cancelled']) {
    _isCancelled = true;
    _reason = reason;
  }
}

class LoopControl {
  const LoopControl({
    this.maxSteps = 12,
    this.maxToolCalls = 8,
    this.timeout = const Duration(seconds: 30),
    this.cancellationSignal,
  });

  final int maxSteps;
  final int maxToolCalls;
  final Duration timeout;
  final CancellationSignal? cancellationSignal;
}

class LoopContinuation {
  const LoopContinuation({
    this.currentStepIndex = 0,
    this.variables = const <String, Object?>{},
    this.waitingReason,
    this.waitingMetadata = const <String, Object?>{},
    this.resumeToken,
  });

  final int currentStepIndex;
  final Map<String, Object?> variables;
  final String? waitingReason;
  final Map<String, Object?> waitingMetadata;
  final String? resumeToken;

  Map<String, Object?> toMetadata() {
    return <String, Object?>{
      'currentStepIndex': currentStepIndex,
      'variables': variables,
      if (waitingReason != null) 'waitingReason': waitingReason,
      if (waitingMetadata.isNotEmpty) 'waitingMetadata': waitingMetadata,
      if (resumeToken != null) 'resumeToken': resumeToken,
    };
  }
}

enum SessionResult { completed, frozen, failed, cancelled, suspended }

class AgentLoopResult {
  const AgentLoopResult({
    required this.sessionResult,
    required this.text,
    this.reason,
    this.toolsUsed = const <String>[],
    this.toolResults = const <ToolResult>[],
    this.stepCount = 0,
    this.toolCallCount = 0,
    this.continuation = const LoopContinuation(),
    this.exceptionType,
    this.errorMessage,
  });

  final SessionResult sessionResult;
  final String text;
  final String? reason;
  final List<String> toolsUsed;
  final List<ToolResult> toolResults;
  final int stepCount;
  final int toolCallCount;
  final LoopContinuation continuation;
  final String? exceptionType;
  final String? errorMessage;

  String? get failureReason {
    if (sessionResult == SessionResult.completed) {
      return null;
    }
    return reason;
  }
}

class AgentResponseParser {
  const AgentResponseParser();

  AgentResponse parse(String output) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) {
      return AgentResponse(text: '', rawOutput: output);
    }

    if (_containsProtocolToken(trimmed)) {
      final markerToolCall = _parseToolCallMarker(trimmed);
      if (markerToolCall == null) {
        return _protocolFailure(output, 'malformed_tool_call');
      }
      return AgentResponse(
        text: '',
        toolCall: markerToolCall,
        rawOutput: output,
        parserStatus: AgentResponseParserStatus.toolCall,
      );
    }

    final decoded = _tryDecodeObject(trimmed);
    if (decoded != null) {
      if (_hasStructuredToolFields(decoded)) {
        final toolCall = _parseToolCall(decoded);
        final toolCalls = _parseToolCalls(decoded);
        if (toolCall == null && toolCalls.isEmpty) {
          return _protocolFailure(output, 'malformed_tool_call');
        }
        return AgentResponse(
          text: '',
          toolCall: toolCall,
          toolCalls: toolCalls,
          rawOutput: output,
          parserStatus: AgentResponseParserStatus.toolCall,
        );
      }
      return AgentResponse(
        text: decoded['text'] as String? ?? '',
        rawOutput: output,
      );
    }
    // Diagnostic fallback: If the model generated pre-text before the json, standard tryDecodeObject will fail.
    // We regex look for `{ "tool_call": ... }` or `{ "tool_calls": ... }` inside the text.
    final embedded = _extractEmbeddedJson(trimmed);
    if (embedded != null) {
      debugPrint(
        'DIAGNOSTIC: AgentResponseParser fallback extraction succeeded from markdown/prose.',
      );
      final toolCall = _parseToolCall(embedded.payload);
      final toolCalls = _parseToolCalls(embedded.payload);
      if (toolCall == null && toolCalls.isEmpty) {
        return _protocolFailure(output, 'malformed_tool_call');
      }
      return AgentResponse(
        text: '',
        toolCall: toolCall,
        toolCalls: toolCalls,
        rawOutput: output,
        parserStatus: AgentResponseParserStatus.toolCall,
      );
    }
    if (_looksLikeStructuredToolOutput(trimmed)) {
      return _protocolFailure(output, 'malformed_tool_call');
    }

    return AgentResponse(text: trimmed, rawOutput: output);
  }

  ToolCall? _parseToolCallMarker(String content) {
    final match = RegExp(
      r'^<\|tool_call\>call:([A-Za-z0-9_.-]+)(.*)<tool_call\|>$',
      dotAll: true,
    ).firstMatch(content);
    if (match == null) {
      return null;
    }
    final toolId = match.group(1) ?? '';
    final rawArgs = (match.group(2) ?? '').trim();
    Object? decodedArgs;
    try {
      decodedArgs = rawArgs.isEmpty ? <String, Object?>{} : jsonDecode(rawArgs);
    } on FormatException {
      return null;
    }
    if (decodedArgs is! Map<String, Object?> && decodedArgs is! Map) {
      return null;
    }
    return ToolCall(
      id: 'tool_call_marker',
      toolId: toolId,
      arguments: decodedArgs is Map<String, Object?>
          ? decodedArgs
          : decodedArgs is Map
          ? Map<String, Object?>.from(decodedArgs)
          : const <String, Object?>{},
      rawArguments: decodedArgs,
      hasRawArguments: true,
    );
  }

  bool _containsProtocolToken(String content) {
    return content.contains('<|tool_call>') ||
        content.contains('<tool_call|>') ||
        content.contains('<|assistant|>') ||
        content.contains('<|user|>') ||
        content.contains('<|system|>') ||
        content.contains('<|tool|>');
  }

  bool _looksLikeStructuredToolOutput(String content) {
    return content.contains('"tool_call"') ||
        content.contains('"tool_calls"') ||
        content.contains('"toolCall"') ||
        content.contains('"toolCalls"');
  }

  bool _hasStructuredToolFields(Map<String, Object?> decoded) {
    return decoded.containsKey('toolCall') ||
        decoded.containsKey('tool_call') ||
        decoded.containsKey('toolCalls') ||
        decoded.containsKey('tool_calls');
  }

  AgentResponse _protocolFailure(String output, String reason) {
    return AgentResponse(
      text: '',
      rawOutput: output,
      parserStatus: AgentResponseParserStatus.protocolFailure,
      parserError: reason,
    );
  }

  ({String text, Map<String, Object?> payload})? _extractEmbeddedJson(
    String content,
  ) {
    // Regex matches the outer braces if they contain 'tool_call' or 'tool_calls'.
    // `dotAll: true` handles multi-line pretty-printed JSON.
    final match = RegExp(
      r'\{.*"tool_call(s)?".*\}',
      dotAll: true,
    ).firstMatch(content);

    if (match != null) {
      final jsonString = match.group(0)!;
      try {
        final decoded = jsonDecode(jsonString);
        if (decoded is Map<String, Object?>) {
          // Strip the JSON footprint and any markdown blocks to leave the true conversational prose.
          final textPart = content
              .substring(0, match.start)
              .replaceAll(RegExp(r'```json\s*$'), '')
              .trim();
          return (text: textPart, payload: decoded);
        }
        if (decoded is Map) {
          final textPart = content
              .substring(0, match.start)
              .replaceAll(RegExp(r'```json\s*$'), '')
              .trim();
          return (text: textPart, payload: Map<String, Object?>.from(decoded));
        }
      } catch (_) {
        // Ignored: JSON chunk was malformed visually
      }
    }

    return null;
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

  List<ToolCall> _parseToolCalls(Map<String, Object?> decoded) {
    final rawToolCalls = decoded['toolCalls'] ?? decoded['tool_calls'];
    if (rawToolCalls is! List) {
      return const <ToolCall>[];
    }
    return rawToolCalls
        .whereType<Map>()
        .map((entry) => ToolCall.fromMap(Map<String, Object?>.from(entry)))
        .toList(growable: false);
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
