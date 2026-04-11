import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/tools/native_tool_errors.dart';
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
      description: manifest.description,
      enabled: manifest.enabled,
      requiresConfirmation: manifest.requiresConfirmation,
      argumentSchema: manifest.argumentSchema,
      category: manifest.category,
      tags: manifest.tags,
      source: 'native',
      runtimeMetadata: <String, Object?>{
        'manifestId': manifest.id,
        'category': manifest.category,
      },
      execute: (ToolCall call) async {
        final result = await _registry.execute(
          ToolInvocation(toolId: call.toolId, arguments: call.arguments),
          context: context,
        );
        if (result.isFailure) {
          final error = result.error!;
          return ToolResult.failure(
            result.content,
            toolId: manifest.id,
            callId: call.id,
            status: _statusForNativeError(error.code),
            userVisibleMessage: error.message,
            metadata: <String, Object?>{
              'toolId': manifest.id,
              'category': manifest.category,
              'errorCode': error.wireCode,
              'errorMessage': error.message,
              ...error.details,
              ...result.metadata,
            },
          );
        }
        return ToolResult.success(
          result.content,
          toolId: manifest.id,
          callId: call.id,
          payload: result.metadata,
          metadata: result.metadata,
        );
      },
    );
  }

  ToolResultStatus _statusForNativeError(NativeToolErrorCode code) {
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
}
