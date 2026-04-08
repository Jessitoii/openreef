import 'dart:convert';

import 'package:openreef/triggers/trigger_models.dart';

class TriggerCodec {
  const TriggerCodec();

  Map<String, Object?> encode(TriggerConfig trigger) {
    return <String, Object?>{
      'id': trigger.id,
      'name': trigger.name,
      'prompt': trigger.prompt,
      'type': trigger.type.name,
      'priority': trigger.priority.name,
      'enabled': trigger.enabled,
      'requiresUserAttention': trigger.requiresUserAttention,
      'isExpensive': trigger.isExpensive,
      'payload': trigger.payload,
      'scheduleSpec': trigger.scheduleSpec == null
          ? null
          : <String, Object?>{
              'hour': trigger.scheduleSpec!.hour,
              'minute': trigger.scheduleSpec!.minute,
              'recurrence': trigger.scheduleSpec!.recurrence.name,
            },
      'intervalSpec': trigger.intervalSpec == null
          ? null
          : <String, Object?>{
              'everyMs': trigger.intervalSpec!.every.inMilliseconds,
            },
      'cronSpec': trigger.cronSpec == null
          ? null
          : <String, Object?>{
              'expression': trigger.cronSpec!.expression,
            },
      'batterySpec': trigger.batterySpec == null
          ? null
          : <String, Object?>{
              'condition': trigger.batterySpec!.condition.name,
              'level': trigger.batterySpec!.level,
              'requiredState': trigger.batterySpec!.requiredState,
            },
      'mcpEventSpec': trigger.mcpEventSpec == null
          ? null
          : <String, Object?>{
              'sourceId': trigger.mcpEventSpec!.sourceId,
              'eventName': trigger.mcpEventSpec!.eventName,
              'payloadMatches': trigger.mcpEventSpec!.payloadMatches,
            },
      'standingOrderSpec': trigger.standingOrderSpec == null
          ? null
          : <String, Object?>{
              'appliesToTypes': trigger.standingOrderSpec!.appliesToTypes
                  .map((entry) => entry.name)
                  .toList(growable: false),
              'payloadMatches': trigger.standingOrderSpec!.payloadMatches,
            },
    };
  }

  TriggerConfig decode(Map<String, Object?> json) {
    final scheduleJson = json['scheduleSpec'];
    final intervalJson = json['intervalSpec'];
    final cronJson = json['cronSpec'];
    final batteryJson = json['batterySpec'];
    final mcpEventJson = json['mcpEventSpec'];
    final standingOrderJson = json['standingOrderSpec'];
    final scheduleMap = scheduleJson is Map
        ? Map<String, Object?>.from(scheduleJson)
        : null;
    final intervalMap = intervalJson is Map
        ? Map<String, Object?>.from(intervalJson)
        : null;
    final cronMap = cronJson is Map ? Map<String, Object?>.from(cronJson) : null;
    final batteryMap = batteryJson is Map
        ? Map<String, Object?>.from(batteryJson)
        : null;
    final mcpEventMap = mcpEventJson is Map
        ? Map<String, Object?>.from(mcpEventJson)
        : null;
    final standingOrderMap = standingOrderJson is Map
        ? Map<String, Object?>.from(standingOrderJson)
        : null;
    return TriggerConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      type: TriggerType.values.byName(json['type'] as String? ?? 'manual'),
      priority: TriggerPriority.values.byName(
        json['priority'] as String? ?? 'normal',
      ),
      enabled: json['enabled'] as bool? ?? true,
      requiresUserAttention: json['requiresUserAttention'] as bool? ?? false,
      isExpensive: json['isExpensive'] as bool? ?? false,
      payload: _payloadFromJson(json['payload']),
      scheduleSpec: scheduleMap == null
          ? null
          : ScheduleTriggerSpec(
              hour: (scheduleMap['hour'] as num?)?.toInt() ?? 0,
              minute: (scheduleMap['minute'] as num?)?.toInt() ?? 0,
              recurrence: ScheduleRecurrence.values.byName(
                scheduleMap['recurrence'] as String? ?? 'daily',
              ),
            ),
      intervalSpec: intervalMap == null
          ? null
          : IntervalTriggerSpec(
              every: Duration(
                milliseconds: (intervalMap['everyMs'] as num?)?.toInt() ?? 0,
              ),
            ),
      cronSpec: cronMap == null
          ? null
          : CronTriggerSpec(
              expression: cronMap['expression'] as String? ?? '',
            ),
      batterySpec: batteryMap == null
          ? null
          : BatteryTriggerSpec(
              condition: BatteryTriggerCondition.values.byName(
                batteryMap['condition'] as String? ?? 'levelAtOrBelow',
              ),
              level: (batteryMap['level'] as num?)?.toInt(),
              requiredState: batteryMap['requiredState'] as String?,
            ),
      mcpEventSpec: mcpEventMap == null
          ? null
          : McpEventTriggerSpec(
              sourceId: mcpEventMap['sourceId'] as String? ?? '',
              eventName: mcpEventMap['eventName'] as String? ?? '',
              payloadMatches: _payloadFromJson(mcpEventMap['payloadMatches']),
            ),
      standingOrderSpec: standingOrderMap == null
          ? null
          : StandingOrderSpec(
              appliesToTypes: ((standingOrderMap['appliesToTypes'] as List?) ??
                      const <Object?>[])
                  .map((entry) => TriggerType.values.byName(entry.toString()))
                  .toList(growable: false),
              payloadMatches: _payloadFromJson(standingOrderMap['payloadMatches']),
            ),
    );
  }

  List<Map<String, Object?>> encodeAll(List<TriggerConfig> triggers) {
    return triggers.map(encode).toList(growable: false);
  }

  List<TriggerConfig> decodeAll(String rawJson) {
    if (rawJson.trim().isEmpty) {
      return const <TriggerConfig>[];
    }
    final decoded = jsonDecode(rawJson);
    if (decoded is! List) {
      return const <TriggerConfig>[];
    }
    return decoded
        .whereType<Map>()
        .map((entry) => decode(Map<String, Object?>.from(entry)))
        .toList(growable: false);
  }

  Map<String, Object?> _payloadFromJson(Object? rawPayload) {
    if (rawPayload is Map<String, Object?>) {
      return rawPayload;
    }
    if (rawPayload is Map) {
      return Map<String, Object?>.from(rawPayload);
    }
    return const <String, Object?>{};
  }
}
