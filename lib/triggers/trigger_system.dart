import 'package:openreef/triggers/mini_kairos.dart';
import 'package:openreef/triggers/trigger_models.dart';

abstract class ScheduleSchedulerBackend {
  Future<void> registerSchedule(TriggerConfig trigger);

  Future<void> cancel(String triggerId);
}

abstract class IntervalSchedulerBackend {
  Future<void> registerInterval(TriggerConfig trigger);

  Future<void> cancel(String triggerId);
}

class TriggerSystem {
  TriggerSystem({
    required ScheduleSchedulerBackend scheduleBackend,
    required IntervalSchedulerBackend intervalBackend,
    required MiniKairos miniKairos,
  }) : _scheduleBackend = scheduleBackend,
       _intervalBackend = intervalBackend,
       _miniKairos = miniKairos;

  final ScheduleSchedulerBackend _scheduleBackend;
  final IntervalSchedulerBackend _intervalBackend;
  final MiniKairos _miniKairos;
  final Map<String, TriggerConfig> _triggers = <String, TriggerConfig>{};

  List<TriggerConfig> listTriggers() {
    return _triggers.values.toList(growable: false);
  }

  TriggerConfig? byId(String triggerId) => _triggers[triggerId];

  TriggerValidationResult validate(TriggerConfig trigger) {
    switch (trigger.type) {
      case TriggerType.schedule:
        final spec = trigger.scheduleSpec;
        if (spec == null || trigger.intervalSpec != null) {
          return const TriggerValidationResult.invalid('invalid_schedule_spec');
        }
        if (spec.hour < 0 || spec.hour > 23) {
          return const TriggerValidationResult.invalid('invalid_schedule_hour');
        }
        if (spec.minute < 0 || spec.minute > 59) {
          return const TriggerValidationResult.invalid(
            'invalid_schedule_minute',
          );
        }
      case TriggerType.interval:
        final spec = trigger.intervalSpec;
        if (spec == null || trigger.scheduleSpec != null) {
          return const TriggerValidationResult.invalid('invalid_interval_spec');
        }
        if (spec.every <= Duration.zero) {
          return const TriggerValidationResult.invalid(
            'invalid_interval_duration',
          );
        }
    }

    return const TriggerValidationResult.valid();
  }

  Future<TriggerRegistrationResult> register(TriggerConfig trigger) async {
    final validation = validate(trigger);
    if (!validation.isValid) {
      return TriggerRegistrationResult(
        isRegistered: false,
        triggerId: trigger.id,
        error: validation.error,
      );
    }

    switch (trigger.type) {
      case TriggerType.schedule:
        await _scheduleBackend.registerSchedule(trigger);
      case TriggerType.interval:
        await _intervalBackend.registerInterval(trigger);
    }

    _triggers[trigger.id] = trigger;
    return TriggerRegistrationResult(isRegistered: true, triggerId: trigger.id);
  }

  Future<bool> cancel(String triggerId) async {
    final trigger = _triggers.remove(triggerId);
    if (trigger == null) {
      return false;
    }

    switch (trigger.type) {
      case TriggerType.schedule:
        await _scheduleBackend.cancel(triggerId);
      case TriggerType.interval:
        await _intervalBackend.cancel(triggerId);
    }

    return true;
  }

  Future<KairosDecision> evaluateTrigger(String triggerId) async {
    final trigger = _triggers[triggerId];
    if (trigger == null) {
      throw StateError('unknown_trigger:$triggerId');
    }

    return _miniKairos.evaluate(trigger);
  }
}
