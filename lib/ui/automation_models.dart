import 'package:flutter/material.dart';
import 'package:openreef/triggers/trigger_models.dart';

enum AutomationCategory { timeBased, eventState, standingOrders }

enum AutomationDriftState { normal, persistedNotRegistered }

enum AutomationEditorKind {
  schedule,
  interval,
  cron,
  battery,
  mcpEvent,
  boot,
  manual,
  standingOrder,
}

enum AutomationNextRunState { available, unsupported, hidden }

class AutomationListItemViewModel {
  const AutomationListItemViewModel({
    required this.id,
    required this.title,
    required this.summary,
    required this.enabled,
    required this.runtimeStatusLabel,
    required this.driftState,
    required this.canEdit,
    required this.canDelete,
    required this.category,
    required this.subtypeLabel,
    required this.isStandingOrder,
    required this.triggerType,
  });

  final String id;
  final String title;
  final String summary;
  final bool enabled;
  final String runtimeStatusLabel;
  final AutomationDriftState driftState;
  final bool canEdit;
  final bool canDelete;
  final AutomationCategory category;
  final String subtypeLabel;
  final bool isStandingOrder;
  final TriggerType triggerType;
}

class AutomationDetailViewModel {
  const AutomationDetailViewModel({
    required this.id,
    required this.title,
    required this.category,
    required this.subtypeLabel,
    required this.enabled,
    required this.runtimeStatusLabel,
    required this.driftState,
    required this.summary,
    required this.lastRunLabel,
    required this.nextRunLabel,
    required this.nextRunState,
    required this.lastResultLabel,
    required this.failureLabel,
    required this.priorityLabel,
    required this.lastMatchedLabel,
    required this.lastAppliedLabel,
    required this.conditionSummary,
    required this.actionSummary,
    required this.appliesToSummary,
    required this.triggerType,
    required this.isStandingOrder,
  });

  final String id;
  final String title;
  final AutomationCategory category;
  final String subtypeLabel;
  final bool enabled;
  final String runtimeStatusLabel;
  final AutomationDriftState driftState;
  final String summary;
  final String lastRunLabel;
  final String nextRunLabel;
  final AutomationNextRunState nextRunState;
  final String lastResultLabel;
  final String failureLabel;
  final String priorityLabel;
  final String lastMatchedLabel;
  final String lastAppliedLabel;
  final String conditionSummary;
  final String actionSummary;
  final String appliesToSummary;
  final TriggerType triggerType;
  final bool isStandingOrder;
}

class StandingOrderListViewModel {
  const StandingOrderListViewModel({
    required this.id,
    required this.title,
    required this.enabled,
    required this.priorityLabel,
    required this.conditionSummary,
    required this.actionSummary,
    required this.appliesToSummary,
    required this.runtimeStatusLabel,
    required this.driftState,
    required this.canEdit,
    required this.canDelete,
  });

  final String id;
  final String title;
  final bool enabled;
  final String priorityLabel;
  final String conditionSummary;
  final String actionSummary;
  final String appliesToSummary;
  final String runtimeStatusLabel;
  final AutomationDriftState driftState;
  final bool canEdit;
  final bool canDelete;
}

class StandingOrderDetailViewModel {
  const StandingOrderDetailViewModel({
    required this.id,
    required this.title,
    required this.enabled,
    required this.priorityLabel,
    required this.conditionSummary,
    required this.actionSummary,
    required this.appliesToSummary,
    required this.runtimeStatusLabel,
    required this.driftState,
    required this.lastMatchedLabel,
    required this.lastAppliedLabel,
  });

  final String id;
  final String title;
  final bool enabled;
  final String priorityLabel;
  final String conditionSummary;
  final String actionSummary;
  final String appliesToSummary;
  final String runtimeStatusLabel;
  final AutomationDriftState driftState;
  final String lastMatchedLabel;
  final String lastAppliedLabel;
}

