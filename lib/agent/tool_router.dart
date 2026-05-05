import 'dart:async';

import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/agent_execution_event.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/subagent_runner.dart';
import 'package:openreef/tools/tool_argument_normalizer.dart';
import 'package:openreef/tools/tool_errors.dart';
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
  InMemoryToolCatalog(List<ToolDefinition> tools) : _tools = _toolsById(tools);

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
      _sourceTools[entry.key] = _toolsById(entry.value);
    }
    _validateUniqueIds(_sourceTools);
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
    nextSourceTools[sourceId] = _toolsById(tools);
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
    ToolArgumentNormalizer argumentNormalizer = const ToolArgumentNormalizer(),
  }) : _catalog = catalog,
       _mailbox = mailbox,
       _confirmToolCall = confirmToolCall,
       _executionTimeout = executionTimeout,
       _argumentNormalizer = argumentNormalizer {
    SubAgentRootBridgeRegistry.registerToolExecutor(
      (call, {required sessionKey}) => dispatch(call, sessionKey: sessionKey),
    );
  }

  final ToolCatalog _catalog;
  final AgentMailbox _mailbox;
  final Future<bool> Function(ToolCall call) _confirmToolCall;
  final Duration _executionTimeout;
  final ToolArgumentNormalizer _argumentNormalizer;

  Future<ToolResult> dispatch(
    ToolCall call, {
    required String sessionKey,
    String? userMessage,
    AgentExecutionEmitter? executionEmitter,
    CancellationSignal? cancellationSignal,
  }) async {
    final canonicalCall = _canonicalizeToolCall(call);
    final cancelled = _cancelledResultIfRequested(
      canonicalCall,
      cancellationSignal,
    );
    if (cancelled != null) {
      return cancelled;
    }
    final tool = _catalog.byId(canonicalCall.toolId);
    final normalizedCall = tool == null
        ? canonicalCall
        : _argumentNormalizer.normalize(
            canonicalCall,
            tool: tool,
            userMessage: userMessage,
          );
    final validationFailure = validateToolCall(normalizedCall);
    if (validationFailure != null) {
      return validationFailure;
    }

    if (tool == null || !tool.enabled) {
      return ToolResult.failure(
        'Tool ${normalizedCall.toolId} is unavailable.',
        toolId: normalizedCall.toolId,
        callId: normalizedCall.id,
        status: ToolResultStatus.unavailable,
        retryable: tool != null,
        metadata: <String, Object?>{
          'reason': tool == null ? 'unknown_tool' : 'disabled_tool',
          'errorCode': tool == null
              ? 'unknown_tool:${normalizedCall.toolId}'
              : 'disabled_tool:${normalizedCall.toolId}',
        },
      );
    }

    final request = NormalizedToolRequest(
      callId: normalizedCall.id,
      toolId: tool.id,
      normalizedArgs: Map<String, Object?>.unmodifiable(
        normalizedCall.arguments,
      ),
      requiresConfirmation: tool.requiresConfirmation,
      sessionKey: sessionKey,
      source: normalizedCall.source,
    );
    return dispatchRequest(
      request,
      executionEmitter: executionEmitter,
      cancellationSignal: cancellationSignal,
    );
  }

  ToolResult? validateToolCall(ToolCall call) {
    if (call.hasRawArguments && call.rawArguments is! Map) {
      return _protocolFailure(call, 'malformed_tool_call');
    }

    final tool = _catalog.byId(call.toolId);
    if (tool == null || !tool.enabled) {
      return null;
    }

    final declaredKeys = tool.argumentSchema
        .map((argument) => argument.name)
        .toSet();
    for (final key in call.arguments.keys) {
      if (_schemaArgumentKeys.contains(key) && !declaredKeys.contains(key)) {
        return _protocolFailure(call, 'schema_passed_as_args');
      }
    }
    if (_containsNestedSchemaPayload(call.arguments)) {
      return _protocolFailure(call, 'schema_passed_as_args');
    }
    if (_containsProtocolPayload(call.arguments)) {
      return _protocolFailure(call, 'malformed_tool_call');
    }
    for (final key in call.arguments.keys) {
      if (!declaredKeys.contains(key)) {
        return _protocolFailure(call, 'malformed_tool_call');
      }
    }
    return null;
  }

  Future<ToolResult> dispatchRequest(
    NormalizedToolRequest request, {
    AgentExecutionEmitter? executionEmitter,
    CancellationSignal? cancellationSignal,
  }) async {
    final canonicalRequest = _canonicalizeRequest(request);
    final tool = _catalog.byId(canonicalRequest.toolId);
    if (tool == null || !tool.enabled) {
      return ToolResult.failure(
        'Tool ${canonicalRequest.toolId} is unavailable.',
        toolId: canonicalRequest.toolId,
        callId: canonicalRequest.callId,
        status: ToolResultStatus.unavailable,
        retryable: tool != null,
        metadata: <String, Object?>{
          'reason': tool == null ? 'unknown_tool' : 'disabled_tool',
          'errorCode': tool == null
              ? 'unknown_tool:${canonicalRequest.toolId}'
              : 'disabled_tool:${canonicalRequest.toolId}',
        },
      );
    }

    final call = canonicalRequest.toToolCall();
    final cancelledBeforeApproval = _cancelledResultIfRequested(
      call,
      cancellationSignal,
    );
    if (cancelledBeforeApproval != null) {
      return cancelledBeforeApproval;
    }
    final requiresConfirmation =
        canonicalRequest.requiresConfirmation || tool.requiresConfirmation;
    if (requiresConfirmation) {
      await executionEmitter?.emitApprovalRequired(call);
      if (!_isSubAgentSession(canonicalRequest.sessionKey)) {
        final approved = await _waitForCancellation(
          _confirmToolCall(call),
          cancellationSignal,
        );
        final cancelledAfterApprovalWait = _cancelledResultIfRequested(
          call,
          cancellationSignal,
        );
        if (cancelledAfterApprovalWait != null) {
          return cancelledAfterApprovalWait;
        }
        if (approved != true) {
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
        final decision = await _waitForCancellation(
          _mailbox.requestApproval(
            workerSessionKey: canonicalRequest.sessionKey,
            call: call,
          ),
          cancellationSignal,
        );
        final cancelledAfterMailboxWait = _cancelledResultIfRequested(
          call,
          cancellationSignal,
        );
        if (cancelledAfterMailboxWait != null) {
          return cancelledAfterMailboxWait;
        }
        if (decision == null) {
          return _cancelledResultIfRequested(call, cancellationSignal)!;
        }
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
      final result = await tool.execute(call).timeout(_executionTimeout);
      final cancelledAfterExecution = _cancelledResultIfRequested(
        call,
        cancellationSignal,
      );
      if (cancelledAfterExecution != null) {
        return cancelledAfterExecution;
      }
      return result.withCall(call);
    } catch (error) {
      final cancelledAfterError = _cancelledResultIfRequested(
        call,
        cancellationSignal,
      );
      if (cancelledAfterError != null) {
        return cancelledAfterError;
      }
      return _normalizeException(call, error);
    }
  }

  Future<T?> _waitForCancellation<T>(
    Future<T> future,
    CancellationSignal? cancellationSignal,
  ) {
    if (cancellationSignal == null) {
      return future;
    }
    if (cancellationSignal.isCancelled) {
      return Future<T?>.value();
    }
    return Future.any(<Future<T?>>[
      future.then<T?>((value) => value),
      cancellationSignal.whenCancelled.then<T?>((_) => null),
    ]);
  }

  ToolResult? _cancelledResultIfRequested(
    ToolCall call,
    CancellationSignal? cancellationSignal,
  ) {
    if (cancellationSignal?.isCancelled != true) {
      return null;
    }
    return ToolResult.failure(
      'Tool execution was cancelled.',
      toolId: call.toolId,
      callId: call.id,
      status: ToolResultStatus.cancelled,
      userVisibleMessage: 'Tool execution was cancelled.',
      metadata: <String, Object?>{
        'reason': cancellationSignal?.reason ?? 'cancelled',
        'errorCode': 'tool_cancelled',
      },
    );
  }

  static const Set<String> _schemaArgumentKeys = <String>{
    'type',
    'properties',
    'required',
    'parameters',
    'schema',
  };

  static const List<String> _protocolTokens = <String>[
    '<|tool_call>',
    '<tool_call|>',
    '<|assistant|>',
    '<|user|>',
    '<|system|>',
    '<|tool|>',
  ];

  static const Map<String, String> _legacyToolIds = <String, String>{
    'communication_sms_send': 'sms_send',
    'communication_phone_call': 'phone_call',
    'communication_phone_dial': 'phone_dial',
  };

  ToolCall _canonicalizeToolCall(ToolCall call) {
    final canonicalToolId = _legacyToolIds[call.toolId];
    if (canonicalToolId == null) {
      return call;
    }
    return ToolCall(
      id: call.id,
      toolId: canonicalToolId,
      arguments: call.arguments,
      rawArguments: call.rawArguments,
      hasRawArguments: call.hasRawArguments,
      source: call.source,
    );
  }

  NormalizedToolRequest _canonicalizeRequest(NormalizedToolRequest request) {
    final canonicalToolId = _legacyToolIds[request.toolId];
    if (canonicalToolId == null) {
      return request;
    }
    return NormalizedToolRequest(
      callId: request.callId,
      toolId: canonicalToolId,
      normalizedArgs: request.normalizedArgs,
      requiresConfirmation: request.requiresConfirmation,
      sessionKey: request.sessionKey,
      source: request.source,
    );
  }

  bool _containsNestedSchemaPayload(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toSet();
      if (keys.contains('type') && keys.contains('properties')) {
        return true;
      }
      return value.values.any(_containsNestedSchemaPayload);
    }
    if (value is List) {
      return value.any(_containsNestedSchemaPayload);
    }
    return false;
  }

  bool _containsProtocolPayload(Object? value) {
    if (value is String) {
      return _protocolTokens.any(value.contains);
    }
    if (value is Map) {
      return value.values.any(_containsProtocolPayload);
    }
    if (value is Iterable) {
      return value.any(_containsProtocolPayload);
    }
    return false;
  }

  ToolResult _protocolFailure(ToolCall call, String reason) {
    return ToolResult.failure(
      reason,
      toolId: call.toolId,
      callId: call.id,
      status: ToolResultStatus.validationError,
      userVisibleMessage: 'The tool call was malformed.',
      metadata: <String, Object?>{'reason': reason, 'errorCode': reason},
    );
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
    if (error is ToolExecutionException) {
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

  ToolResultStatus _statusForNativeErrorCode(ToolErrorCode code) {
    return switch (code) {
      ToolErrorCode.permissionDenied ||
      ToolErrorCode.permissionRequired => ToolResultStatus.permissionDenied,
      ToolErrorCode.invalidArguments => ToolResultStatus.validationError,
      ToolErrorCode.featureUnavailable ||
      ToolErrorCode.appUnavailable ||
      ToolErrorCode.unsupported => ToolResultStatus.unavailable,
      ToolErrorCode.operationFailed ||
      ToolErrorCode.nativeError ||
      ToolErrorCode.mcpError ||
      ToolErrorCode.runtimeError => ToolResultStatus.executionError,
      ToolErrorCode.semanticError => ToolResultStatus.executionError,
    };
  }

  String _errorCodeFor(Object error) {
    if (error is TimeoutException) {
      return 'timeout';
    }
    if (error is ToolExecutionException) {
      return error.error.id;
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
      ToolResultStatus.executionError => 'Tool execution failed.',
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

Map<String, ToolDefinition> _toolsById(List<ToolDefinition> tools) {
  final byId = <String, ToolDefinition>{};
  for (final tool in tools) {
    if (byId.containsKey(tool.id)) {
      throw StateError('duplicate_tool_id:${tool.id}');
    }
    byId[tool.id] = tool;
  }
  return byId;
}
