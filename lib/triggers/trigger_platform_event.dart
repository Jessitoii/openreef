class TriggerPlatformEvent {
  const TriggerPlatformEvent({
    required this.triggerId,
    this.deliveryId,
    required this.type,
    required this.scheduledAtEpochMs,
    required this.deliveredAtEpochMs,
    this.enqueuedAtEpochMs,
    this.deliveryStage,
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
      deliveryId: _readOptionalString(map, 'deliveryId'),
      type: _readRequiredString(map, 'type'),
      scheduledAtEpochMs: _readRequiredInt(map, 'scheduledAtEpochMs'),
      deliveredAtEpochMs: _readRequiredInt(map, 'deliveredAtEpochMs'),
      enqueuedAtEpochMs: _readOptionalInt(map, 'enqueuedAtEpochMs'),
      deliveryStage: _readOptionalString(map, 'deliveryStage'),
      payload: _coercePayloadMap(map['payload']),
    );
  }

  final String triggerId;
  final String? deliveryId;
  final String type;
  final int scheduledAtEpochMs;
  final int deliveredAtEpochMs;
  final int? enqueuedAtEpochMs;
  final String? deliveryStage;
  final Map<String, Object?> payload;

  DateTime get scheduledAt =>
      DateTime.fromMillisecondsSinceEpoch(scheduledAtEpochMs);

  DateTime get deliveredAt =>
      DateTime.fromMillisecondsSinceEpoch(deliveredAtEpochMs);

  DateTime? get enqueuedAt => enqueuedAtEpochMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(enqueuedAtEpochMs!);

  static String _readRequiredString(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw ArgumentError.value(value, key, 'Expected non-empty string');
  }

  static String? _readOptionalString(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return value.toString();
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

  static int? _readOptionalInt(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value == null) {
      return null;
    }
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