class AutomationEditorDraft {
  AutomationEditorDraft({
    required this.kind,
    required this.name,
    required this.enabled,
    required this.actionPrompt,
    required this.priority,
    this.timeOfDay,
    this.repeatInterval,
    this.recurrenceDays = const <int>[],
    this.batteryThreshold,
    this.batteryDirection,
    this.connectedService,
    this.eventType,
    this.standingOrderRule,
    this.id,
    this.rawCron,
    this.rawSourceId,
    this.rawEventId,
    this.payload = const <String, Object?>{},
  });

  factory AutomationEditorDraft.create(AutomationEditorKind kind) {
    return AutomationEditorDraft(
      kind: kind,
      name: '',
      enabled: true,
      actionPrompt: '',
      priority: TriggerPriority.normal,
      timeOfDay: const TimeOfDay(hour: 8, minute: 0),
      repeatInterval: 15,
      batteryThreshold: 20,
      batteryDirection: BatteryTriggerCondition.levelAtOrBelow,
      standingOrderRule: '',
    );
  }

  factory AutomationEditorDraft.fromTrigger(TriggerConfig trigger) {
    return AutomationEditorDraft(
      kind: switch (trigger.type) {
        TriggerType.schedule => AutomationEditorKind.schedule,
        TriggerType.interval => AutomationEditorKind.interval,
        TriggerType.cron => AutomationEditorKind.cron,
        TriggerType.battery => AutomationEditorKind.battery,
        TriggerType.mcpEvent => AutomationEditorKind.mcpEvent,
        TriggerType.boot => AutomationEditorKind.boot,
        TriggerType.manual => AutomationEditorKind.manual,
        TriggerType.standingOrder => AutomationEditorKind.standingOrder,
      },
      id: trigger.id,
      name: trigger.name,
      enabled: trigger.enabled,
      actionPrompt: trigger.prompt,
      priority: trigger.priority,
      timeOfDay: trigger.scheduleSpec == null
          ? const TimeOfDay(hour: 8, minute: 0)
          : TimeOfDay(
              hour: trigger.scheduleSpec!.hour,
              minute: trigger.scheduleSpec!.minute,
            ),
      repeatInterval: trigger.intervalSpec?.every.inMinutes,
      batteryThreshold: trigger.batterySpec?.level,
      batteryDirection: trigger.batterySpec?.condition,
      connectedService: trigger.mcpEventSpec?.sourceId,
      eventType: trigger.mcpEventSpec?.eventName,
      standingOrderRule: trigger.standingOrderSpec == null
          ? ''
          : trigger.standingOrderSpec!.payloadMatches.isEmpty
              ? 'any payload'
              : 'payload conditions',
      rawCron: trigger.cronSpec?.expression,
      rawSourceId: trigger.mcpEventSpec?.sourceId,
      rawEventId: trigger.mcpEventSpec?.eventName,
      payload: trigger.payload,
    );
  }

  final AutomationEditorKind kind;
  final String name;
  final bool enabled;
  final String actionPrompt;
  final TriggerPriority priority;
  final TimeOfDay? timeOfDay;
  final int? repeatInterval;
  final List<int> recurrenceDays;
  final int? batteryThreshold;
  final BatteryTriggerCondition? batteryDirection;
  final String? connectedService;
  final String? eventType;
  final String? standingOrderRule;
  final String? id;
  final String? rawCron;
  final String? rawSourceId;
  final String? rawEventId;
  final Map<String, Object?> payload;

  AutomationEditorDraft copyWith({
    AutomationEditorKind? kind,
    String? name,
    bool? enabled,
    String? actionPrompt,
    TriggerPriority? priority,
    TimeOfDay? timeOfDay,
    int? repeatInterval,
    List<int>? recurrenceDays,
    int? batteryThreshold,
    BatteryTriggerCondition? batteryDirection,
    String? connectedService,
    String? eventType,
    String? standingOrderRule,
    String? id,
    String? rawCron,
    String? rawSourceId,
    String? rawEventId,
    Map<String, Object?>? payload,
  }) {
    return AutomationEditorDraft(
      kind: kind ?? this.kind,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      actionPrompt: actionPrompt ?? this.actionPrompt,
      priority: priority ?? this.priority,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      repeatInterval: repeatInterval ?? this.repeatInterval,
      recurrenceDays: recurrenceDays ?? this.recurrenceDays,
      batteryThreshold: batteryThreshold ?? this.batteryThreshold,
      batteryDirection: batteryDirection ?? this.batteryDirection,
      connectedService: connectedService ?? this.connectedService,
      eventType: eventType ?? this.eventType,
      standingOrderRule: standingOrderRule ?? this.standingOrderRule,
      id: id ?? this.id,
      rawCron: rawCron ?? this.rawCron,
      rawSourceId: rawSourceId ?? this.rawSourceId,
      rawEventId: rawEventId ?? this.rawEventId,
      payload: payload ?? this.payload,
    );
  }

