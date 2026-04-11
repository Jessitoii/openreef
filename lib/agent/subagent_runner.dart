import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:openreef/agent/agent_models.dart';

typedef RootToolExecutor =
    Future<ToolResult> Function(
      ToolCall call, {
      required String sessionKey,
    });

class SubAgentRootBridgeRegistry {
  static RootToolExecutor? _toolExecutor;

  static RootToolExecutor? get toolExecutor => _toolExecutor;

  static void registerToolExecutor(RootToolExecutor executor) {
    _toolExecutor = executor;
  }
}

enum SubAgentRunStatus {
  completed,
  failed,
  timedOut,
}

class SubAgentLaunchRequest {
  const SubAgentLaunchRequest({
    required this.parentSessionKey,
    required this.sessionKey,
    required this.task,
    required this.timeoutMs,
    this.preferredModel,
    this.rootIsolateToken,
  });

  final String parentSessionKey;
  final String sessionKey;
  final String task;
  final String? preferredModel;
  final int timeoutMs;
  final RootIsolateToken? rootIsolateToken;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'parentSessionKey': parentSessionKey,
      'sessionKey': sessionKey,
      'task': task,
      'preferredModel': preferredModel,
      'timeoutMs': timeoutMs,
      'rootIsolateToken': rootIsolateToken,
    };
  }

  factory SubAgentLaunchRequest.fromMap(Map<String, Object?> map) {
    return SubAgentLaunchRequest(
      parentSessionKey: map['parentSessionKey'] as String? ?? 'agent:main',
      sessionKey: map['sessionKey'] as String? ?? 'agent:main:sub:unknown',
      task: map['task'] as String? ?? '',
      preferredModel: map['preferredModel'] as String?,
      timeoutMs: map['timeoutMs'] as int? ?? 0,
      rootIsolateToken: map['rootIsolateToken'] as RootIsolateToken?,
    );
  }
}

class SubAgentRunResult {
  const SubAgentRunResult({
    required this.sessionKey,
    required this.status,
    required this.text,
    required this.durationMs,
    this.reason,
  });

  final String sessionKey;
  final SubAgentRunStatus status;
  final String text;
  final String? reason;
  final int durationMs;

  bool get isCompleted => status == SubAgentRunStatus.completed;
  bool get isFailed => status == SubAgentRunStatus.failed;
  bool get isTimedOut => status == SubAgentRunStatus.timedOut;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sessionKey': sessionKey,
      'status': switch (status) {
        SubAgentRunStatus.completed => 'completed',
        SubAgentRunStatus.failed => 'failed',
        SubAgentRunStatus.timedOut => 'timed_out',
      },
      'text': text,
      'reason': reason,
      'durationMs': durationMs,
    };
  }

  factory SubAgentRunResult.fromMap(Map<String, Object?> map) {
    final rawStatus = map['status'] as String? ?? 'failed';
    return SubAgentRunResult(
      sessionKey: map['sessionKey'] as String? ?? 'agent:main:sub:unknown',
      status: switch (rawStatus) {
        'completed' => SubAgentRunStatus.completed,
        'timed_out' => SubAgentRunStatus.timedOut,
        _ => SubAgentRunStatus.failed,
      },
      text: map['text'] as String? ?? '',
      reason: map['reason'] as String?,
      durationMs: map['durationMs'] as int? ?? 0,
    );
  }
}

class SubAgentRunner {
  const SubAgentRunner();

  Future<SubAgentRunResult> run(SubAgentLaunchRequest request) async {
    final bridgePort = ReceivePort();
    final subscription = bridgePort.listen((message) {
      unawaited(_handleBridgeMessage(message));
    });

    try {
      final result = await Isolate.run<Map<String, Object?>>(
        () => _runInIsolate(request.toMap(), bridgePort.sendPort),
      ).timeout(
        Duration(milliseconds: request.timeoutMs),
        onTimeout: () => <String, Object?>{
          'sessionKey': request.sessionKey,
          'status': 'timed_out',
          'text': '',
          'reason': 'timeout',
          'durationMs': request.timeoutMs,
        },
      );
      return SubAgentRunResult.fromMap(result);
    } finally {
      await subscription.cancel();
      bridgePort.close();
    }
  }

