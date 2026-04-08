import 'dart:async';

import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/triggers/battery_trigger_scheduler_backend.dart';
import 'package:openreef/triggers/cron_expression.dart';
import 'package:openreef/triggers/mini_kairos.dart';
import 'package:openreef/triggers/standing_order_applicator.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_platform_event.dart';

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
    required AgentTaskExecutor taskExecutor,
    BatterySchedulerBackend? batteryBackend,
    StandingOrderApplicator standingOrderApplicator =
        const StandingOrderApplicator(),
    this.systemSessionKey = 'system_main',
    this.historyLimit = 10,
    DateTime Function()? clock,
  }) : _scheduleBackend = scheduleBackend,
       _intervalBackend = intervalBackend,
       _miniKairos = miniKairos,
       _taskExecutor = taskExecutor,
       _batteryBackend = batteryBackend,
       _standingOrderApplicator = standingOrderApplicator,
       _clock = clock ?? DateTime.now;

  final ScheduleSchedulerBackend _scheduleBackend;
  final IntervalSchedulerBackend _intervalBackend;
  final MiniKairos _miniKairos;
  final AgentTaskExecutor _taskExecutor;
  final BatterySchedulerBackend? _batteryBackend;
  final StandingOrderApplicator _standingOrderApplicator;
  final String systemSessionKey;
  final int historyLimit;
  final DateTime Function() _clock;
  final Map<String, TriggerConfig> _triggers = <String, TriggerConfig>{};
  final Map<String, TriggerState> _states = <String, TriggerState>{};
  final StreamController<TriggerExecutionEvent> _executionEvents =
      StreamController<TriggerExecutionEvent>.broadcast();

  bool _runtimeReady = false;

  Stream<TriggerExecutionEvent> get executionEvents => _executionEvents.stream;

  List<TriggerConfig> listTriggers() {
    return _triggers.values.toList(growable: false);
  }

  Map<String, TriggerState> listTriggerStates() {
    return Map<String, TriggerState>.unmodifiable(_states);
  }

  TriggerConfig? byId(String triggerId) => _triggers[triggerId];

  TriggerState? stateById(String triggerId) => _states[triggerId];

  bool get isRuntimeReady => _runtimeReady;

  void setRuntimeReady(bool isReady) {
    _runtimeReady = isReady;
  }

  TriggerValidationResult validate(TriggerConfig trigger) {
    if (trigger.prompt.trim().isEmpty) {
      return const TriggerValidationResult.invalid('missing_prompt');
    }

    if (trigger.type == TriggerType.manual || trigger.type == TriggerType.boot) {
      if (_countDefinedSpecs(trigger) != 0) {
        return const TriggerValidationResult.invalid('invalid_trigger_spec');
      }
      return const TriggerValidationResult.valid();
    }

    if (trigger.type == TriggerType.schedule) {
      final spec = trigger.scheduleSpec;
      if (_countDefinedSpecs(trigger) != 1 || spec == null) {
        return const TriggerValidationResult.invalid('invalid_schedule_spec');
      }
      if (spec.hour < 0 || spec.hour > 23) {
        return const TriggerValidationResult.invalid('invalid_schedule_hour');
      }
      if (spec.minute < 0 || spec.minute > 59) {
        return const TriggerValidationResult.invalid('invalid_schedule_minute');
      }
      return const TriggerValidationResult.valid();
    }

    if (trigger.type == TriggerType.interval) {
      final spec = trigger.intervalSpec;
      if (_countDefinedSpecs(trigger) != 1 || spec == null) {
        return const TriggerValidationResult.invalid('invalid_interval_spec');
      }
      if (spec.every <= Duration.zero) {
        return const TriggerValidationResult.invalid(
          'invalid_interval_duration',
        );
      }
      return const TriggerValidationResult.valid();
    }

    if (trigger.type == TriggerType.cron) {
      final spec = trigger.cronSpec;
      if (_countDefinedSpecs(trigger) != 1 || spec == null) {
        return const TriggerValidationResult.invalid('invalid_cron_spec');
      }
      final validation = CronExpressionValidator.instance.validate(
        spec.expression,
      );
      if (!validation.isValid) {
        return TriggerValidationResult.invalid(validation.error!);
      }
      return const TriggerValidationResult.valid();
    }

    if (trigger.type == TriggerType.battery) {
      final spec = trigger.batterySpec;
      if (_countDefinedSpecs(trigger) != 1 || spec == null) {
        return const TriggerValidationResult.invalid('invalid_battery_spec');
      }
      if ((spec.condition == BatteryTriggerCondition.levelAtOrBelow ||
              spec.condition == BatteryTriggerCondition.levelAtOrAbove) &&
          (spec.level == null || spec.level! < 0 || spec.level! > 100)) {
        return const TriggerValidationResult.invalid('invalid_battery_level');
      }
      if (spec.condition == BatteryTriggerCondition.stateChanged &&
          spec.requiredState != null &&
          spec.requiredState!.trim().isEmpty) {
        return const TriggerValidationResult.invalid('invalid_battery_state');
      }
      return const TriggerValidationResult.valid();
    }

    if (trigger.type == TriggerType.mcpEvent) {
      final spec = trigger.mcpEventSpec;
      if (_countDefinedSpecs(trigger) != 1 || spec == null) {
        return const TriggerValidationResult.invalid('invalid_mcp_event_spec');
      }
      if (spec.sourceId.trim().isEmpty || spec.eventName.trim().isEmpty) {
        return const TriggerValidationResult.invalid('invalid_mcp_event_spec');
      }
      return const TriggerValidationResult.valid();
    }

    final spec = trigger.standingOrderSpec;
    if (_countDefinedSpecs(trigger) != 1 || spec == null) {
      return const TriggerValidationResult.invalid('invalid_standing_order_spec');
    }
    if (spec.appliesToTypes.isEmpty ||
        spec.appliesToTypes.contains(TriggerType.standingOrder)) {
      return const TriggerValidationResult.invalid('invalid_standing_order_scope');
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

    final previous = _triggers[trigger.id];
    if (previous != null && previous.enabled) {
      await _deactivate(previous);
    }

    _triggers[trigger.id] = trigger;
    _states[trigger.id] = (_states[trigger.id] ?? TriggerState(enabled: trigger.enabled))
        .copyWith(enabled: trigger.enabled);

    if (trigger.enabled) {
      await _activate(trigger);
    }

    return TriggerRegistrationResult(isRegistered: true, triggerId: trigger.id);
  }

  Future<bool> cancel(String triggerId) async {
    final trigger = _triggers.remove(triggerId);
    _states.remove(triggerId);
    if (trigger == null) {
      return false;
    }

    if (trigger.enabled) {
      await _deactivate(trigger);
    }
    return true;
  }

  Future<bool> setEnabled(String triggerId, bool enabled) async {
    final trigger = _triggers[triggerId];
    if (trigger == null) {
      return false;
    }
    if (trigger.enabled == enabled) {
      _states[triggerId] = (_states[triggerId] ?? TriggerState(enabled: enabled))
          .copyWith(enabled: enabled);
      return true;
    }

    if (trigger.enabled) {
      await _deactivate(trigger);
    }

    final updated = trigger.copyWith(enabled: enabled);
    _triggers[triggerId] = updated;
    _states[triggerId] = (_states[triggerId] ?? TriggerState(enabled: enabled))
        .copyWith(enabled: enabled);

    if (enabled) {
      await _activate(updated);
    }

    return true;
  }

  Future<TriggerFireResult> fireManual(String triggerId) {
    return _handleDelivery(
      TriggerDelivery(
        triggerId: triggerId,
        source: TriggerDeliverySource.manual,
        deliveredAt: _clock(),
      ),
    );
  }

  Future<List<TriggerFireResult>> fireBootTriggers() async {
    final results = <TriggerFireResult>[];
    for (final trigger in _triggers.values) {
      if (!trigger.enabled || trigger.type != TriggerType.boot) {
        continue;
      }
      results.add(
        await _handleDelivery(
          TriggerDelivery(
            triggerId: trigger.id,
            source: TriggerDeliverySource.boot,
            deliveredAt: _clock(),
          ),
        ),
      );
    }
    return results;
  }

  Future<TriggerFireResult> handlePlatformEvent(TriggerPlatformEvent event) {
    return _handleDelivery(
      TriggerDelivery(
        triggerId: event.triggerId,
        source: _sourceFromTypeName(event.type),
        deliveredAt: event.deliveredAt,
        scheduledAt: event.scheduledAt,
        payload: event.payload,
      ),
    );
  }

  Future<TriggerFireResult> fireInterval(String triggerId) {
    return _handleDelivery(
      TriggerDelivery(
        triggerId: triggerId,
        source: TriggerDeliverySource.interval,
        deliveredAt: _clock(),
      ),
    );
  }

  Future<TriggerFireResult> fireBattery(
    String triggerId, {
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    return _handleDelivery(
      TriggerDelivery(
        triggerId: triggerId,
        source: TriggerDeliverySource.battery,
        deliveredAt: _clock(),
        payload: payload,
      ),
    );
  }

  Future<List<TriggerFireResult>> handleMcpRuntimeEvent(
    McpRuntimeEvent event,
  ) async {
    final results = <TriggerFireResult>[];
    for (final trigger in _triggers.values) {
      final spec = trigger.mcpEventSpec;
      if (!trigger.enabled ||
          trigger.type != TriggerType.mcpEvent ||
          spec == null ||
          spec.sourceId != event.sourceId ||
          spec.eventName != event.eventName) {
        continue;
      }
      if (!_payloadMatches(spec.payloadMatches, event.payload)) {
        continue;
      }
      results.add(
        await _handleDelivery(
          TriggerDelivery(
            triggerId: trigger.id,
            source: TriggerDeliverySource.mcpEvent,
            deliveredAt: event.receivedAt,
            payload: <String, Object?>{
              ...event.payload,
              'sourceId': event.sourceId,
              'eventName': event.eventName,
              'transportEvent': event.transportEvent,
            },
          ),
        ),
      );
    }
    return results;
  }

  Future<KairosDecision> evaluateTrigger(String triggerId) async {
    final trigger = _triggers[triggerId];
    if (trigger == null) {
      throw StateError('unknown_trigger:$triggerId');
    }
    return _miniKairos.evaluate(trigger);
  }

  Future<void> _activate(TriggerConfig trigger) async {
    if (trigger.type == TriggerType.schedule || trigger.type == TriggerType.cron) {
      await _scheduleBackend.registerSchedule(trigger);
      return;
    }
    if (trigger.type == TriggerType.interval) {
      await _intervalBackend.registerInterval(trigger);
      return;
    }
    if (trigger.type == TriggerType.battery) {
      final batteryBackend = _batteryBackend;
      if (batteryBackend == null) {
        throw StateError('battery_backend_unavailable');
      }
      await batteryBackend.registerBattery(trigger);
    }
  }

  Future<void> _deactivate(TriggerConfig trigger) async {
    if (trigger.type == TriggerType.schedule || trigger.type == TriggerType.cron) {
      await _scheduleBackend.cancel(trigger.id);
      return;
    }
    if (trigger.type == TriggerType.interval) {
      await _intervalBackend.cancel(trigger.id);
      return;
    }
    if (trigger.type == TriggerType.battery) {
      await _batteryBackend?.cancel(trigger.id);
    }
  }

  Future<TriggerFireResult> _handleDelivery(TriggerDelivery delivery) async {
    final trigger = _triggers[delivery.triggerId];
    if (trigger == null) {
      throw StateError('unknown_trigger:${delivery.triggerId}');
    }

    final baselineState =
        _states[trigger.id] ?? TriggerState(enabled: trigger.enabled);

    if (!trigger.enabled) {
      final nextState = _recordState(
        trigger: trigger,
        state: baselineState.copyWith(
          enabled: false,
          lastEvaluatedAt: delivery.deliveredAt,
          lastDecision: TriggerDecision.skip,
          lastDecisionReason: 'trigger_disabled',
          lastStatus: TriggerRuntimeStatus.skipped,
          lastSkipReason: 'trigger_disabled',
          clearLastDelayReason: true,
        ),
        historyEntry: TriggerHistoryEntry(
          triggerId: trigger.id,
          triggerType: trigger.type,
          deliverySource: delivery.source,
          deliveredAt: delivery.deliveredAt,
          scheduledAt: delivery.scheduledAt,
          decision: TriggerDecision.skip,
          status: TriggerRuntimeStatus.skipped,
          skipReason: 'trigger_disabled',
          payload: delivery.payload,
        ),
      );
      return TriggerFireResult(
        decision: TriggerDecision.skip,
        reason: 'trigger_disabled',
        state: nextState,
      );
    }

    if (!_runtimeReady) {
      final nextState = _recordState(
        trigger: trigger,
        state: baselineState.copyWith(
          enabled: true,
          lastEvaluatedAt: delivery.deliveredAt,
          lastDecision: TriggerDecision.delay,
          lastDecisionReason: 'runtime_not_ready',
          lastStatus: TriggerRuntimeStatus.delayed,
          lastDelayReason: 'runtime_not_ready',
          clearLastSkipReason: true,
        ),
        historyEntry: TriggerHistoryEntry(
          triggerId: trigger.id,
          triggerType: trigger.type,
          deliverySource: delivery.source,
          deliveredAt: delivery.deliveredAt,
          scheduledAt: delivery.scheduledAt,
          decision: TriggerDecision.delay,
          status: TriggerRuntimeStatus.delayed,
          delayReason: 'runtime_not_ready',
          payload: delivery.payload,
        ),
      );
      return TriggerFireResult(
        decision: TriggerDecision.delay,
        reason: 'runtime_not_ready',
        state: nextState,
      );
    }

    final evaluation = await _miniKairos.evaluate(trigger);
    switch (evaluation.type) {
      case KairosDecisionType.proceed:
        return _executeTrigger(
          trigger: trigger,
          delivery: delivery,
          baselineState: baselineState,
        );
      case KairosDecisionType.skip:
        final reason = evaluation.reason ?? 'skipped';
        final nextState = _recordState(
          trigger: trigger,
          state: baselineState.copyWith(
            enabled: true,
            lastEvaluatedAt: delivery.deliveredAt,
            lastDecision: TriggerDecision.skip,
            lastDecisionReason: reason,
            lastStatus: TriggerRuntimeStatus.skipped,
            lastSkipReason: reason,
            clearLastDelayReason: true,
          ),
          historyEntry: TriggerHistoryEntry(
            triggerId: trigger.id,
            triggerType: trigger.type,
            deliverySource: delivery.source,
            deliveredAt: delivery.deliveredAt,
            scheduledAt: delivery.scheduledAt,
            decision: TriggerDecision.skip,
            status: TriggerRuntimeStatus.skipped,
            skipReason: reason,
            payload: delivery.payload,
          ),
        );
        return TriggerFireResult(
          decision: TriggerDecision.skip,
          reason: reason,
          state: nextState,
        );
      case KairosDecisionType.delay:
      case KairosDecisionType.queue:
        final reason = evaluation.type == KairosDecisionType.queue
            ? 'queued_${evaluation.priority?.name ?? 'normal'}'
            : evaluation.reason ?? 'delayed';
        final nextState = _recordState(
          trigger: trigger,
          state: baselineState.copyWith(
            enabled: true,
            lastEvaluatedAt: delivery.deliveredAt,
            lastDecision: TriggerDecision.delay,
            lastDecisionReason: reason,
            lastStatus: TriggerRuntimeStatus.delayed,
            lastDelayReason: reason,
            clearLastSkipReason: true,
          ),
          historyEntry: TriggerHistoryEntry(
            triggerId: trigger.id,
            triggerType: trigger.type,
            deliverySource: delivery.source,
            deliveredAt: delivery.deliveredAt,
            scheduledAt: delivery.scheduledAt,
            decision: TriggerDecision.delay,
            status: TriggerRuntimeStatus.delayed,
            delayReason: reason,
            payload: delivery.payload,
          ),
        );
        return TriggerFireResult(
          decision: TriggerDecision.delay,
          reason: reason,
          state: nextState,
        );
    }
  }

  Future<TriggerFireResult> _executeTrigger({
    required TriggerConfig trigger,
    required TriggerDelivery delivery,
    required TriggerState baselineState,
  }) async {
    final payload = <String, Object?>{
      ...trigger.payload,
      ...delivery.payload,
    };
    final standingOrders = _standingOrderApplicator.apply(
      standingOrders: _triggers.values,
      trigger: trigger,
      payload: payload,
    );
    final executionResult = await _taskExecutor.executeTask(
      AgentTaskRequest(
        sessionKey: systemSessionKey,
        prompt: trigger.prompt,
        source:
            trigger.type == TriggerType.schedule || trigger.type == TriggerType.cron
            ? ExecutionSource.schedule
            : trigger.type == TriggerType.mcpEvent
            ? ExecutionSource.mcpEvent
            : ExecutionSource.trigger,
        visibility: trigger.visibility ?? ExecutionVisibility.background,
        triggerMetadata: AgentTaskTriggerMetadata(
          triggerId: trigger.id,
          triggerName: trigger.name,
          triggerType: trigger.type.name,
          deliveryType: delivery.source.name,
          payload: payload,
          deliveredAt: delivery.deliveredAt,
          scheduledAt: delivery.scheduledAt,
          appliedStandingOrderIds: standingOrders.appliedIds,
          standingOrderInstructions: standingOrders.instructions.trim(),
        ),
      ),
    );
    final executionRecord = TriggerExecutionRecord(
      status: _mapExecutionStatus(executionResult.status),
      startedAt: delivery.deliveredAt,
      finishedAt: _clock(),
      output: executionResult.text,
      error: executionResult.status == AgentTaskExecutionStatus.completed
          ? null
          : (executionResult.text.trim().isNotEmpty
                ? executionResult.text.trim()
                : executionResult.reason),
    );
    final runtimeStatus = _mapRuntimeStatus(executionResult.status);
    final nextState = _recordState(
      trigger: trigger,
      state: baselineState.copyWith(
        enabled: true,
        lastEvaluatedAt: delivery.deliveredAt,
        lastDecision: TriggerDecision.execute,
        clearLastDecisionReason: true,
        lastRunAt: executionRecord.finishedAt,
        lastResult: executionRecord.output,
        lastFailure: executionRecord.error,
        clearLastFailure: executionRecord.error == null,
        lastExecution: executionRecord,
        lastStatus: runtimeStatus,
        clearLastSkipReason: true,
        clearLastDelayReason: true,
      ),
      historyEntry: TriggerHistoryEntry(
        triggerId: trigger.id,
        triggerType: trigger.type,
        deliverySource: delivery.source,
        deliveredAt: delivery.deliveredAt,
        scheduledAt: delivery.scheduledAt,
        decision: TriggerDecision.execute,
        status: runtimeStatus,
        result: executionRecord.output,
        failure: executionRecord.error,
        execution: executionRecord,
        payload: payload,
      ),
    );
    _executionEvents.add(
      TriggerExecutionEvent(
        trigger: trigger,
        delivery: delivery,
        execution: executionRecord,
        appliedStandingOrderIds: standingOrders.appliedIds,
      ),
    );
    return TriggerFireResult(
      decision: TriggerDecision.execute,
      state: nextState,
    );
  }

  TriggerState _recordState({
    required TriggerConfig trigger,
    required TriggerState state,
    required TriggerHistoryEntry historyEntry,
  }) {
    final history = <TriggerHistoryEntry>[
      ...state.history,
      historyEntry,
    ];
    final trimmed = history.length > historyLimit
        ? history.sublist(history.length - historyLimit)
        : history;
    final nextState = state.copyWith(
      history: List<TriggerHistoryEntry>.unmodifiable(trimmed),
    );
    _states[trigger.id] = nextState;
    return nextState;
  }

  TriggerExecutionStatus _mapExecutionStatus(AgentTaskExecutionStatus status) {
    return switch (status) {
      AgentTaskExecutionStatus.completed => TriggerExecutionStatus.completed,
      AgentTaskExecutionStatus.frozen => TriggerExecutionStatus.frozen,
      AgentTaskExecutionStatus.failed => TriggerExecutionStatus.failed,
    };
  }

  TriggerRuntimeStatus _mapRuntimeStatus(AgentTaskExecutionStatus status) {
    return switch (status) {
      AgentTaskExecutionStatus.completed => TriggerRuntimeStatus.completed,
      AgentTaskExecutionStatus.frozen => TriggerRuntimeStatus.frozen,
      AgentTaskExecutionStatus.failed => TriggerRuntimeStatus.failed,
    };
  }

  TriggerDeliverySource _sourceFromTypeName(String type) {
    return switch (type) {
      'schedule' => TriggerDeliverySource.schedule,
      'interval' => TriggerDeliverySource.interval,
      'boot' => TriggerDeliverySource.boot,
      'cron' => TriggerDeliverySource.cron,
      'battery' => TriggerDeliverySource.battery,
      'mcpEvent' => TriggerDeliverySource.mcpEvent,
      _ => TriggerDeliverySource.manual,
    };
  }

  bool _payloadMatches(
    Map<String, Object?> expected,
    Map<String, Object?> actual,
  ) {
    for (final entry in expected.entries) {
      if (actual[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  int _countDefinedSpecs(TriggerConfig trigger) {
    var total = 0;
    if (trigger.scheduleSpec != null) {
      total += 1;
    }
    if (trigger.intervalSpec != null) {
      total += 1;
    }
    if (trigger.cronSpec != null) {
      total += 1;
    }
    if (trigger.batterySpec != null) {
      total += 1;
    }
    if (trigger.mcpEventSpec != null) {
      total += 1;
    }
    if (trigger.standingOrderSpec != null) {
      total += 1;
    }
    return total;
  }
}