  TriggerConfig toTriggerConfig() {
    final resolvedId = (id ?? '').trim().isEmpty
        ? 'automation_${DateTime.now().microsecondsSinceEpoch}'
        : id!.trim();
    return switch (kind) {
      AutomationEditorKind.schedule => TriggerConfig(
        id: resolvedId,
        name: name.trim(),
        prompt: actionPrompt.trim(),
        type: TriggerType.schedule,
        priority: priority,
        enabled: enabled,
        scheduleSpec: ScheduleTriggerSpec(
          hour: timeOfDay?.hour ?? 8,
          minute: timeOfDay?.minute ?? 0,
        ),
        payload: payload,
      ),
      AutomationEditorKind.interval => TriggerConfig(
        id: resolvedId,
        name: name.trim(),
        prompt: actionPrompt.trim(),
        type: TriggerType.interval,
        priority: priority,
        enabled: enabled,
        intervalSpec: IntervalTriggerSpec(
          every: Duration(minutes: repeatInterval ?? 15),
        ),
        payload: payload,
      ),
      AutomationEditorKind.cron => TriggerConfig(
        id: resolvedId,
        name: name.trim(),
        prompt: actionPrompt.trim(),
        type: TriggerType.cron,
        priority: priority,
        enabled: enabled,
        cronSpec: CronTriggerSpec(expression: rawCron?.trim() ?? '0 9 * * *'),
        payload: payload,
      ),
      AutomationEditorKind.battery => TriggerConfig(
        id: resolvedId,
        name: name.trim(),
        prompt: actionPrompt.trim(),
        type: TriggerType.battery,
        priority: priority,
        enabled: enabled,
        batterySpec: BatteryTriggerSpec(
          condition: batteryDirection ?? BatteryTriggerCondition.levelAtOrBelow,
          level: batteryThreshold,
        ),
        payload: payload,
      ),
      AutomationEditorKind.mcpEvent => TriggerConfig(
        id: resolvedId,
        name: name.trim(),
        prompt: actionPrompt.trim(),
        type: TriggerType.mcpEvent,
        priority: priority,
        enabled: enabled,
        mcpEventSpec: McpEventTriggerSpec(
          sourceId: rawSourceId?.trim() ?? connectedService?.trim() ?? '',
          eventName: rawEventId?.trim() ?? eventType?.trim() ?? '',
        ),
        payload: payload,
      ),
      AutomationEditorKind.boot => TriggerConfig(
        id: resolvedId,
        name: name.trim(),
        prompt: actionPrompt.trim(),
        type: TriggerType.boot,
        priority: priority,
        enabled: enabled,
        payload: payload,
      ),
      AutomationEditorKind.manual => TriggerConfig(
        id: resolvedId,
        name: name.trim(),
        prompt: actionPrompt.trim(),
        type: TriggerType.manual,
        priority: priority,
        enabled: enabled,
        payload: payload,
      ),
      AutomationEditorKind.standingOrder => TriggerConfig(
        id: resolvedId,
        name: name.trim(),
        prompt: actionPrompt.trim(),
        type: TriggerType.standingOrder,
        priority: priority,
        enabled: enabled,
        standingOrderSpec: StandingOrderSpec(
          appliesToTypes: const <TriggerType>[
            TriggerType.schedule,
            TriggerType.interval,
            TriggerType.cron,
            TriggerType.battery,
            TriggerType.mcpEvent,
            TriggerType.manual,
            TriggerType.boot,
          ],
        ),
        payload: payload,
      ),
    };
  }
}
