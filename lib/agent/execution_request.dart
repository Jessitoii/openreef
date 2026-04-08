enum ExecutionSource { user, trigger, schedule, mcpEvent }

enum ExecutionVisibility { chat, background, chatAndBackground }

class ExecutionRequest {
  const ExecutionRequest({
    required this.id,
    required this.source,
    required this.sessionKey,
    required this.prompt,
    required this.visibility,
    required this.createdAt,
    this.metadata,
  });

  final String id;
  final ExecutionSource source;
  final String sessionKey;
  final String prompt;
  final Map<String, dynamic>? metadata;
  final ExecutionVisibility visibility;
  final DateTime createdAt;

  factory ExecutionRequest.fromUserMessage({
    required String sessionKey,
    required String prompt,
    Map<String, dynamic>? metadata,
    String? id,
    DateTime? createdAt,
    ExecutionVisibility visibility = ExecutionVisibility.chat,
  }) {
    final timestamp = (createdAt ?? DateTime.now()).toUtc();
    return ExecutionRequest(
      id: id ?? _defaultId(ExecutionSource.user, timestamp),
      source: ExecutionSource.user,
      sessionKey: sessionKey,
      prompt: prompt,
      metadata: metadata == null ? null : Map<String, dynamic>.from(metadata),
      visibility: visibility,
      createdAt: timestamp,
    );
  }

  factory ExecutionRequest.fromTrigger({
    required String sessionKey,
    required String prompt,
    required ExecutionSource source,
    Map<String, dynamic>? metadata,
    String? id,
    DateTime? createdAt,
    ExecutionVisibility visibility = ExecutionVisibility.background,
  }) {
    assert(
      source == ExecutionSource.trigger || source == ExecutionSource.schedule,
      'Trigger execution source must be trigger or schedule.',
    );
    final timestamp = (createdAt ?? DateTime.now()).toUtc();
    return ExecutionRequest(
      id: id ?? _defaultId(source, timestamp),
      source: source,
      sessionKey: sessionKey,
      prompt: prompt,
      metadata: metadata == null ? null : Map<String, dynamic>.from(metadata),
      visibility: visibility,
      createdAt: timestamp,
    );
  }

  factory ExecutionRequest.fromMcpEvent({
    required String sessionKey,
    required String prompt,
    Map<String, dynamic>? metadata,
    String? id,
    DateTime? createdAt,
    ExecutionVisibility visibility = ExecutionVisibility.background,
  }) {
    final timestamp = (createdAt ?? DateTime.now()).toUtc();
    return ExecutionRequest(
      id: id ?? _defaultId(ExecutionSource.mcpEvent, timestamp),
      source: ExecutionSource.mcpEvent,
      sessionKey: sessionKey,
      prompt: prompt,
      metadata: metadata == null ? null : Map<String, dynamic>.from(metadata),
      visibility: visibility,
      createdAt: timestamp,
    );
  }

  static String _defaultId(ExecutionSource source, DateTime timestamp) {
    return '${source.name}_${timestamp.microsecondsSinceEpoch}';
  }
}
