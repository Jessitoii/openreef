import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/tools/native_tool_adapters.dart';
import 'package:openreef/triggers/battery_trigger_scheduler_backend.dart';
import 'package:openreef/triggers/mini_kairos.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_platform_event.dart';
import 'package:openreef/triggers/trigger_system.dart';

void main() {
  late _RecordingScheduleBackend scheduleBackend;
  late _RecordingIntervalBackend intervalBackend;
  late _RecordingTaskExecutor taskExecutor;
  late _RecordingBatteryBackend batteryBackend;

  TriggerSystem buildSystem({
    KairosContext context = const KairosContext(
      isAppForeground: true,
      batteryLevel: 80,
      activeSubAgents: 0,
    ),
    AgentLoopResult? executionResult,
  }) {
    scheduleBackend = _RecordingScheduleBackend();
    intervalBackend = _RecordingIntervalBackend();
    batteryBackend = _RecordingBatteryBackend();
    taskExecutor = _RecordingTaskExecutor(
      result:
          executionResult ??
          const AgentLoopResult(
            sessionResult: SessionResult.completed,
            text: 'done',
            reason: 'completed',
          ),
    );
    return TriggerSystem(
      scheduleBackend: scheduleBackend,
      intervalBackend: intervalBackend,
      batteryBackend: batteryBackend,
      miniKairos: MiniKairos(contextLoader: () async => context),
      taskExecutor: taskExecutor,
      systemSessionKey: 'system_main',
      historyLimit: 3,
    );
  }

  test('registering CRON routes to the schedule backend', () async {
    final system = buildSystem();

    final result = await system.register(_cronTrigger());

    expect(result.isRegistered, isTrue);
    expect(scheduleBackend.registeredIds, <String>['weekday_digest']);
  });

  test('invalid CRON subset is rejected explicitly', () async {
    final system = buildSystem();

    final result = await system.register(
      const TriggerConfig(
        id: 'bad_cron',
        name: 'Bad cron',
        prompt: 'Bad cron.',
        type: TriggerType.cron,
        priority: TriggerPriority.normal,
        cronSpec: CronTriggerSpec(expression: '0 9 1 * 1'),
      ),
    );

    expect(result.isRegistered, isFalse);
    expect(result.error, 'unsupported_cron_day_of_month');
  });

  test('manual fire reaches shared executor and records history', () async {
    final system = buildSystem();
    await system.register(_manualTrigger());
    system.setRuntimeReady(true);

    final result = await system.fireManual('manual_sync');

    expect(result.decision, TriggerDecision.execute);
    expect(taskExecutor.requests.single.sessionKey, 'system_main');
    expect(
      taskExecutor.requests.single.triggerMetadata?.deliveryType,
      'manual',
    );
    expect(system.stateById('manual_sync')?.lastResult, 'done');
    expect(system.stateById('manual_sync')?.history, hasLength(1));
    expect(
      system.stateById('manual_sync')?.lastStatus,
      TriggerRuntimeStatus.completed,
    );
  });

  test('cron platform delivery executes through shared path', () async {
    final system = buildSystem();
    await system.register(_cronTrigger());
    system.setRuntimeReady(true);

    await system.handlePlatformEvent(
      const TriggerPlatformEvent(
        triggerId: 'weekday_digest',
        type: 'cron',
        scheduledAtEpochMs: 1710000000000,
        deliveredAtEpochMs: 1710000001000,
      ),
    );

    expect(taskExecutor.requests, hasLength(1));
    expect(taskExecutor.requests.single.source, ExecutionSource.schedule);
    expect(
      taskExecutor.requests.single.triggerMetadata?.deliveryType,
      TriggerDeliverySource.cron.name,
    );
  });

  test('failed execution records failure and bounded history', () async {
    final system = buildSystem(
      executionResult: const AgentLoopResult(
        sessionResult: SessionResult.failed,
        text: '',
        reason: 'generation_failure',
      ),
    );
    await system.register(_manualTrigger());
    system.setRuntimeReady(true);

    await system.fireManual('manual_sync');
    await system.fireManual('manual_sync');
    await system.fireManual('manual_sync');
    await system.fireManual('manual_sync');

    final state = system.stateById('manual_sync');
    expect(state?.lastFailure, 'generation_failure');
    expect(state?.lastExecution?.status, TriggerExecutionStatus.failed);
    expect(state?.history, hasLength(3));
  });

  test('skip and delay reasons are recorded separately', () async {
    final skipSystem = buildSystem(
      context: const KairosContext(
        isAppForeground: true,
        batteryLevel: 5,
        activeSubAgents: 0,
      ),
    );
    await skipSystem.register(_intervalTrigger().copyWith(isExpensive: true));
    skipSystem.setRuntimeReady(true);
    final skipResult = await skipSystem.fireInterval('poll_inputs');

    expect(skipResult.decision, TriggerDecision.skip);
    expect(skipSystem.stateById('poll_inputs')?.lastSkipReason, 'battery_low');

    final delaySystem = buildSystem(
      context: const KairosContext(
        isAppForeground: false,
        batteryLevel: 80,
        activeSubAgents: 0,
      ),
    );
    await delaySystem.register(
      _scheduleTrigger().copyWith(requiresUserAttention: true),
    );
    delaySystem.setRuntimeReady(true);
    final delayResult = await delaySystem.handlePlatformEvent(
      const TriggerPlatformEvent(
        triggerId: 'briefing',
        type: 'schedule',
        scheduledAtEpochMs: 1710000000000,
        deliveredAtEpochMs: 1710000001000,
      ),
    );

    expect(delayResult.decision, TriggerDecision.delay);
    expect(
      delaySystem.stateById('briefing')?.lastDelayReason,
      'user_attention_required',
    );
  });

  test(
    'MCP_EVENT reaches trigger execution when source and payload match',
    () async {
      final system = buildSystem();
      await system.register(_mcpEventTrigger());
      system.setRuntimeReady(true);

      final results = await system.handleMcpRuntimeEvent(
        McpRuntimeEvent(
          sourceId: 'source-a',
          eventName: 'notifications/github.pr_merged',
          payload: <String, Object?>{
            'method': 'notifications/github.pr_merged',
            'params': <String, Object?>{'repo': 'openreef'},
          },
          receivedAt: DateTime.utc(2026, 4, 7, 12),
          transportEvent: 'message',
        ),
      );

      expect(results, hasLength(1));
      expect(taskExecutor.requests, hasLength(1));
      expect(
        taskExecutor.requests.single.triggerMetadata?.triggerType,
        TriggerType.mcpEvent.name,
      );
    },
  );

  test(
    'standing order deterministically influences execution metadata',
    () async {
      final system = buildSystem();
      await system.register(_manualTrigger());
      await system.register(_standingOrderTrigger());
      system.setRuntimeReady(true);

      await system.fireManual('manual_sync');

      final triggerMetadata = taskExecutor.requests.single.triggerMetadata;
      expect(triggerMetadata?.appliedStandingOrderIds, <String>['boss_rule']);
      expect(
        triggerMetadata?.standingOrderInstructions,
        contains('Escalate anything tagged work-critical first.'),
      );
    },
  );

  test('BATTERY registration routes to battery backend', () async {
    final system = buildSystem();

    final result = await system.register(_batteryTrigger());

    expect(result.isRegistered, isTrue);
    expect(batteryBackend.registeredIds, <String>['low_battery']);
  });

  test('battery polling fires only on threshold crossing', () async {
    final deliveries = <BatteryTriggerDelivery>[];
    final backend = PollingBatterySchedulerBackend(
      batteryAdapter: _FakeBatteryAdapter(
        snapshots: <BatterySnapshot>[
          const BatterySnapshot(level: 50, state: BatteryState.discharging),
          const BatterySnapshot(level: 19, state: BatteryState.discharging),
          const BatterySnapshot(level: 18, state: BatteryState.discharging),
        ],
      ),
      onTriggerFired: (delivery) async {
        deliveries.add(delivery);
      },
      pollInterval: const Duration(minutes: 1),
      timerFactory: (every, onTick) =>
          _FakeTimerHandle(every: every, onTick: onTick),
      timerCanceler: (handle) {},
    );

    await backend.registerBattery(_batteryTrigger());
    await backend.registerBattery(_batteryTrigger());

    expect(deliveries, hasLength(1));
    expect(deliveries.single.triggerId, 'low_battery');
    expect(deliveries.single.payload['batteryLevel'], 19);
  });
}

