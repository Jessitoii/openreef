import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/triggers/mini_kairos.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_system.dart';

void main() {
  late _RecordingScheduleBackend scheduleBackend;
  late _RecordingIntervalBackend intervalBackend;

  TriggerSystem buildSystem({
    KairosContext context = const KairosContext(
      isAppForeground: true,
      batteryLevel: 80,
      activeSubAgents: 0,
    ),
    MiniKairosPolicy policy = const MiniKairosPolicy(),
  }) {
    scheduleBackend = _RecordingScheduleBackend();
    intervalBackend = _RecordingIntervalBackend();
    return TriggerSystem(
      scheduleBackend: scheduleBackend,
      intervalBackend: intervalBackend,
      miniKairos: MiniKairos(
        contextLoader: () async => context,
        policy: policy,
      ),
    );
  }

  test('registering SCHEDULE routes to the schedule backend', () async {
    final system = buildSystem();
    final trigger = TriggerConfig(
      id: 'briefing',
      name: 'Morning briefing',
      type: TriggerType.schedule,
      priority: TriggerPriority.normal,
      scheduleSpec: const ScheduleTriggerSpec(hour: 8, minute: 0),
    );

    final result = await system.register(trigger);

    expect(result.isRegistered, isTrue);
    expect(scheduleBackend.registeredIds, <String>['briefing']);
    expect(intervalBackend.registeredIds, isEmpty);
  });

  test('registering INTERVAL routes to the interval backend', () async {
    final system = buildSystem();
    final trigger = TriggerConfig(
      id: 'poll_inputs',
      name: 'Poll inboxes',
      type: TriggerType.interval,
      priority: TriggerPriority.low,
      intervalSpec: const IntervalTriggerSpec(every: Duration(minutes: 30)),
    );

    final result = await system.register(trigger);

    expect(result.isRegistered, isTrue);
    expect(intervalBackend.registeredIds, <String>['poll_inputs']);
    expect(scheduleBackend.registeredIds, isEmpty);
  });

  test('invalid trigger specs are rejected', () async {
    final system = buildSystem();
    final invalidSchedule = TriggerConfig(
      id: 'bad_schedule',
      name: 'Bad schedule',
      type: TriggerType.schedule,
      priority: TriggerPriority.normal,
      scheduleSpec: const ScheduleTriggerSpec(hour: 25, minute: 0),
    );
    final invalidInterval = TriggerConfig(
      id: 'bad_interval',
      name: 'Bad interval',
      type: TriggerType.interval,
      priority: TriggerPriority.normal,
      intervalSpec: const IntervalTriggerSpec(every: Duration.zero),
    );

    final scheduleResult = await system.register(invalidSchedule);
    final intervalResult = await system.register(invalidInterval);

    expect(scheduleResult.isRegistered, isFalse);
    expect(scheduleResult.error, 'invalid_schedule_hour');
    expect(intervalResult.isRegistered, isFalse);
    expect(intervalResult.error, 'invalid_interval_duration');
  });

  test('cancel and list operate on in-memory registrations', () async {
    final system = buildSystem();
    final trigger = TriggerConfig(
      id: 'battery_check',
      name: 'Battery check',
      type: TriggerType.interval,
      priority: TriggerPriority.normal,
      intervalSpec: const IntervalTriggerSpec(every: Duration(minutes: 15)),
    );

    await system.register(trigger);

    expect(system.listTriggers().map((item) => item.id), <String>[
      'battery_check',
    ]);

    final cancelled = await system.cancel('battery_check');

    expect(cancelled, isTrue);
    expect(system.listTriggers(), isEmpty);
    expect(intervalBackend.cancelledIds, <String>['battery_check']);
  });

  test(
    'MiniKAIROS delays when user attention is required in background',
    () async {
      final system = buildSystem(
        context: const KairosContext(
          isAppForeground: false,
          batteryLevel: 80,
          activeSubAgents: 0,
        ),
      );
      await system.register(
        TriggerConfig(
          id: 'foreground_only',
          name: 'Foreground follow-up',
          type: TriggerType.schedule,
          priority: TriggerPriority.normal,
          requiresUserAttention: true,
          scheduleSpec: const ScheduleTriggerSpec(hour: 9, minute: 0),
        ),
      );

      final decision = await system.evaluateTrigger('foreground_only');

      expect(decision.type, KairosDecisionType.delay);
      expect(decision.reason, 'user_attention_required');
      expect(decision.untilSignal, 'app_foreground');
    },
  );

  test('MiniKAIROS skips expensive work on low battery', () async {
    final system = buildSystem(
      context: const KairosContext(
        isAppForeground: true,
        batteryLevel: 5,
        activeSubAgents: 0,
      ),
    );
    await system.register(
      TriggerConfig(
        id: 'expensive_job',
        name: 'Expensive job',
        type: TriggerType.interval,
        priority: TriggerPriority.high,
        isExpensive: true,
        intervalSpec: const IntervalTriggerSpec(every: Duration(minutes: 30)),
      ),
    );

    final decision = await system.evaluateTrigger('expensive_job');

    expect(decision.type, KairosDecisionType.skip);
    expect(decision.reason, 'battery_low');
  });

  test('MiniKAIROS queues when sub-agent concurrency is saturated', () async {
    final system = buildSystem(
      context: const KairosContext(
        isAppForeground: true,
        batteryLevel: 50,
        activeSubAgents: 3,
      ),
    );
    await system.register(
      TriggerConfig(
        id: 'queued_job',
        name: 'Queued job',
        type: TriggerType.interval,
        priority: TriggerPriority.high,
        intervalSpec: const IntervalTriggerSpec(every: Duration(minutes: 10)),
      ),
    );

    final decision = await system.evaluateTrigger('queued_job');

    expect(decision.type, KairosDecisionType.queue);
    expect(decision.priority, TriggerPriority.high);
  });

  test('MiniKAIROS proceeds when no gating condition applies', () async {
    final system = buildSystem();
    await system.register(
      TriggerConfig(
        id: 'ok_job',
        name: 'Okay job',
        type: TriggerType.schedule,
        priority: TriggerPriority.normal,
        scheduleSpec: const ScheduleTriggerSpec(hour: 7, minute: 30),
      ),
    );

    final decision = await system.evaluateTrigger('ok_job');

    expect(decision.type, KairosDecisionType.proceed);
  });
}

class _RecordingScheduleBackend implements ScheduleSchedulerBackend {
  final List<String> registeredIds = <String>[];
  final List<String> cancelledIds = <String>[];

  @override
  Future<void> cancel(String triggerId) async {
    cancelledIds.add(triggerId);
  }

  @override
  Future<void> registerSchedule(TriggerConfig trigger) async {
    registeredIds.add(trigger.id);
  }
}

class _RecordingIntervalBackend implements IntervalSchedulerBackend {
  final List<String> registeredIds = <String>[];
  final List<String> cancelledIds = <String>[];

  @override
  Future<void> cancel(String triggerId) async {
    cancelledIds.add(triggerId);
  }

  @override
  Future<void> registerInterval(TriggerConfig trigger) async {
    registeredIds.add(trigger.id);
  }
}
