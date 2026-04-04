class AutoDreamSessionState {
  const AutoDreamSessionState({
    required this.sessionId,
    required this.lastSummarizedPosition,
    required this.lastSummarizedAt,
    required this.lastMemoryKey,
  });

  factory AutoDreamSessionState.fromDatabaseMap(Map<String, Object?> map) {
    return AutoDreamSessionState(
      sessionId: map['session_id'] as String? ?? '',
      lastSummarizedPosition: (map['last_summarized_position'] as num?)?.toInt() ?? -1,
      lastSummarizedAt: DateTime.parse(map['last_summarized_at'] as String),
      lastMemoryKey: map['last_memory_key'] as String? ?? '',
    );
  }

  final String sessionId;
  final int lastSummarizedPosition;
  final DateTime lastSummarizedAt;
  final String lastMemoryKey;

  Map<String, Object?> toDatabaseMap() {
    return <String, Object?>{
      'session_id': sessionId,
      'last_summarized_position': lastSummarizedPosition,
      'last_summarized_at': lastSummarizedAt.toUtc().toIso8601String(),
      'last_memory_key': lastMemoryKey,
    };
  }
}
