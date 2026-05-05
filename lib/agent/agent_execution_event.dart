import 'package:openreef/agent/agent_models.dart';

sealed class AgentExecutionEvent {
  const AgentExecutionEvent({
    required this.runId,
    required this.sessionId,
    required this.requestId,
    required this.sequence,
    required this.occurredAt,
  });

  final String? runId;
  final String sessionId;
  final String requestId;
  final int sequence;
  final DateTime occurredAt;
}

class TokenDeltaEvent extends AgentExecutionEvent {
  const TokenDeltaEvent({
    required super.runId,
    required super.sessionId,
    required super.requestId,
    required super.sequence,
    required super.occurredAt,
    required this.messageId,
    required this.delta,
  });

  final String messageId;
  final String delta;
}

class StepStartedEvent extends AgentExecutionEvent {
  const StepStartedEvent({
    required super.runId,
    required super.sessionId,
    required super.requestId,
    required super.sequence,
    required super.occurredAt,
    required this.stepId,
    required this.label,
  });

  final String stepId;
  final String label;
}

class StepUpdatedEvent extends AgentExecutionEvent {
  const StepUpdatedEvent({
    required super.runId,
    required super.sessionId,
    required super.requestId,
    required super.sequence,
    required super.occurredAt,
    required this.stepId,
    required this.status,
  });

  final String stepId;
  final String status;
}

class ToolCallStartedEvent extends AgentExecutionEvent {
  const ToolCallStartedEvent({
    required super.runId,
    required super.sessionId,
    required super.requestId,
    required super.sequence,
    required super.occurredAt,
    required this.toolId,
    required this.callId,
    required this.displayLabel,
    required this.safeArgsPreview,
  });

  final String toolId;
  final String callId;
  final String displayLabel;
  final List<ToolArgumentPreview> safeArgsPreview;
}

class ToolCallResultEvent extends AgentExecutionEvent {
  const ToolCallResultEvent({
    required super.runId,
    required super.sessionId,
    required super.requestId,
    required super.sequence,
    required super.occurredAt,
    required this.toolId,
    required this.callId,
    required this.displayLabel,
    required this.status,
    required this.summary,
  });

  final String toolId;
  final String callId;
  final String displayLabel;
  final String status;
  final String summary;
}

class ToolCallFailedEvent extends AgentExecutionEvent {
  const ToolCallFailedEvent({
    required super.runId,
    required super.sessionId,
    required super.requestId,
    required super.sequence,
    required super.occurredAt,
    required this.toolId,
    required this.callId,
    required this.displayLabel,
    required this.status,
    required this.summary,
  });

  final String toolId;
  final String callId;
  final String displayLabel;
  final String status;
  final String summary;
}

class ApprovalRequiredEvent extends AgentExecutionEvent {
  const ApprovalRequiredEvent({
    required super.runId,
    required super.sessionId,
    required super.requestId,
    required super.sequence,
    required super.occurredAt,
    required this.toolId,
    required this.callId,
    required this.displayLabel,
    required this.safeArgsPreview,
  });

  final String toolId;
  final String callId;
  final String displayLabel;
  final List<ToolArgumentPreview> safeArgsPreview;
}

class RunCompletedEvent extends AgentExecutionEvent {
  const RunCompletedEvent({
    required super.runId,
    required super.sessionId,
    required super.requestId,
    required super.sequence,
    required super.occurredAt,
    required this.reason,
  });

  final String reason;
}

class RunFailedEvent extends AgentExecutionEvent {
  const RunFailedEvent({
    required super.runId,
    required super.sessionId,
    required super.requestId,
    required super.sequence,
    required super.occurredAt,
    required this.reason,
  });

  final String reason;
}

class RunCancelledEvent extends AgentExecutionEvent {
  const RunCancelledEvent({
    required super.runId,
    required super.sessionId,
    required super.requestId,
    required super.sequence,
    required super.occurredAt,
    required this.reason,
  });

  final String reason;
}

class ToolArgumentPreview {
  const ToolArgumentPreview({required this.name, required this.displayValue});

  final String name;
  final String displayValue;
}

abstract class AgentExecutionEventSink {
  Future<void> applyAgentExecutionEvent(AgentExecutionEvent event);
}

class AgentExecutionEmitter {
  AgentExecutionEmitter({
    required this.requestId,
    required this.sessionId,
    this.runId,
    AgentExecutionEventSink? sink,
    DateTime Function()? clock,
  }) : _sink = sink,
       _clock = clock ?? DateTime.now;

  final String requestId;
  final String sessionId;
  final String? runId;
  final AgentExecutionEventSink? _sink;
  final DateTime Function() _clock;
  var _sequence = 0;

  Future<void> emitTokenDelta({
    required String messageId,
    required String delta,
  }) {
    return _emit(
      TokenDeltaEvent(
        runId: runId,
        sessionId: sessionId,
        requestId: requestId,
        sequence: _sequence++,
        occurredAt: _clock().toUtc(),
        messageId: messageId,
        delta: delta,
      ),
    );
  }

  Future<void> emitStepStarted({
    required String stepId,
    required String label,
  }) {
    return _emit(
      StepStartedEvent(
        runId: runId,
        sessionId: sessionId,
        requestId: requestId,
        sequence: _sequence++,
        occurredAt: _clock().toUtc(),
        stepId: stepId,
        label: label,
      ),
    );
  }

