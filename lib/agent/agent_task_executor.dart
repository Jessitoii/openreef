import 'dart:async';
import 'dart:convert';

import 'package:openreef/agent/agent_loop.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/execution_log.dart';
import 'package:openreef/agent/execution_request.dart';

enum AgentTaskExecutionStatus { completed, frozen, failed }

class AgentTaskTriggerMetadata {
  const AgentTaskTriggerMetadata({
    required this.triggerId,
    required this.triggerName,
    required this.triggerType,
    required this.deliveryType,
    required this.payload,
    required this.deliveredAt,
    this.scheduledAt,
    this.appliedStandingOrderIds = const <String>[],
    this.standingOrderInstructions,
  });

  final String triggerId;
  final String triggerName;
  final String triggerType;
  final String deliveryType;
  final Map<String, Object?> payload;
  final DateTime deliveredAt;
  final DateTime? scheduledAt;
  final List<String> appliedStandingOrderIds;
  final String? standingOrderInstructions;

  Map<String, dynamic> toMetadataMap() {
    return <String, dynamic>{
      'triggerId': triggerId,
      'triggerName': triggerName,
      'triggerType': triggerType,
      'deliveryType': deliveryType,
      'payload': payload,
      'deliveredAt': deliveredAt.toIso8601String(),
      if (scheduledAt != null) 'scheduledAt': scheduledAt!.toIso8601String(),
      if (appliedStandingOrderIds.isNotEmpty)
        'appliedStandingOrderIds': appliedStandingOrderIds,
      if (standingOrderInstructions != null &&
          standingOrderInstructions!.trim().isNotEmpty)
        'standingOrderInstructions': standingOrderInstructions!.trim(),
    };
  }
}

class AgentTaskRequest {
  const AgentTaskRequest({
    required this.sessionKey,
    required this.prompt,
    required this.source,
    this.visibility = ExecutionVisibility.background,
    this.triggerMetadata,
    this.metadata = const <String, dynamic>{},
  });

  final String sessionKey;
  final String prompt;
  final ExecutionSource source;
  final ExecutionVisibility visibility;
  final AgentTaskTriggerMetadata? triggerMetadata;
  final Map<String, dynamic> metadata;

  ExecutionRequest toExecutionRequest() {
    final timestamp = DateTime.now().toUtc();
    final mergedMetadata = <String, dynamic>{
      ...metadata,
      ...?triggerMetadata?.toMetadataMap(),
    };
    return ExecutionRequest(
      id: '${source.name}_${timestamp.microsecondsSinceEpoch}',
      source: source,
      sessionKey: sessionKey,
      prompt: prompt,
      visibility: visibility,
      createdAt: timestamp,
      metadata: mergedMetadata.isEmpty ? null : mergedMetadata,
    );
  }
}

class AgentTaskExecutionResult {
  const AgentTaskExecutionResult({
    required this.status,
    required this.text,
    required this.reason,
    required this.toolsUsed,
  });

  final AgentTaskExecutionStatus status;
  final String text;
  final String reason;
  final List<String> toolsUsed;

  factory AgentTaskExecutionResult.fromLoopResult(AgentLoopResult result) {
    return AgentTaskExecutionResult(
      status: switch (result.sessionResult) {
        SessionResult.completed => AgentTaskExecutionStatus.completed,
        SessionResult.frozen => AgentTaskExecutionStatus.frozen,
        SessionResult.failed => AgentTaskExecutionStatus.failed,
      },
      text: result.text,
      reason: result.reason ?? '',
      toolsUsed: result.toolsUsed,
    );
  }
}

abstract class ChatExecutionSink {
  Future<void> appendExecutionResult(
    ExecutionRequest request,
    AgentLoopResult result,
  );
}

abstract class BackgroundExecutionSink {
  Future<void> recordExecution(
    ExecutionRequest request,
    AgentLoopResult result,
  );
}

abstract class AgentTaskExecutor {
  Future<AgentLoopResult> execute(ExecutionRequest request);

  Future<AgentTaskExecutionResult> executeTask(AgentTaskRequest request);
}

class AgentLoopTaskExecutor implements AgentTaskExecutor {
  AgentLoopTaskExecutor({
    required AgentLoop agentLoop,
    required ExecutionLogStore executionLogStore,
    ChatExecutionSink? chatSink,
    BackgroundExecutionSink? backgroundSink,
    DateTime Function()? clock,
  }) : _agentLoop = agentLoop,
       _executionLogStore = executionLogStore,
       _chatSink = chatSink,
       _backgroundSink = backgroundSink,
       _clock = clock ?? DateTime.now;

  final AgentLoop _agentLoop;
  final ExecutionLogStore _executionLogStore;
  final ChatExecutionSink? _chatSink;
  final BackgroundExecutionSink? _backgroundSink;
  final DateTime Function() _clock;
  final Set<String> _activeSessionKeys = <String>{};

  @override
  Future<AgentTaskExecutionResult> executeTask(AgentTaskRequest request) async {
    final result = await execute(request.toExecutionRequest());
    return AgentTaskExecutionResult.fromLoopResult(result);
  }

