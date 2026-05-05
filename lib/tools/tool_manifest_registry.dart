import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/tools/tool_errors.dart';
import 'package:openreef/tools/tool_execution_context.dart';

class ToolManifestRegistry {
  ToolManifestRegistry(List<NativeToolHandler> handlers)
    : _handlers = _handlersById(handlers);

  final Map<String, NativeToolHandler> _handlers;

  List<ToolManifest> listManifests() {
    return _handlers.values
        .map((handler) => handler.manifest)
        .toList(growable: false);
  }

  ToolManifest? manifestById(String toolId) => _handlers[toolId]?.manifest;

  NativeToolHandler? handlerById(String toolId) => _handlers[toolId];

  ToolValidationResult validate(ToolInvocation invocation) {
    final handler = _handlers[invocation.toolId];
    if (handler == null) {
      return ToolValidationResult.invalid('unknown_tool:${invocation.toolId}');
    }

    final manifest = handler.manifest;
    if (!manifest.enabled) {
      return ToolValidationResult.invalid('disabled_tool:${manifest.id}');
    }

    final normalized = <String, Object?>{};
    for (final spec in manifest.argumentSchema) {
      final hasValue = invocation.arguments.containsKey(spec.name);
      final value = invocation.arguments[spec.name];
      if (!hasValue || value == null) {
        if (spec.isRequired) {
          return ToolValidationResult.invalid('missing_argument:${spec.name}');
        }
        continue;
      }

      final normalizedValue = _normalizeArgument(spec, value);
      if (normalizedValue case _NormalizationFailure(:final message)) {
        return ToolValidationResult.invalid(message);
      }

      normalized[spec.name] = normalizedValue as Object?;
    }

    return ToolValidationResult.valid(normalized);
  }

  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation, {
    ToolExecutionContext context = const ToolExecutionContext(
      sessionKey: 'agent:main',
    ),
  }) async {
    try {
      final validation = validate(invocation);
      if (!validation.isValid) {
        return NativeToolExecutionResult.failure(
          error: ToolExecutionError(
            code: ToolErrorCode.invalidArguments,
            message: validation.error!,
          ),
        );
      }

      final handler = _handlers[invocation.toolId]!;
      final normalizedInvocation = ToolInvocation(
        toolId: invocation.toolId,
        arguments: validation.normalizedArguments,
      );
      final result = await handler.execute(normalizedInvocation, context);
      return switch (result.status) {
        NativeToolExecutionStatus.success => NativeToolExecutionResult.success(
          content: result.content,
          metadata: <String, Object?>{
            'toolId': handler.manifest.id,
            'category': handler.manifest.category,
            ...result.metadata,
          },
        ),
        NativeToolExecutionStatus.failure => NativeToolExecutionResult.failure(
          error: result.error!,
          metadata: <String, Object?>{
            'toolId': handler.manifest.id,
            'category': handler.manifest.category,
            ...result.metadata,
          },
        ),
      };
    } catch (e) {
      return NativeToolExecutionResult.failure(
        error: ToolExecutionError(
          code: ToolErrorCode.nativeError,
          message: 'Tool execution internal exception: $e',
          innerError: e,
        ),
      );
    }
  }

  Object _normalizeArgument(ToolArgumentSpec spec, Object value) {
    switch (spec.type) {
      case ToolArgumentType.string:
        if (value is! String) {
          return _NormalizationFailure('invalid_argument:${spec.name}');
        }
        return _validateAllowedValues(spec, value);
      case ToolArgumentType.integer:
        if (value is int) {
          return _validateNumericRange(spec, value);
        }
        if (value is num && value == value.roundToDouble()) {
          return _validateNumericRange(spec, value.toInt());
        }
        return _NormalizationFailure('invalid_argument:${spec.name}');
      case ToolArgumentType.doubleValue:
        if (value is! num) {
          return _NormalizationFailure('invalid_argument:${spec.name}');
        }
        return _validateNumericRange(spec, value.toDouble());
      case ToolArgumentType.boolean:
        if (value is! bool) {
          return _NormalizationFailure('invalid_argument:${spec.name}');
        }
        return _validateAllowedValues(spec, value);
    }
  }

  Object _validateNumericRange(ToolArgumentSpec spec, num value) {
    if (spec.minimum != null && value < spec.minimum!) {
      return _NormalizationFailure('argument_out_of_range:${spec.name}');
    }
    if (spec.maximum != null && value > spec.maximum!) {
      return _NormalizationFailure('argument_out_of_range:${spec.name}');
    }
    return _validateAllowedValues(spec, value);
  }

  Object _validateAllowedValues(ToolArgumentSpec spec, Object value) {
    if (spec.allowedValues.isNotEmpty && !spec.allowedValues.contains(value)) {
      return _NormalizationFailure('argument_not_allowed:${spec.name}');
    }
    return value;
  }
}

Map<String, NativeToolHandler> _handlersById(List<NativeToolHandler> handlers) {
  final byId = <String, NativeToolHandler>{};
  for (final handler in handlers) {
    final id = handler.manifest.id;
    if (byId.containsKey(id)) {
      throw StateError('duplicate_tool_id:$id');
    }
    byId[id] = handler;
  }
  return byId;
}

class _NormalizationFailure {
  const _NormalizationFailure(this.message);

  final String message;
}
