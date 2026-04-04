class TriggerPlatformEvent {
  const TriggerPlatformEvent({
    required this.triggerId,
    required this.type,
    required this.scheduledAtEpochMs,
    required this.deliveredAtEpochMs,
    this.payload = const <String, Object?>{},
  });

  factory TriggerPlatformEvent.fromPlatformPayload(dynamic payload) {
    final map = switch (payload) {
      final Map<dynamic, dynamic> value => value,
      _ => throw ArgumentError.value(
        payload,
        'payload',
        'Expected map payload',
      ),
    };

    return TriggerPlatformEvent(
      triggerId: _readRequiredString(map, 'triggerId'),
      type: _readRequiredString(map, 'type'),
      scheduledAtEpochMs: _readRequiredInt(map, 'scheduledAtEpochMs'),
      deliveredAtEpochMs: _readRequiredInt(map, 'deliveredAtEpochMs'),
      payload: _coercePayloadMap(map['payload']),
    );
  }

  final String triggerId;
  final String type;
  final int scheduledAtEpochMs;
  final int deliveredAtEpochMs;
  final Map<String, Object?> payload;

  DateTime get scheduledAt =>
      DateTime.fromMillisecondsSinceEpoch(scheduledAtEpochMs);

  DateTime get deliveredAt =>
      DateTime.fromMillisecondsSinceEpoch(deliveredAtEpochMs);

  static String _readRequiredString(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw ArgumentError.value(value, key, 'Expected non-empty string');
  }

  static int _readRequiredInt(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    throw ArgumentError.value(value, key, 'Expected integer');
  }

  static Map<String, Object?> _coercePayloadMap(Object? rawPayload) {
    final payload = switch (rawPayload) {
      null => const <String, Object?>{},
      final Map<dynamic, dynamic> value => value,
      _ => throw ArgumentError.value(
        rawPayload,
        'payload',
        'Expected payload map',
      ),
    };

    return Map<String, Object?>.unmodifiable(
      payload.map(
        (key, value) => MapEntry(key.toString(), _coercePrimitiveValue(value)),
      ),
    );
  }

  static Object? _coercePrimitiveValue(Object? value) {
    return switch (value) {
      null || bool() || num() || String() => value,
      _ => value.toString(),
    };
  }
}