TriggerConfig _manualTrigger() {
  return const TriggerConfig(
    id: 'manual_sync',
    name: 'Manual sync',
    prompt: 'Run a manual maintenance sync.',
    type: TriggerType.manual,
    priority: TriggerPriority.normal,
    payload: <String, Object?>{'scope': 'work'},
  );
}

TriggerConfig _scheduleTrigger() {
  return const TriggerConfig(
    id: 'briefing',
    name: 'Morning briefing',
    prompt: 'Deliver the scheduled morning briefing.',
    type: TriggerType.schedule,
    priority: TriggerPriority.normal,
    scheduleSpec: ScheduleTriggerSpec(hour: 8, minute: 0),
  );
}

TriggerConfig _intervalTrigger() {
  return const TriggerConfig(
    id: 'poll_inputs',
    name: 'Poll inputs',
    prompt: 'Poll interval inputs for new work.',
    type: TriggerType.interval,
    priority: TriggerPriority.low,
    intervalSpec: IntervalTriggerSpec(every: Duration(minutes: 30)),
  );
}

TriggerConfig _cronTrigger() {
  return const TriggerConfig(
    id: 'weekday_digest',
    name: 'Weekday digest',
    prompt: 'Deliver the weekday digest.',
    type: TriggerType.cron,
    priority: TriggerPriority.normal,
    cronSpec: CronTriggerSpec(expression: '0 9 * * 1-5'),
  );
}