  Future<void> emitStepUpdated({
    required String stepId,
    required String status,
  }) {
    return _emit(
      StepUpdatedEvent(
        runId: runId,
        sessionId: sessionId,
        requestId: requestId,
        sequence: _sequence++,
        occurredAt: _clock().toUtc(),
        stepId: stepId,
        status: status,
      ),
    );
  }

  Future<void> emitToolCallStarted(ToolCall call) {
    return _emit(
      ToolCallStartedEvent(
        runId: runId,
        sessionId: sessionId,
        requestId: requestId,
        sequence: _sequence++,
        occurredAt: _clock().toUtc(),
        toolId: call.toolId,
        callId: call.id,
        displayLabel: displayLabelForToolId(call.toolId),
        safeArgsPreview: safeArgsPreviewFor(call.arguments),
      ),
    );
  }

  Future<void> emitToolCallResult(ToolCall call, ToolResult result) {
    return _emit(
      ToolCallResultEvent(
        runId: runId,
        sessionId: sessionId,
        requestId: requestId,
        sequence: _sequence++,
        occurredAt: _clock().toUtc(),
        toolId: result.toolId ?? call.toolId,
        callId: result.callId ?? call.id,
        displayLabel: displayLabelForToolId(result.toolId ?? call.toolId),
        status: result.statusName,
        summary: _safeSummary(result),
      ),
    );
  }

  Future<void> emitToolCallFailed(ToolCall call, ToolResult result) {
    return _emit(
      ToolCallFailedEvent(
        runId: runId,
        sessionId: sessionId,
        requestId: requestId,
        sequence: _sequence++,
        occurredAt: _clock().toUtc(),
        toolId: result.toolId ?? call.toolId,
        callId: result.callId ?? call.id,
        displayLabel: displayLabelForToolId(result.toolId ?? call.toolId),
        status: result.statusName,
        summary: _safeSummary(result),
      ),
    );
  }

  Future<void> emitApprovalRequired(ToolCall call) {
    return _emit(
      ApprovalRequiredEvent(
        runId: runId,
        sessionId: sessionId,
        requestId: requestId,
        sequence: _sequence++,
        occurredAt: _clock().toUtc(),
        toolId: call.toolId,
        callId: call.id,
        displayLabel: displayLabelForToolId(call.toolId),
        safeArgsPreview: safeArgsPreviewFor(call.arguments),
      ),
    );
  }

  Future<void> emitRunCompleted({required String reason}) {
    return _emit(
      RunCompletedEvent(
        runId: runId,
        sessionId: sessionId,
        requestId: requestId,
        sequence: _sequence++,
        occurredAt: _clock().toUtc(),
        reason: reason,
      ),
    );
  }

  Future<void> emitRunFailed({required String reason}) {
    return _emit(
      RunFailedEvent(
        runId: runId,
        sessionId: sessionId,
        requestId: requestId,
        sequence: _sequence++,
        occurredAt: _clock().toUtc(),
        reason: reason,
      ),
    );
  }

  Future<void> emitRunCancelled({required String reason}) {
    return _emit(
      RunCancelledEvent(
        runId: runId,
        sessionId: sessionId,
        requestId: requestId,
        sequence: _sequence++,
        occurredAt: _clock().toUtc(),
        reason: reason,
      ),
    );
  }

  Future<void> _emit(AgentExecutionEvent event) async {
    final sink = _sink;
    if (sink == null) {
      return;
    }
    await sink.applyAgentExecutionEvent(event);
  }
}

String displayLabelForToolId(String toolId) {
  final words = toolId
      .split(RegExp(r'[_\-.]+'))
      .where((part) => part.trim().isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}');
  return words.isEmpty ? 'Tool' : words.join(' ');
}

List<ToolArgumentPreview> safeArgsPreviewFor(Map<String, Object?> args) {
  final keys = args.keys.toList()..sort();
  return keys
      .map(
        (key) => ToolArgumentPreview(
          name: key,
          displayValue: _safeDisplayValue(args[key]),
        ),
      )
      .toList(growable: false);
}

String _safeDisplayValue(Object? value) {
  if (value == null) {
    return 'empty';
  }
  if (value is bool || value is num) {
    return value.toString();
  }
  if (value is String) {
    return _looksSensitive(value) ? 'redacted' : _clip(value);
  }
  if (value is Iterable) {
    return '${value.length} items';
  }
  if (value is Map) {
    return '${value.length} fields';
  }
  return _clip(value.toString());
}

String _safeSummary(ToolResult result) {
  final summary = result.userVisibleMessage ?? result.summary;
  return _clip(summary.trim());
}

bool _looksSensitive(String value) {
  final lowered = value.toLowerCase();
  return lowered.contains('token') ||
      lowered.contains('secret') ||
      lowered.contains('password') ||
      lowered.contains('authorization') ||
      lowered.contains('bearer ');
}

String _clip(String value) {
  const limit = 80;
  final trimmed = value.trim();
  if (trimmed.length <= limit) {
    return trimmed;
  }
  return '${trimmed.substring(0, limit)}...';
}
