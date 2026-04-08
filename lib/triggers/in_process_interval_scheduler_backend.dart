import 'dart:async';

import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_system.dart';

typedef IntervalTimerFactory = Object Function(
  Duration every,
  void Function() onTick,
);

typedef IntervalTimerCanceler = void Function(Object handle);

class InProcessIntervalSchedulerBackend implements IntervalSchedulerBackend {
  InProcessIntervalSchedulerBackend({
    required Future<void> Function(String triggerId) onTriggerFired,
    IntervalTimerFactory? timerFactory,
    IntervalTimerCanceler? timerCanceler,
  }) : _onTriggerFired = onTriggerFired,
       _timerFactory = timerFactory ?? _defaultTimerFactory,
       _timerCanceler = timerCanceler ?? _defaultTimerCanceler;

  final Future<void> Function(String triggerId) _onTriggerFired;
  final IntervalTimerFactory _timerFactory;
  final IntervalTimerCanceler _timerCanceler;
  final Map<String, Object> _timers = <String, Object>{};

  Iterable<String> get activeTriggerIds => _timers.keys;

  @override
  Future<void> cancel(String triggerId) async {
    final handle = _timers.remove(triggerId);
    if (handle != null) {
      _timerCanceler(handle);
    }
  }

  @override
  Future<void> registerInterval(TriggerConfig trigger) async {
    final spec = trigger.intervalSpec;
    if (spec == null) {
      throw StateError('interval trigger missing intervalSpec');
    }

    await cancel(trigger.id);
    _timers[trigger.id] = _timerFactory(spec.every, () {
      unawaited(_onTriggerFired(trigger.id));
    });
  }

  static Object _defaultTimerFactory(
    Duration every,
    void Function() onTick,
  ) {
    return Timer.periodic(every, (_) => onTick());
  }

  static void _defaultTimerCanceler(Object handle) {
    (handle as Timer).cancel();
  }
}
