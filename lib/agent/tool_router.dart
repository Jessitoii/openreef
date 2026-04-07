import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/subagent_runner.dart';

class ToolDefinition {
  const ToolDefinition({
    required this.id,
    required this.embedding,
    required this.execute,
    this.enabled = true,
    this.requiresConfirmation = false,
  });

  final String id;
  final List<double> embedding;
  final Future<ToolResult> Function(ToolCall call) execute;
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
