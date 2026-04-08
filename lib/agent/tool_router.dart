import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/subagent_runner.dart';

class ToolDefinition {
  const ToolDefinition({
    required this.id,
    required this.embedding,
    required this.execute,
    this.description = '',
    this.enabled = true,
    this.requiresConfirmation = false,
  });

  final String id;
  final List<double> embedding;
  final Future<ToolResult> Function(ToolCall call) execute;
  final String description;
  final bool enabled;
  final bool requiresConfirmation;
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
    Map<String, List<ToolDefinition>> sourceTools = const <String, List<ToolDefinition>>{},
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

  void _validateUniqueIds(Map<String, Map<String, ToolDefinition>> sourceTools) {
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
  })  : _catalog = catalog,
        _mailbox = mailbox,
        _confirmToolCall = confirmToolCall {
    SubAgentRootBridgeRegistry.registerToolExecutor(
      (call, {required sessionKey}) => dispatch(
        call,
        sessionKey: sessionKey,
      ),
    );
  }

  final ToolCatalog _catalog;
  final AgentMailbox _mailbox;
  final Future<bool> Function(ToolCall call) _confirmToolCall;

  Future<ToolResult> dispatch(
    ToolCall call, {
    required String sessionKey,
  }) async {
    final tool = _catalog.byId(call.toolId);
    if (tool == null || !tool.enabled) {
      throw StateError('unknown_tool:${call.toolId}');
    }

    if (tool.requiresConfirmation) {
      if (!_isSubAgentSession(sessionKey)) {
        final approved = await _confirmToolCall(call);
        if (!approved) {
          return const ToolResult.rejected(
            metadata: <String, Object?>{
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
            content: decision.reason ?? 'rejected',
            metadata: <String, Object?>{
              rejectionReasonKey: _normalizeMailboxRejectionReason(
                decision.reason,
              ),
            },
          );
        }
      }
    }

    return tool.execute(call);
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
