import 'dart:async';

import 'package:openreef/tools/native_tool_adapters.dart';
import 'package:openreef/triggers/trigger_models.dart';

typedef BatteryTimerFactory = Object Function(
  Duration every,
  void Function() onTick,
);

typedef BatteryTimerCanceler = void Function(Object handle);

class BatteryTriggerDelivery {
  const BatteryTriggerDelivery({
    required this.triggerId,
    required this.payload,
  });

  final String triggerId;
  final Map<String, Object?> payload;
}

abstract class BatterySchedulerBackend {
  Future<void> registerBattery(TriggerConfig trigger);

  Future<void> cancel(String triggerId);
}

class PollingBatterySchedulerBackend implements BatterySchedulerBackend {
  PollingBatterySchedulerBackend({
    required BatteryAdapter batteryAdapter,
    required Future<void> Function(BatteryTriggerDelivery delivery)
    onTriggerFired,
    this.pollInterval = const Duration(minutes: 5),
    BatteryTimerFactory? timerFactory,
    BatteryTimerCanceler? timerCanceler,
  }) : _batteryAdapter = batteryAdapter,
       _onTriggerFired = onTriggerFired,
       _timerFactory = timerFactory ?? _defaultTimerFactory,
       _timerCanceler = timerCanceler ?? _defaultTimerCanceler;

  final BatteryAdapter _batteryAdapter;
  final Future<void> Function(BatteryTriggerDelivery delivery) _onTriggerFired;
  final Duration pollInterval;
  final BatteryTimerFactory _timerFactory;
  final BatteryTimerCanceler _timerCanceler;
  final Map<String, Object> _timers = <String, Object>{};
  final Map<String, _BatteryObservation> _lastObservations =
      <String, _BatteryObservation>{};
  final Map<String, TriggerConfig> _triggers = <String, TriggerConfig>{};
  bool _pollInFlight = false;

  Iterable<String> get activeTriggerIds => _timers.keys;

  @override
  Future<void> cancel(String triggerId) async {
    final handle = _timers.remove(triggerId);
    if (handle != null) {
      _timerCanceler(handle);
    }
    _triggers.remove(triggerId);
    _lastObservations.remove(triggerId);
  }

  @override
  Future<void> registerBattery(TriggerConfig trigger) async {
    await cancel(trigger.id);
    _triggers[trigger.id] = trigger;
    _timers[trigger.id] = _timerFactory(pollInterval, _tick);
    await _pollOnce();
  }

  Future<void> _tick() async {
    await _pollOnce();
  }

  Future<void> _pollOnce() async {
    if (_pollInFlight || _triggers.isEmpty) {
      return;
    }
    _pollInFlight = true;
    try {
      final snapshot = await _batteryAdapter.readBatteryInfo();
      for (final trigger in _triggers.values) {
        final spec = trigger.batterySpec;
        if (spec == null) {
          continue;
        }
        final previous = _lastObservations[trigger.id];
        final current = _BatteryObservation(
          level: snapshot.level,
          state: snapshot.state.name,
        );
        _lastObservations[trigger.id] = current;
        if (!_shouldFire(spec, previous, current)) {
          continue;
        }
        await _onTriggerFired(
          BatteryTriggerDelivery(
            triggerId: trigger.id,
            payload: <String, Object?>{
              'batteryLevel': snapshot.level,
              'batteryState': snapshot.state.name,
              'isLowPowerMode': snapshot.isLowPowerMode,
            },
          ),
        );
      }
    } finally {
      _pollInFlight = false;
    }
  }

  bool _shouldFire(
    BatteryTriggerSpec spec,
    _BatteryObservation? previous,
    _BatteryObservation current,
  ) {
    switch (spec.condition) {
      case BatteryTriggerCondition.levelAtOrBelow:
        final threshold = spec.level;
        if (threshold == null) {
          return false;
        }
        if (current.level > threshold) {
          return false;
        }
        return previous == null || previous.level > threshold;
      case BatteryTriggerCondition.levelAtOrAbove:
        final threshold = spec.level;
        if (threshold == null) {
          return false;
        }
        if (current.level < threshold) {
          return false;
        }
        return previous == null || previous.level < threshold;
      case BatteryTriggerCondition.stateChanged:
        final requiredState = spec.requiredState;
        if (requiredState != null && current.state != requiredState) {
          return false;
        }
        return previous == null || previous.state != current.state;
    }
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

class _BatteryObservation {
  const _BatteryObservation({
    required this.level,
    required this.state,
  });

  final int level;
  final String state;
}
