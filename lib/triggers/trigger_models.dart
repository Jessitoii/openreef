enum TriggerType { schedule, interval }

enum TriggerPriority { low, normal, high }

enum ScheduleRecurrence { daily }

class ScheduleTriggerSpec {
  const ScheduleTriggerSpec({
    required this.hour,
    required this.minute,
    this.recurrence = ScheduleRecurrence.daily,
  });

  final int hour;
  final int minute;
  final ScheduleRecurrence recurrence;
}

class IntervalTriggerSpec {
  const IntervalTriggerSpec({required this.every});

  final Duration every;
}

class TriggerConfig {
  const TriggerConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.priority,
    this.scheduleSpec,
    this.intervalSpec,
    this.requiresUserAttention = false,
    this.isExpensive = false,
    this.payload = const <String, Object?>{},
  });

  final String id;
  final String name;
  final TriggerType type;
  final TriggerPriority priority;
  final ScheduleTriggerSpec? scheduleSpec;
  final IntervalTriggerSpec? intervalSpec;
  final bool requiresUserAttention;
  final bool isExpensive;
  final Map<String, Object?> payload;
}

class TriggerValidationResult {
  const TriggerValidationResult._({required this.isValid, this.error});

  const TriggerValidationResult.valid() : this._(isValid: true);

  const TriggerValidationResult.invalid(String error)
    : this._(isValid: false, error: error);

  final bool isValid;
  final String? error;
}

class TriggerRegistrationResult {
  const TriggerRegistrationResult({
    required this.isRegistered,
    required this.triggerId,
    this.error,
  });

  final bool isRegistered;
  final String triggerId;
  final String? error;
}