TriggerConfig _batteryTrigger() {
  return const TriggerConfig(
    id: 'low_battery',
    name: 'Low battery reminder',
    prompt: 'Tell the user the battery is low.',
    type: TriggerType.battery,
    priority: TriggerPriority.normal,
    batterySpec: BatteryTriggerSpec(
      condition: BatteryTriggerCondition.levelAtOrBelow,
      level: 20,
    ),
  );
}

TriggerConfig _mcpEventTrigger() {
  return const TriggerConfig(
    id: 'pr_merge',
    name: 'PR merge',
    prompt: 'Summarize the merged pull request.',
    type: TriggerType.mcpEvent,
    priority: TriggerPriority.normal,
    mcpEventSpec: McpEventTriggerSpec(
      sourceId: 'source-a',
      eventName: 'notifications/github.pr_merged',
      payloadMatches: <String, Object?>{
        'method': 'notifications/github.pr_merged',
      },
    ),
  );
}

TriggerConfig _standingOrderTrigger() {
  return const TriggerConfig(
    id: 'boss_rule',
    name: 'Boss rule',
    prompt: 'Escalate anything tagged work-critical first.',
    type: TriggerType.standingOrder,
    priority: TriggerPriority.high,
    standingOrderSpec: StandingOrderSpec(
      appliesToTypes: <TriggerType>[TriggerType.manual],
      payloadMatches: <String, Object?>{'scope': 'work'},
    ),
  );
}

class _RecordingScheduleBackend implements ScheduleSchedulerBackend {
  final List<String> registeredIds = <String>[];

  @override
  Future<void> cancel(String triggerId) async {}

  @override
  Future<void> registerSchedule(TriggerConfig trigger) async {
    registeredIds.add(trigger.id);
  }
}

class _RecordingIntervalBackend implements IntervalSchedulerBackend {
  final List<String> registeredIds = <String>[];

  @override
  Future<void> cancel(String triggerId) async {}

  @override
  Future<void> registerInterval(TriggerConfig trigger) async {
    registeredIds.add(trigger.id);
  }
}

class _RecordingBatteryBackend implements BatterySchedulerBackend {
  final List<String> registeredIds = <String>[];

  @override
  Future<void> cancel(String triggerId) async {}

  @override
  Future<void> registerBattery(TriggerConfig trigger) async {
    registeredIds.add(trigger.id);
  }
}

class _RecordingTaskExecutor implements AgentTaskExecutor {
  _RecordingTaskExecutor({required this.result});

  final AgentLoopResult result;
  final List<AgentTaskRequest> requests = <AgentTaskRequest>[];

  @override
  Future<bool> cancelActiveRun({
    String? runId,
    String? sessionKey,
    RunCancellationReason reason = RunCancellationReason.userRequested,
  }) async {
    return false;
  }

  @override
  Future<ExecutionResult> execute(ExecutionRequest request) async {
    throw UnimplementedError();
  }

  @override
  Future<AgentTaskExecutionResult> executeTask(AgentTaskRequest request) async {
    requests.add(request);
    return AgentTaskExecutionResult.fromLoopResult(result);
  }
}

class _FakeBatteryAdapter implements BatteryAdapter {
  _FakeBatteryAdapter({required this.snapshots});

  final List<BatterySnapshot> snapshots;
  int _index = 0;

  @override
  Future<BatterySnapshot> readBatteryInfo() async {
    final snapshot = snapshots[_index.clamp(0, snapshots.length - 1)];
    if (_index < snapshots.length - 1) {
      _index += 1;
    }
    return snapshot;
  }
}

class _FakeTimerHandle {
  _FakeTimerHandle({required this.every, required this.onTick});

  final Duration every;
  final void Function() onTick;
}
