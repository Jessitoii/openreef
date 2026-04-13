import 'package:openreef/agent/execution_request.dart';

enum TriggerType {
  manual,
  schedule,
  interval,
  boot,
  cron,
  battery,
  mcpEvent,
  standingOrder,
}

enum TriggerPriority { low, normal, high }

enum ScheduleRecurrence { daily }

enum BatteryTriggerCondition { levelAtOrBelow, levelAtOrAbove, stateChanged }

enum TriggerExecutionStatus { completed, frozen, failed }

enum TriggerDecision { execute, skip, delay }

enum TriggerRuntimeStatus { idle, completed, frozen, failed, skipped, delayed }

enum TriggerDeliverySource {
  manual,
  schedule,
  interval,
  boot,
  cron,
  battery,
  mcpEvent,
}

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

class CronTriggerSpec {
  const CronTriggerSpec({required this.expression});

  final String expression;
}

class BatteryTriggerSpec {
  const BatteryTriggerSpec({
    required this.condition,
    this.level,
    this.requiredState,
  });

  final BatteryTriggerCondition condition;
  final int? level;
  final String? requiredState;
}

class McpEventTriggerSpec {
  const McpEventTriggerSpec({
    required this.sourceId,
    required this.eventName,
    this.payloadMatches = const <String, Object?>{},
  });

  final String sourceId;
  final String eventName;
  final Map<String, Object?> payloadMatches;
}

class StandingOrderSpec {
  const StandingOrderSpec({
    required this.appliesToTypes,
    this.payloadMatches = const <String, Object?>{},
  });

  final List<TriggerType> appliesToTypes;
  final Map<String, Object?> payloadMatches;
}

class TriggerConfig {
  const TriggerConfig({
    required this.id,
    required this.name,
    required this.prompt,
    required this.type,
    required this.priority,
    this.enabled = true,
    this.scheduleSpec,
    this.intervalSpec,
    this.cronSpec,
    this.batterySpec,
    this.mcpEventSpec,
    this.standingOrderSpec,
    this.requiresUserAttention = false,
    this.isExpensive = false,
    this.visibility,
    this.payload = const <String, Object?>{},
    this.pollIntervalMinutes,
  });

  final String id;
  final String name;
  final String prompt;
  final TriggerType type;
  final TriggerPriority priority;
  final bool enabled;
  final ScheduleTriggerSpec? scheduleSpec;
  final IntervalTriggerSpec? intervalSpec;
  final CronTriggerSpec? cronSpec;
  final BatteryTriggerSpec? batterySpec;
  final McpEventTriggerSpec? mcpEventSpec;
  final StandingOrderSpec? standingOrderSpec;
  final bool requiresUserAttention;
  final bool isExpensive;
  final ExecutionVisibility? visibility;
  final Map<String, Object?> payload;
  final int? pollIntervalMinutes;

  TriggerConfig copyWith({
    String? id,
    String? name,
    String? prompt,
    TriggerType? type,
    TriggerPriority? priority,
    bool? enabled,
    ScheduleTriggerSpec? scheduleSpec,
    bool clearScheduleSpec = false,
    IntervalTriggerSpec? intervalSpec,
    bool clearIntervalSpec = false,
    CronTriggerSpec? cronSpec,
    bool clearCronSpec = false,
    BatteryTriggerSpec? batterySpec,
    bool clearBatterySpec = false,
    McpEventTriggerSpec? mcpEventSpec,
    bool clearMcpEventSpec = false,
    StandingOrderSpec? standingOrderSpec,
    bool clearStandingOrderSpec = false,
    bool? requiresUserAttention,
    bool? isExpensive,
    Map<String, Object?>? payload,
    int? pollIntervalMinutes,
  }) {
    return TriggerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
      scheduleSpec: clearScheduleSpec ? null : scheduleSpec ?? this.scheduleSpec,
      intervalSpec: clearIntervalSpec ? null : intervalSpec ?? this.intervalSpec,
      cronSpec: clearCronSpec ? null : cronSpec ?? this.cronSpec,
      batterySpec: clearBatterySpec ? null : batterySpec ?? this.batterySpec,
      mcpEventSpec: clearMcpEventSpec ? null : mcpEventSpec ?? this.mcpEventSpec,
      standingOrderSpec: clearStandingOrderSpec
          ? null
          : standingOrderSpec ?? this.standingOrderSpec,
      requiresUserAttention:
          requiresUserAttention ?? this.requiresUserAttention,
      isExpensive: isExpensive ?? this.isExpensive,
      payload: payload ?? this.payload,
      pollIntervalMinutes: pollIntervalMinutes ?? this.pollIntervalMinutes,
    );
  }
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

class TriggerExecutionRecord {
  const TriggerExecutionRecord({
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    required this.output,
    this.error,
  });

  final TriggerExecutionStatus status;
  final DateTime startedAt;
  final DateTime finishedAt;
  final String output;
  final String? error;
}

class TriggerHistoryEntry {
  const TriggerHistoryEntry({
    required this.triggerId,
    required this.triggerType,
    required this.deliverySource,
    required this.deliveredAt,
    required this.decision,
    required this.status,
    this.scheduledAt,
    this.result,
    this.failure,
    this.skipReason,
    this.delayReason,
    this.execution,
    this.payload = const <String, Object?>{},
  });

