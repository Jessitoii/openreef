import 'dart:async';

import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/subagent_runner.dart';
import 'package:openreef/tools/native_tool_errors.dart';
import 'package:openreef/tools/tool_manifest.dart';

class ToolDefinition {
  const ToolDefinition({
    required this.id,
    required this.embedding,
    required this.execute,
    this.description = '',
    this.enabled = true,
    this.requiresConfirmation = false,
    this.argumentSchema = const <ToolArgumentSpec>[],
    this.category = 'general',
    this.tags = const <String>[],
    this.source,
    this.runtimeMetadata = const <String, Object?>{},
  });

  final String id;
  final List<double> embedding;
  final Future<ToolResult> Function(ToolCall call) execute;
  final String description;
  final bool enabled;
  final bool requiresConfirmation;
  final List<ToolArgumentSpec> argumentSchema;
  final String category;
  final List<String> tags;
  final String? source;
  final Map<String, Object?> runtimeMetadata;
}

abstract class ToolCatalog {
  List<ToolDefinition> listTools();

  ToolDefinition? byId(String id);
}

class InMemoryToolCatalog implements ToolCatalog {
  InMemoryToolCatalog(List<ToolDefinition> tools)
    : _tools = Map<String, ToolDefinition>.fromEntries(
        tools.map((tool) => MapEntry<String, ToolDefinition>(tool.id, tool)),
      );

  final Map<String, ToolDefinition> _tools;

  @override
  ToolDefinition? byId(String id) => _tools[id];

  @override
  List<ToolDefinition> listTools() => _tools.values.toList(growable: false);
}

class RuntimeToolCatalog implements ToolCatalog {
  RuntimeToolCatalog({
    Map<String, List<ToolDefinition>> sourceTools =
        const <String, List<ToolDefinition>>{},
  }) : _sourceTools = <String, Map<String, ToolDefinition>>{} {
    for (final entry in sourceTools.entries) {
      _sourceTools[entry.key] = Map<String, ToolDefinition>.fromEntries(
        entry.value.map(
          (tool) => MapEntry<String, ToolDefinition>(tool.id, tool),
        ),
      );
    }
    _rebuildIndex();
  }

  final Map<String, Map<String, ToolDefinition>> _sourceTools;
  Map<String, ToolDefinition> _tools = <String, ToolDefinition>{};

  @override
  ToolDefinition? byId(String id) => _tools[id];

  @override
  List<ToolDefinition> listTools() => _tools.values.toList(growable: false);

  void replaceSourceTools(String sourceId, List<ToolDefinition> tools) {
    final nextSourceTools = Map<String, Map<String, ToolDefinition>>.from(
      _sourceTools,
    );
    nextSourceTools[sourceId] = Map<String, ToolDefinition>.fromEntries(
      tools.map((tool) => MapEntry<String, ToolDefinition>(tool.id, tool)),
    );
    _commit(nextSourceTools);
  }

  void removeSourceTools(String sourceId) {
    if (!_sourceTools.containsKey(sourceId)) {
      return;
    }
    final nextSourceTools = Map<String, Map<String, ToolDefinition>>.from(
      _sourceTools,
    )..remove(sourceId);
    _commit(nextSourceTools);
  }

  List<ToolDefinition> listSourceTools(String sourceId) {
    return _sourceTools[sourceId]?.values.toList(growable: false) ??
        const <ToolDefinition>[];
  }

  void _commit(Map<String, Map<String, ToolDefinition>> nextSourceTools) {
    _validateUniqueIds(nextSourceTools);
    _sourceTools
      ..clear()
      ..addAll(nextSourceTools);
    _rebuildIndex();
  }

  void _rebuildIndex() {
    final rebuilt = <String, ToolDefinition>{};
    for (final tools in _sourceTools.values) {
      rebuilt.addAll(tools);
    }
    _tools = rebuilt;
  }

  void _validateUniqueIds(
    Map<String, Map<String, ToolDefinition>> sourceTools,
  ) {
    final seenIds = <String>{};
    for (final tools in sourceTools.values) {
      for (final toolId in tools.keys) {
        if (!seenIds.add(toolId)) {
          throw StateError('duplicate_tool_id:$toolId');
        }
      }
    }
  }
}

class ToolRouter {
  static const String rejectionReasonKey = 'outcome_reason';

  ToolRouter({
    required ToolCatalog catalog,
    required AgentMailbox mailbox,
    required Future<bool> Function(ToolCall call) confirmToolCall,
    Duration executionTimeout = const Duration(seconds: 30),
  }) : _catalog = catalog,
       _mailbox = mailbox,
       _confirmToolCall = confirmToolCall,
       _executionTimeout = executionTimeout {
    SubAgentRootBridgeRegistry.registerToolExecutor(
      (call, {required sessionKey}) => dispatch(call, sessionKey: sessionKey),
    );
  }

  final ToolCatalog _catalog;
  final AgentMailbox _mailbox;
  final Future<bool> Function(ToolCall call) _confirmToolCall;
  final Duration _executionTimeout;

