enum ToolErrorCode {
  permissionDenied,
  permissionRequired,
  featureUnavailable,
  appUnavailable,
  invalidArguments,
  operationFailed,
  unsupported,
  semanticError,
  runtimeError,
  nativeError,
  mcpError,
}

class ToolExecutionError {
  const ToolExecutionError({
    required this.code,
    required this.message,
    this.innerError,
  });

  final ToolErrorCode code;
  final String message;
  final Object? innerError;

  String get id {
    return switch (code) {
      ToolErrorCode.permissionDenied => 'permission_denied',
      ToolErrorCode.permissionRequired => 'permission_required',
      ToolErrorCode.featureUnavailable => 'feature_unavailable',
      ToolErrorCode.appUnavailable => 'app_unavailable',
      ToolErrorCode.invalidArguments => 'invalid_arguments',
      ToolErrorCode.operationFailed => 'operation_failed',
      ToolErrorCode.unsupported => 'unsupported',
      ToolErrorCode.semanticError => 'semantic_error',
      ToolErrorCode.runtimeError => 'runtime_error',
      ToolErrorCode.nativeError => 'native_error',
      ToolErrorCode.mcpError => 'mcp_error',
    };
  }
}

class ToolExecutionException implements Exception {
  const ToolExecutionException(this.error);

  final ToolExecutionError error;

  @override
  String toString() => 'ToolExecutionException: ${error.message} (${error.code})';
}
