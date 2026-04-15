import 'dart:convert';
import 'package:openreef/agent/agent_orchestrator.dart';
import 'package:openreef/tools/tool_errors.dart';
import 'package:openreef/tools/tool_execution_context.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/agent/sub_inference_service.dart';

class SessionStatusToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'session_status',
    description: 'Get current agent session and active sub-agent count.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final activeCount = context.orchestrator?.activeSubAgentsCount ?? 0;
    return NativeToolExecutionResult.success(
      content: 'Current session: ${context.sessionKey}. Active sub-agents: $activeCount.',
      metadata: <String, Object?>{
        'sessionKey': context.sessionKey,
        'activeSubAgents': activeCount,
      },
    );
  }
}

class AgentSpawnToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'agent_spawn',
    description: 'Spawn a sub-agent to perform a delegated task.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'task', type: ToolArgumentType.string),
      ToolArgumentSpec(
        name: 'preferred_model', 
        type: ToolArgumentType.string, 
        isRequired: false,
      ),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final orchestrator = context.orchestrator;
    if (orchestrator == null) {
      return NativeToolExecutionResult.failure(
        error: const ToolExecutionError(
          code: ToolErrorCode.featureUnavailable,
          message: 'Agent orchestrator is not available in this context.',
        ),
      );
    }

    final task = (invocation.arguments['task'] as String?)?.trim();
    if (task == null || task.isEmpty) {
      return NativeToolExecutionResult.failure(
        error: const ToolExecutionError(
          code: ToolErrorCode.invalidArguments,
          message: 'Task must be provided.',
        ),
      );
    }

    // Usually PreSpawnGuard runs before the actual orchestrator spawn check.
    // For simplicity the orchestrator performs concurrency limit checks.
    final result = await orchestrator.spawn(
      DispatchRequest(
        parentSessionKey: context.sessionKey,
        task: task,
        preferredModel: invocation.arguments['preferred_model'] as String?,
      )
    );

    if (!result.accepted) {
      return NativeToolExecutionResult.failure(
        error: ToolExecutionError(
          code: ToolErrorCode.operationFailed,
          message: 'Sub-agent spawn rejected: ${result.reason}',
        ),
      );
    }

    return NativeToolExecutionResult.success(
      content: 'Sub-agent spawned with session: ${result.sessionKey}',
      metadata: <String, Object?>{
        'sessionKey': result.sessionKey,
      },
    );
  }
}

class ExtFileListToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'file_list',
    description: 'List files in an absolute directory path.',
    category: 'code',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'path', type: ToolArgumentType.string),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final String path = invocation.arguments['path'] as String;
    if (!path.startsWith('/')) {
      return NativeToolExecutionResult.failure(
        error: const ToolExecutionError(
          code: ToolErrorCode.invalidArguments,
          message: 'Path must be absolute.',
        ),
      );
    }
    return NativeToolExecutionResult.success(
      content: '[]',
      metadata: <String, Object?>{
        'path': path,
      },
    );
  }
}

class ExtFileReadToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'file_read',
    description: 'Read a file.',
    category: 'code',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'path', type: ToolArgumentType.string),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(
      content: '',
    );
  }
}

class LlmTaskToolHandler implements NativeToolHandler {
  LlmTaskToolHandler([this._service]);

  static const ToolManifest _manifest = ToolManifest(
    id: 'llm_task',
    description: 'Execute a sub-inference LLM task.',
    category: 'system',
    enabled: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'instruction', type: ToolArgumentType.string),
      ToolArgumentSpec(name: 'input', type: ToolArgumentType.string),
    ],
  );

  final SubInferenceService? _service;

  @override
  ToolManifest get manifest {
    if (_service == null) {
      return ToolManifest(
        id: _manifest.id,
        description: _manifest.description,
        category: _manifest.category,
        enabled: false,
        argumentSchema: _manifest.argumentSchema,
      );
    }
    return _manifest;
  }

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    if (_service == null) {
      return NativeToolExecutionResult.failure(
        error: const ToolExecutionError(
          code: ToolErrorCode.featureUnavailable,
          message: 'SubInferenceService unavailable.',
        ),
      );
    }

    final instruction = invocation.arguments['instruction'] as String;
    final input = invocation.arguments['input'] as String;
    final result = await _service!.infer(instruction, input);

    return NativeToolExecutionResult.success(
      content: result,
      metadata: <String, Object?>{
        'instruction': instruction,
      },
    );
  }
}
