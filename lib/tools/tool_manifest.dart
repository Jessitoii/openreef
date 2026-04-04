enum ToolArgumentType { string, integer, doubleValue, boolean }

class ToolArgumentSpec {
  const ToolArgumentSpec({
    required this.name,
    required this.type,
    this.description = '',
    this.isRequired = true,
    this.minimum,
    this.maximum,
    this.allowedValues = const <Object?>[],
  });

  final String name;
  final ToolArgumentType type;
  final String description;
  final bool isRequired;
  final num? minimum;
  final num? maximum;
  final List<Object?> allowedValues;
}

class ToolManifest {
  const ToolManifest({
    required this.id,
    required this.description,
    required this.category,
    required this.argumentSchema,
    this.requiresConfirmation = false,
    this.enabled = true,
    this.tags = const <String>[],
  });

  final String id;
  final String description;
  final String category;
  final bool requiresConfirmation;
  final bool enabled;
  final List<ToolArgumentSpec> argumentSchema;
  final List<String> tags;
}

class ToolValidationResult {
  const ToolValidationResult._({
    required this.isValid,
    this.normalizedArguments = const <String, Object?>{},
    this.error,
  });

  const ToolValidationResult.valid(Map<String, Object?> normalizedArguments)
    : this._(isValid: true, normalizedArguments: normalizedArguments);

  const ToolValidationResult.invalid(String error)
    : this._(isValid: false, error: error);

  final bool isValid;
  final Map<String, Object?> normalizedArguments;
  final String? error;
}

class ToolInvocation {
  const ToolInvocation({
    required this.toolId,
    this.arguments = const <String, Object?>{},
  });

  final String toolId;
  final Map<String, Object?> arguments;
}

class NativeToolContext {
  const NativeToolContext({DateTime Function()? clock}) : _clock = clock;

  final DateTime Function()? _clock;

  DateTime now() => _clock?.call() ?? DateTime.now().toUtc();
}

class NativeToolExecutionResult {
  const NativeToolExecutionResult({
    required this.content,
    this.metadata = const <String, Object?>{},
  });

  final String content;
  final Map<String, Object?> metadata;
}

abstract class NativeToolHandler {
  ToolManifest get manifest;

  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    NativeToolContext context,
  );
}
