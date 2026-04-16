import 'dart:async';

import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/mcp/mcp_client.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_tool_manifest_adapter.dart';
import 'package:openreef/tools/tool_manifest.dart';

class McpRuntimeSourceBinding {
  const McpRuntimeSourceBinding({
    required this.sourceId,
    required this.client,
    required this.isActive,
    required this.requiresTrust,
    required this.trusted,
    required this.requiresManualSecretEntry,
    required this.hasRequiredSecretMaterial,
  });

  final String sourceId;
  final McpClient client;
  final bool Function() isActive;
  final bool requiresTrust;
  final bool trusted;
  final bool requiresManualSecretEntry;
  final Future<bool> Function() hasRequiredSecretMaterial;
}

class McpImportedToolSnapshot {
  const McpImportedToolSnapshot({required this.importedToolIds});

  final List<String> importedToolIds;

  int get importedToolCount => importedToolIds.length;
}

class McpRuntimeCoordinator {
  McpRuntimeCoordinator({
    required RuntimeToolCatalog toolCatalog,
    required Future<List<double>> Function(String text) embedText,
    AgentTaskExecutor? taskExecutor,
    McpToolManifestAdapter manifestAdapter = const McpToolManifestAdapter(),
  }) : _toolCatalog = toolCatalog,
       _embedText = embedText,
       _taskExecutor = taskExecutor,
       _manifestAdapter = manifestAdapter;

  static const String category = 'mcp';
  static const String missingSessionError = 'mcp_session_missing';
  static const String staleSessionError = 'mcp_session_stale';
  static const String untrustedSourceError = 'mcp_source_untrusted';
  static const String secretRequiredError = 'mcp_secret_required';

  final RuntimeToolCatalog _toolCatalog;
  final Future<List<double>> Function(String text) _embedText;
  final AgentTaskExecutor? _taskExecutor;
  final McpToolManifestAdapter _manifestAdapter;
  final Map<String, _McpRuntimeSource> _sources = <String, _McpRuntimeSource>{};
  final StreamController<McpRuntimeEvent> _events =
      StreamController<McpRuntimeEvent>.broadcast();

  Stream<McpRuntimeEvent> get events => _events.stream;

  Future<McpImportedToolSnapshot> replaceSourceTools({
    required McpRuntimeSourceBinding binding,
    required List<McpTool> discoveredTools,
  }) async {
    final runtimeSource = _McpRuntimeSource(binding: binding);
    final importedTools = <ToolDefinition>[];
    final importedToolIds = <String>[];

    for (final tool in discoveredTools) {
      ToolManifest? manifest;
      try {
        manifest = _manifestAdapter.adapt(tool);
      } on McpToolAdaptationException {
        continue;
      }

      final runtimeToolId = '${binding.sourceId}/${tool.name}';
      final embedding = await _embedText('${tool.name} ${tool.description}');
      final hasSecret = await binding.hasRequiredSecretMaterial();
      importedTools.add(
        ToolDefinition(
          id: runtimeToolId,
          embedding: embedding,
          description: manifest.description,
          enabled: manifest.enabled,
          requiresConfirmation: manifest.requiresConfirmation,
          argumentSchema: manifest.argumentSchema,
          category: manifest.category,
          tags: manifest.tags,
          source: category,
          runtimeMetadata: <String, Object?>{
            'sourceId': binding.sourceId,
            'mcpToolName': tool.name,
            'manifestId': manifest.id,
            'namespace': binding.sourceId,
            'mcpActive': binding.isActive(),
            'mcpTrusted': !binding.requiresTrust || binding.trusted,
            'mcpHasSecret': !binding.requiresManualSecretEntry && hasSecret,
            'mcpRequiresTrust': binding.requiresTrust,
            'mcpRequiresManualSecretEntry': binding.requiresManualSecretEntry,
          },
          execute: (call) => executeTool(
            sourceId: binding.sourceId,
            runtimeToolId: runtimeToolId,
            mcpToolName: tool.name,
            arguments: call.arguments,
          ),
        ),
      );
      importedToolIds.add(runtimeToolId);
    }

    _toolCatalog.replaceSourceTools(binding.sourceId, importedTools);
    _sources[binding.sourceId] = runtimeSource;
    return McpImportedToolSnapshot(
      importedToolIds: List<String>.unmodifiable(importedToolIds),
    );
  }

  void removeSource(String sourceId) {
    _sources.remove(sourceId);
    _toolCatalog.removeSourceTools(sourceId);
  }

  void emitSourceEvent(McpRuntimeEvent event) {
    if (_sources.containsKey(event.sourceId)) {
      _events.add(event);
      unawaited(_executeRuntimeEvent(event));
    }
  }

  int importedToolCountForSource(String sourceId) {
    return _toolCatalog.listSourceTools(sourceId).length;
  }

  List<String> importedToolIdsForSource(String sourceId) {
    return _toolCatalog
        .listSourceTools(sourceId)
        .map((tool) => tool.id)
        .toList(growable: false);
  }