  Future<ToolResult> dispatch(
    ToolCall call, {
    required String sessionKey,
  }) async {
    final tool = _catalog.byId(call.toolId);
    if (tool == null || !tool.enabled) {
      return ToolResult.failure(
        'Tool ${call.toolId} is unavailable.',
        toolId: call.toolId,
        callId: call.id,
        status: ToolResultStatus.unavailable,
        retryable: tool != null,
        metadata: <String, Object?>{
          'reason': tool == null ? 'unknown_tool' : 'disabled_tool',
          'errorCode': tool == null
              ? 'unknown_tool:${call.toolId}'
              : 'disabled_tool:${call.toolId}',
        },
      );
    }

    if (tool.requiresConfirmation) {
      if (!_isSubAgentSession(sessionKey)) {
        final approved = await _confirmToolCall(call);
        if (!approved) {
          return ToolResult.rejected(
            summary: 'Tool call rejected by the user.',
            toolId: call.toolId,
            callId: call.id,
            userVisibleMessage: 'Tool call rejected.',
            metadata: <String, Object?>{
              'reason': 'user_rejected',
              rejectionReasonKey: 'user_rejected',
            },
          );
        }
      } else {
        final decision = await _mailbox.requestApproval(
          workerSessionKey: sessionKey,
          call: call,
        );
        if (decision.isRejected) {
          return ToolResult.rejected(
            summary: decision.reason ?? 'Tool call rejected by mailbox.',
            toolId: call.toolId,
            callId: call.id,
            userVisibleMessage: 'Tool call rejected.',
            metadata: <String, Object?>{
              'reason': _normalizeMailboxRejectionReason(decision.reason),
              rejectionReasonKey: _normalizeMailboxRejectionReason(
                decision.reason,
              ),
            },
          );
        }
      }
    }

    try {
      return (await tool.execute(call).timeout(_executionTimeout)).withCall(
        call,
      );
    } catch (error) {
      return _normalizeException(call, error);
    }
  }

  ToolResult _normalizeException(ToolCall call, Object error) {
    final status = _statusForException(error);
    final errorCode = _errorCodeFor(error);
    return ToolResult.failure(
      _summaryFor(status, error),
      toolId: call.toolId,
      callId: call.id,
      status: status,
      retryable:
          status == ToolResultStatus.timeout ||
          status == ToolResultStatus.unavailable,
      userVisibleMessage: _userVisibleMessageFor(status),
      metadata: <String, Object?>{
        'reason': errorCode,
        'errorCode': errorCode,
        'errorMessage': error.toString(),
      },
    );
  }

  ToolResultStatus _statusForException(Object error) {
    if (error is TimeoutException) {
      return ToolResultStatus.timeout;
    }
    if (error is NativeToolException) {
      return _statusForNativeErrorCode(error.error.code);
    }
    if (error is ArgumentError ||
        error is FormatException ||
        error is TypeError ||
        error is UnsupportedError) {
      return ToolResultStatus.validationError;
    }
    if (error is StateError) {
      final message = error.message;
      if (message.startsWith('unknown_tool:') ||
          message.startsWith('disabled_tool:') ||
          message.contains('unavailable') ||
          message.contains('missing') ||
          message.contains('stale')) {
        return ToolResultStatus.unavailable;
      }
      if (message.contains('permission') ||
          message.contains('untrusted') ||
          message.contains('secret')) {
        return ToolResultStatus.permissionDenied;
      }
    }
    return ToolResultStatus.executionError;
  }

  ToolResultStatus _statusForNativeErrorCode(NativeToolErrorCode code) {
    return switch (code) {
      NativeToolErrorCode.permissionDenied ||
      NativeToolErrorCode.permissionRequired =>
        ToolResultStatus.permissionDenied,
      NativeToolErrorCode.invalidArguments => ToolResultStatus.validationError,
      NativeToolErrorCode.featureUnavailable ||
      NativeToolErrorCode.appUnavailable ||
      NativeToolErrorCode.unsupported => ToolResultStatus.unavailable,
      NativeToolErrorCode.operationFailed => ToolResultStatus.executionError,
    };
  }

  String _errorCodeFor(Object error) {
    if (error is TimeoutException) {
      return 'timeout';
    }
    if (error is NativeToolException) {
      return error.error.wireCode;
    }
    if (error is StateError) {
      return error.message;
    }
    if (error is ArgumentError) {
      return 'invalid_arguments';
    }
    if (error is FormatException) {
      return 'invalid_format';
    }
    if (error is TypeError) {
      return 'invalid_type';
    }
    if (error is UnsupportedError) {
      return 'unsupported';
    }
    return 'execution_error';
  }

  String _summaryFor(ToolResultStatus status, Object error) {
    return switch (status) {
      ToolResultStatus.validationError => 'Tool arguments failed validation.',
      ToolResultStatus.permissionDenied => 'Tool execution was denied.',
      ToolResultStatus.unavailable => 'Tool is unavailable.',
      ToolResultStatus.timeout => 'Tool execution timed out.',
      ToolResultStatus.cancelled => 'Tool execution was cancelled.',
      ToolResultStatus.rejected => 'Tool call was rejected.',
      ToolResultStatus.executionError => 'Tool execution failed: $error',
      ToolResultStatus.success => 'Tool execution completed.',
    };
  }

  String _userVisibleMessageFor(ToolResultStatus status) {
    return switch (status) {
      ToolResultStatus.validationError =>
        'The tool could not run because its arguments were invalid.',
      ToolResultStatus.permissionDenied =>
        'The tool could not run because permission was denied.',
      ToolResultStatus.unavailable => 'The requested tool is unavailable.',
      ToolResultStatus.timeout => 'The tool timed out.',
      ToolResultStatus.cancelled => 'The tool was cancelled.',
      ToolResultStatus.executionError => 'The tool failed while running.',
      ToolResultStatus.rejected => 'The tool call was rejected.',
      ToolResultStatus.success => 'The tool completed.',
    };
  }

  bool _isSubAgentSession(String sessionKey) {
    return sessionKey.startsWith('agent:main:sub:');
  }

  static String _normalizeMailboxRejectionReason(String? reason) {
    return switch (reason) {
      'timeout' => 'timeout',
      'user_denied' => 'user_rejected',
      'policy_denied' => 'policy_rejected',
      _ => 'rejected_unknown',
    };
  }
}
