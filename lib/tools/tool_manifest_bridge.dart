import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/tools/tool_manifest_registry.dart';

class ToolManifestBridge {
  ToolManifestBridge(
    this._registry, {
    this.context = const NativeToolContext(),
  });

  final ToolManifestRegistry _registry;
  final NativeToolContext context;

  ToolDefinition toToolDefinition({
    required String toolId,
    required List<double> embedding,
  }) {
    final manifest = _registry.manifestById(toolId);
    if (manifest == null) {
      throw StateError('unknown_tool:$toolId');
    }

    return ToolDefinition(
      id: manifest.id,
      embedding: embedding,
      enabled: manifest.enabled,
      requiresConfirmation: manifest.requiresConfirmation,
      execute: (ToolCall call) async {
        final result = await _registry.execute(
          ToolInvocation(toolId: call.toolId, arguments: call.arguments),
          context: context,
        );
        return ToolResult.success(result.content, metadata: result.metadata);
      },
    );
  }
}