  Future<ExecutionResult?> executeEvent({
    required String sessionKey,
    required String eventName,
    required String prompt,
    Map<String, dynamic>? metadata,
    ExecutionVisibility visibility = ExecutionVisibility.background,
  }) async {
    final taskExecutor = _taskExecutor;
    if (taskExecutor == null) {
      return null;
    }
    return taskExecutor.execute(
      ExecutionRequest.fromMcpEvent(
        sessionKey: sessionKey,
        prompt: prompt,
        visibility: visibility,
        metadata: <String, dynamic>{
          'eventName': eventName,
          if (metadata != null) ...metadata,
        },
      ),
    );
  }

  Future<void> _executeRuntimeEvent(McpRuntimeEvent event) async {
    await executeEvent(
      sessionKey: 'mcp:${event.sourceId}',
      eventName: event.eventName,
      prompt:
          event.payload['prompt'] as String? ??
          'Handle MCP event ${event.eventName} from ${event.sourceId}.',
      metadata: <String, dynamic>{
        'sourceId': event.sourceId,
        'transportEvent': event.transportEvent,
        'payload': event.payload,
      },
    );
  }

  Future<ToolResult> executeTool({
    required String sourceId,
    required String runtimeToolId,
    required String mcpToolName,
    required Map<String, Object?> arguments,
  }) async {
    final source = _sources[sourceId];
    if (source == null) {
      return _failure(
        runtimeToolId: runtimeToolId,
        status: ToolResultStatus.unavailable,
        summary: 'MCP source session is missing.',
        errorCode: missingSessionError,
        retryable: true,
      );
    }
    if (!source.binding.isActive()) {
      return _failure(
        runtimeToolId: runtimeToolId,
        status: ToolResultStatus.unavailable,
        summary: 'MCP source session is stale.',
        errorCode: staleSessionError,
        retryable: true,
      );
    }
    if (source.binding.requiresTrust && !source.binding.trusted) {
      return _failure(
        runtimeToolId: runtimeToolId,
        status: ToolResultStatus.permissionDenied,
        summary: 'MCP source is not trusted.',
        errorCode: untrustedSourceError,
      );
    }
    if (source.binding.requiresManualSecretEntry) {
      return _failure(
        runtimeToolId: runtimeToolId,
        status: ToolResultStatus.permissionDenied,
        summary: 'MCP source requires secret material.',
        errorCode: secretRequiredError,
      );
    }
    final hasRequiredSecretMaterial = await source.binding
        .hasRequiredSecretMaterial();
    if (!hasRequiredSecretMaterial) {
      return _failure(
        runtimeToolId: runtimeToolId,
        status: ToolResultStatus.permissionDenied,
        summary: 'MCP source requires secret material.',
        errorCode: secretRequiredError,
      );
    }

    late final McpToolCallResult result;
    try {
      result = await source.binding.client.callTool(
        name: mcpToolName,
        arguments: arguments,
      );
    } on McpProtocolException catch (error) {
      return _failure(
        runtimeToolId: runtimeToolId,
        status: error.message == 'client_not_initialized'
            ? ToolResultStatus.unavailable
            : ToolResultStatus.executionError,
        summary: 'MCP tool call failed: ${error.message}',
        errorCode: error.message,
        retryable: error.message == 'client_not_initialized',
      );
    } on McpTransportException catch (error) {
      return _failure(
        runtimeToolId: runtimeToolId,
        status: ToolResultStatus.unavailable,
        summary: 'MCP transport failed: ${error.message}',
        errorCode: 'mcp_transport_error',
        retryable: true,
      );
    } catch (error) {
      return _failure(
        runtimeToolId: runtimeToolId,
        status: ToolResultStatus.executionError,
        summary: 'MCP tool call failed: $error',
        errorCode: 'mcp_call_exception',
      );
    }
    final payload = <String, Object?>{
      'mcpToolName': mcpToolName,
      if (result.structuredContent.isNotEmpty)
        'structuredContent': result.structuredContent,
    };
    if (result.isError) {
      return ToolResult.failure(
        result.contentText.isEmpty
            ? 'MCP tool returned an error.'
            : result.contentText,
        toolId: runtimeToolId,
        status: ToolResultStatus.executionError,
        payload: payload,
        metadata: <String, Object?>{
          'toolId': runtimeToolId,
          'category': category,
          'mcpToolName': mcpToolName,
          'reason': 'mcp_tool_error',
          'errorCode': 'mcp_tool_error',
          'isError': true,
        },
      );
    }
    return ToolResult.success(
      result.contentText,
      toolId: runtimeToolId,
      payload: payload,
      metadata: <String, Object?>{
        'toolId': runtimeToolId,
        'category': category,
        'mcpToolName': mcpToolName,
        'isError': result.isError,
        if (result.structuredContent.isNotEmpty)
          'structuredContent': result.structuredContent,
      },
    );
  }

  ToolResult _failure({
    required String runtimeToolId,
    required ToolResultStatus status,
    required String summary,
    required String errorCode,
    bool retryable = false,
  }) {
    return ToolResult.failure(
      summary,
      toolId: runtimeToolId,
      status: status,
      retryable: retryable,
      userVisibleMessage: summary,
      metadata: <String, Object?>{
        'toolId': runtimeToolId,
        'category': category,
        'reason': errorCode,
        'errorCode': errorCode,
      },
    );
  }
}

class _McpRuntimeSource {
  const _McpRuntimeSource({required this.binding});

  final McpRuntimeSourceBinding binding;
}
