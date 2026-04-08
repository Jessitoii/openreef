enum NativeToolErrorCode {
  permissionDenied,
  permissionRequired,
  featureUnavailable,
  appUnavailable,
  invalidArguments,
  operationFailed,
  unsupported,
}

class NativeToolError {
  const NativeToolError({
    required this.code,
    required this.message,
    this.details = const <String, Object?>{},
  });

  final NativeToolErrorCode code;
  final String message;
  final Map<String, Object?> details;

  String get wireCode => switch (code) {
    NativeToolErrorCode.permissionDenied => 'permission_denied',
    NativeToolErrorCode.permissionRequired => 'permission_required',
    NativeToolErrorCode.featureUnavailable => 'feature_unavailable',
    NativeToolErrorCode.appUnavailable => 'app_unavailable',
    NativeToolErrorCode.invalidArguments => 'invalid_arguments',
    NativeToolErrorCode.operationFailed => 'operation_failed',
    NativeToolErrorCode.unsupported => 'unsupported',
  };
}

class NativeToolException implements Exception {
  const NativeToolException(this.error);

  final NativeToolError error;

  @override
  String toString() => error.message;
}
