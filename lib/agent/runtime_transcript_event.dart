import 'package:openreef/agent/agent_models.dart';

enum RuntimeTranscriptEventKind {
  assistantMessageStarted,
  assistantMessageDelta,
  assistantMessageFinalized,
  assistantMessageFailed,
  toolStepStarted,
  toolStepUpdated,
  toolStepFinished,
}

class RuntimeTranscriptEvent {
  const RuntimeTranscriptEvent({
    required this.kind,
    required this.requestId,
    required this.sessionKey,
    required this.sequence,
    required this.occurredAt,
    this.messageId,
    this.stepId,
    this.toolCallId,
    this.toolId,
    this.deltaText,
    this.finalText,
    this.status,
    this.summary,
    this.toolResult,
  });

  final RuntimeTranscriptEventKind kind;
  final String requestId;
  final String sessionKey;
  final int sequence;
  final DateTime occurredAt;
  final String? messageId;
  final String? stepId;
  final String? toolCallId;
  final String? toolId;
  final String? deltaText;
  final String? finalText;
  final String? status;
  final String? summary;
  final ToolResult? toolResult;

  RuntimeTranscriptEvent copyWith({
    RuntimeTranscriptEventKind? kind,
    String? requestId,
    String? sessionKey,
    int? sequence,
    DateTime? occurredAt,
    String? messageId,
    String? stepId,
    String? toolCallId,
    String? toolId,
    String? deltaText,
    String? finalText,
    String? status,
    String? summary,
    ToolResult? toolResult,
  }) {
    return RuntimeTranscriptEvent(
      kind: kind ?? this.kind,
      requestId: requestId ?? this.requestId,
      sessionKey: sessionKey ?? this.sessionKey,
      sequence: sequence ?? this.sequence,
      occurredAt: occurredAt ?? this.occurredAt,
      messageId: messageId ?? this.messageId,
      stepId: stepId ?? this.stepId,
      toolCallId: toolCallId ?? this.toolCallId,
      toolId: toolId ?? this.toolId,
      deltaText: deltaText ?? this.deltaText,
      finalText: finalText ?? this.finalText,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      toolResult: toolResult ?? this.toolResult,
    );
  }
}

abstract class RuntimeTranscriptSink {
  Future<void> applyRuntimeTranscriptEvent(RuntimeTranscriptEvent event);
}

class RuntimeTranscriptEmitter {
  RuntimeTranscriptEmitter({
    required this.requestId,
    required this.sessionKey,
    RuntimeTranscriptSink? sink,
    DateTime Function()? clock,
  }) : _sink = sink,
       _clock = clock ?? DateTime.now;

  final String requestId;
  final String sessionKey;
  final RuntimeTranscriptSink? _sink;
  final DateTime Function() _clock;
  var _sequence = 0;

  bool get hasSink => _sink != null;

  Future<void> emit({
    required RuntimeTranscriptEventKind kind,
    String? messageId,
    String? stepId,
    String? toolCallId,
    String? toolId,
    String? deltaText,
    String? finalText,
    String? status,
    String? summary,
    ToolResult? toolResult,
  }) async {
    final sink = _sink;
    if (sink == null) {
      return;
    }
    await sink.applyRuntimeTranscriptEvent(
      RuntimeTranscriptEvent(
        kind: kind,
        requestId: requestId,
        sessionKey: sessionKey,
        sequence: _sequence++,
        occurredAt: _clock().toUtc(),
        messageId: messageId,
        stepId: stepId,
        toolCallId: toolCallId,
        toolId: toolId,
        deltaText: deltaText,
        finalText: finalText,
        status: status,
        summary: summary,
        toolResult: toolResult,
      ),
    );
  }
}