  final String triggerId;
  final TriggerType triggerType;
  final TriggerDeliverySource deliverySource;
  final DateTime deliveredAt;
  final DateTime? scheduledAt;
  final TriggerDecision decision;
  final TriggerRuntimeStatus status;
  final String? result;
  final String? failure;
  final String? skipReason;
  final String? delayReason;
  final TriggerExecutionRecord? execution;
  final Map<String, Object?> payload;
}

class TriggerState {
  const TriggerState({
    required this.enabled,
    this.lastEvaluatedAt,
    this.lastDecision,
    this.lastDecisionReason,
    this.lastRunAt,
    this.lastResult,
    this.lastFailure,
    this.lastExecution,
    this.lastStatus = TriggerRuntimeStatus.idle,
    this.lastSkipReason,
    this.lastDelayReason,
    this.history = const <TriggerHistoryEntry>[],
  });

  final bool enabled;
  final DateTime? lastEvaluatedAt;
  final TriggerDecision? lastDecision;
  final String? lastDecisionReason;
  final DateTime? lastRunAt;
  final String? lastResult;
  final String? lastFailure;
  final TriggerExecutionRecord? lastExecution;
  final TriggerRuntimeStatus lastStatus;
  final String? lastSkipReason;
  final String? lastDelayReason;
  final List<TriggerHistoryEntry> history;

  TriggerState copyWith({
    bool? enabled,
    DateTime? lastEvaluatedAt,
    bool clearLastEvaluatedAt = false,
    TriggerDecision? lastDecision,
    bool clearLastDecision = false,
    String? lastDecisionReason,
    bool clearLastDecisionReason = false,
    DateTime? lastRunAt,
    bool clearLastRunAt = false,
    String? lastResult,
    bool clearLastResult = false,
    String? lastFailure,
    bool clearLastFailure = false,
    TriggerExecutionRecord? lastExecution,
    bool clearLastExecution = false,
    TriggerRuntimeStatus? lastStatus,
    String? lastSkipReason,
    bool clearLastSkipReason = false,
    String? lastDelayReason,
    bool clearLastDelayReason = false,
    List<TriggerHistoryEntry>? history,
  }) {
    return TriggerState(
      enabled: enabled ?? this.enabled,
      lastEvaluatedAt: clearLastEvaluatedAt
          ? null
          : lastEvaluatedAt ?? this.lastEvaluatedAt,
      lastDecision: clearLastDecision ? null : lastDecision ?? this.lastDecision,
      lastDecisionReason: clearLastDecisionReason
          ? null
          : lastDecisionReason ?? this.lastDecisionReason,
      lastRunAt: clearLastRunAt ? null : lastRunAt ?? this.lastRunAt,
      lastResult: clearLastResult ? null : lastResult ?? this.lastResult,
      lastFailure: clearLastFailure ? null : lastFailure ?? this.lastFailure,
      lastExecution: clearLastExecution
          ? null
          : lastExecution ?? this.lastExecution,
      lastStatus: lastStatus ?? this.lastStatus,
      lastSkipReason: clearLastSkipReason
          ? null
          : lastSkipReason ?? this.lastSkipReason,
      lastDelayReason: clearLastDelayReason
          ? null
          : lastDelayReason ?? this.lastDelayReason,
      history: history ?? this.history,
    );
  }
}

class TriggerDelivery {
  const TriggerDelivery({
    required this.triggerId,
    required this.source,
    required this.deliveredAt,
    this.scheduledAt,
    this.payload = const <String, Object?>{},
  });

  final String triggerId;
  final TriggerDeliverySource source;
  final DateTime deliveredAt;
  final DateTime? scheduledAt;
  final Map<String, Object?> payload;
}

class TriggerPollState {
  const TriggerPollState({
    this.lastCheckedAt,
    this.lastDeliveredAt,
    this.cursor,
  });

  final DateTime? lastCheckedAt;
  final DateTime? lastDeliveredAt;
  final String? cursor;

  TriggerPollState copyWith({
    DateTime? lastCheckedAt,
    bool clearLastCheckedAt = false,
    DateTime? lastDeliveredAt,
    bool clearLastDeliveredAt = false,
    String? cursor,
    bool clearCursor = false,
  }) {
    return TriggerPollState(
      lastCheckedAt: clearLastCheckedAt
          ? null
          : lastCheckedAt ?? this.lastCheckedAt,
      lastDeliveredAt: clearLastDeliveredAt
          ? null
          : lastDeliveredAt ?? this.lastDeliveredAt,
      cursor: clearCursor ? null : cursor ?? this.cursor,
    );
  }
}

class TriggerFireResult {
  const TriggerFireResult({
    required this.decision,
    required this.state,
    this.reason,
  });

  final TriggerDecision decision;
  final String? reason;
  final TriggerState state;
}

class TriggerExecutionEvent {
  const TriggerExecutionEvent({
    required this.trigger,
    required this.delivery,
    required this.execution,
    this.appliedStandingOrderIds = const <String>[],
  });

  final TriggerConfig trigger;
  final TriggerDelivery delivery;
  final TriggerExecutionRecord execution;
  final List<String> appliedStandingOrderIds;
}