  @override
  Future<AgentLoopResult> execute(ExecutionRequest request) async {
    _executionLogStore.start(
      ExecutionRecord(
        id: request.id,
        sessionKey: request.sessionKey,
        source: request.source,
        status: ExecutionStatus.running,
        toolsUsed: const <String>[],
        createdAt: request.createdAt.toUtc(),
      ),
    );

    if (!_activeSessionKeys.add(request.sessionKey)) {
      final result = const AgentLoopResult(
        sessionResult: SessionResult.failed,
        text: '',
        reason: 'session_busy',
        toolsUsed: <String>[],
      );
      await _completeExecution(
        request,
        result,
        status: ExecutionStatus.failed,
        errorSummary: 'An execution is already running for this session.',
      );
      return result;
    }

    try {
      final result = await _agentLoop.run(
        _buildPrompt(request),
        sessionKey: request.sessionKey,
        conversationHistory: _conversationHistoryFromMetadata(request.metadata),
        modelContextWindow:
            (request.metadata?['modelContextWindow'] as int?) ?? 8192,
        compactRequested:
            (request.metadata?['compactRequested'] as bool?) ?? false,
        recentFiles: (request.metadata?['recentFiles'] as List?)
                ?.map((entry) => entry.toString())
                .toList(growable: false) ??
            const <String>[],
      );
      await _completeExecution(
        request,
        result,
        status: _mapStatus(result.sessionResult),
        errorSummary: _errorSummaryFor(result),
      );
      return result;
    } catch (error) {
      final result = const AgentLoopResult(
        sessionResult: SessionResult.failed,
        text: '',
        reason: 'executor_failure',
        toolsUsed: <String>[],
      );
      await _completeExecution(
        request,
        result,
        status: ExecutionStatus.failed,
        errorSummary: error.toString(),
      );
      return result;
    } finally {
      _activeSessionKeys.remove(request.sessionKey);
    }
  }

  Future<void> _completeExecution(
    ExecutionRequest request,
    AgentLoopResult result, {
    required ExecutionStatus status,
    String? errorSummary,
  }) async {
    _executionLogStore.complete(
      request.id,
      status: status,
      toolsUsed: result.toolsUsed,
      finishedAt: _clock().toUtc(),
      failureReason: result.sessionResult == SessionResult.completed
          ? null
          : result.reason,
      errorSummary: errorSummary,
    );
    await _routeOutput(request, result);
  }

  Future<void> _routeOutput(
    ExecutionRequest request,
    AgentLoopResult result,
  ) async {
    switch (request.visibility) {
      case ExecutionVisibility.chat:
        final chatSink = _chatSink;
        if (chatSink != null) {
          await chatSink.appendExecutionResult(request, result);
        }
      case ExecutionVisibility.background:
        final backgroundSink = _backgroundSink;
        if (backgroundSink != null) {
          await backgroundSink.recordExecution(request, result);
        }
      case ExecutionVisibility.chatAndBackground:
        final chatSink = _chatSink;
        if (chatSink != null) {
          await chatSink.appendExecutionResult(request, result);
        }
        final backgroundSink = _backgroundSink;
        if (backgroundSink != null) {
          await backgroundSink.recordExecution(request, result);
        }
    }
  }

  ExecutionStatus _mapStatus(SessionResult result) {
    return switch (result) {
      SessionResult.completed => ExecutionStatus.completed,
      SessionResult.frozen => ExecutionStatus.frozen,
      SessionResult.failed => ExecutionStatus.failed,
    };
  }

  String? _errorSummaryFor(AgentLoopResult result) {
    if (result.sessionResult == SessionResult.completed) {
      return null;
    }
    final trimmed = result.text.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return result.reason;
  }

  String _buildPrompt(ExecutionRequest request) {
    final trimmedPrompt = request.prompt.trim();
    if (request.metadata == null || request.metadata!.isEmpty) {
      return trimmedPrompt;
    }

    final sourceLabel = switch (request.source) {
      ExecutionSource.user => 'USER',
      ExecutionSource.trigger => 'TRIGGER',
      ExecutionSource.schedule => 'SCHEDULE',
      ExecutionSource.mcpEvent => 'MCP_EVENT',
    };
    final metadata = Map<String, dynamic>.from(request.metadata!)
      ..remove('conversationHistory')
      ..remove('modelContextWindow')
      ..remove('compactRequested')
      ..remove('recentFiles');
    if (metadata.isEmpty) {
      return trimmedPrompt;
    }
    return '$sourceLabel EXECUTION\nmetadata: ${_canonicalJson(metadata)}\n\n$trimmedPrompt';
  }

  String _canonicalJson(Map<String, dynamic> value) {
    final sortedKeys = value.keys.toList()..sort();
    return jsonEncode(
      <String, dynamic>{for (final key in sortedKeys) key: value[key]},
    );
  }

  List<AgentMessage> _conversationHistoryFromMetadata(
    Map<String, dynamic>? metadata,
  ) {
    final rawHistory = metadata?['conversationHistory'];
    if (rawHistory is! List) {
      return const <AgentMessage>[];
    }
    return rawHistory
        .whereType<Map>()
        .map(
          (entry) => AgentMessage(
            role: _roleFromName(entry['role'] as String?),
            content: entry['content'] as String? ?? '',
            turnNumber: entry['turnNumber'] as int?,
          ),
        )
        .toList(growable: false);
  }

  AgentMessageRole _roleFromName(String? value) {
    return switch (value) {
      'system' => AgentMessageRole.system,
      'assistant' => AgentMessageRole.assistant,
      'tool' => AgentMessageRole.tool,
      'toolError' => AgentMessageRole.toolError,
      'summary' => AgentMessageRole.summary,
      'standingOrder' => AgentMessageRole.standingOrder,
      'memory' => AgentMessageRole.memory,
      _ => AgentMessageRole.user,
    };
  }
}