  static Future<Map<String, Object?>> _runInIsolate(
    Map<String, Object?> rawRequest,
    SendPort rootBridgePort,
  ) async {
    final request = SubAgentLaunchRequest.fromMap(rawRequest);
    final start = DateTime.now();

    try {
      final token = request.rootIsolateToken;
      if (token != null) {
        BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      }

      final taskSpec = _TaskSpec.parse(request.task);
      if (taskSpec.delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: taskSpec.delayMs));
      }

      if (taskSpec.failReason != null) {
        throw StateError(taskSpec.failReason!);
      }

      var text = taskSpec.text ?? request.task;
      if (taskSpec.toolCall != null) {
        text = await _executeToolCall(
          rootBridgePort,
          request.sessionKey,
          taskSpec.toolCall!,
        );
      }

      return SubAgentRunResult(
        sessionKey: request.sessionKey,
        status: SubAgentRunStatus.completed,
        text: text,
        durationMs: DateTime.now().difference(start).inMilliseconds,
      ).toMap();
    } catch (error) {
      return SubAgentRunResult(
        sessionKey: request.sessionKey,
        status: SubAgentRunStatus.failed,
        text: '',
        reason: error.toString(),
        durationMs: DateTime.now().difference(start).inMilliseconds,
      ).toMap();
    }
  }

  static Future<String> _executeToolCall(
    SendPort rootBridgePort,
    String sessionKey,
    ToolCall call,
  ) async {
    final responsePort = ReceivePort();
    try {
      rootBridgePort.send(<String, Object?>{
        'kind': 'tool_call',
        'workerSessionKey': sessionKey,
        'call': call.toMap(),
        'replyPort': responsePort.sendPort,
      });
      final response = await responsePort.first;
      if (response is Map<String, Object?>) {
        return ToolResult.fromMap(response).content;
      }
      if (response is Map) {
        return ToolResult.fromMap(Map<String, Object?>.from(response)).content;
      }
      return 'unsupported_background_operation';
    } finally {
      responsePort.close();
    }
  }

  Future<void> _handleBridgeMessage(dynamic message) async {
    if (message is! Map) {
      return;
    }

    final rawMessage = Map<String, Object?>.from(message);
    if (rawMessage['kind'] != 'tool_call') {
      return;
    }

    final replyPort = rawMessage['replyPort'];
    if (replyPort is! SendPort) {
      return;
    }

    final rawCall = rawMessage['call'];
    final call = rawCall is Map<String, Object?>
        ? ToolCall.fromMap(rawCall)
        : rawCall is Map
            ? ToolCall.fromMap(Map<String, Object?>.from(rawCall))
            : const ToolCall(id: 'unsupported', toolId: '');

    final executor = SubAgentRootBridgeRegistry.toolExecutor;
    final result = executor == null
        ? const ToolResult.rejected(
            summary: 'unsupported_background_operation',
          )
        : await executor(
            call,
            sessionKey: rawMessage['workerSessionKey'] as String? ?? 'agent:main',
          );
    replyPort.send(result.toMap());
  }
}

class _TaskSpec {
  const _TaskSpec({
    required this.delayMs,
    this.text,
    this.failReason,
    this.toolCall,
  });

  final int delayMs;
  final String? text;
  final String? failReason;
  final ToolCall? toolCall;

  factory _TaskSpec.parse(String task) {
    try {
      final decoded = jsonDecode(task);
      if (decoded is! Map) {
        return _TaskSpec(delayMs: 0, text: task);
      }

      final rawToolCall = decoded['toolCall'] ?? decoded['tool_call'];
      final toolCall = rawToolCall is Map<String, Object?>
          ? ToolCall.fromMap(rawToolCall)
          : rawToolCall is Map
              ? ToolCall.fromMap(Map<String, Object?>.from(rawToolCall))
              : null;

      return _TaskSpec(
        delayMs: decoded['delayMs'] as int? ?? decoded['delay_ms'] as int? ?? 0,
        text: decoded['text'] as String? ?? decoded['result'] as String?,
        failReason: decoded['failReason'] as String? ?? decoded['fail_reason'] as String?,
        toolCall: toolCall,
      );
    } on FormatException {
      return _TaskSpec(delayMs: 0, text: task);
    }
  }
}
