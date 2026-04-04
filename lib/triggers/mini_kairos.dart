import 'package:openreef/triggers/trigger_models.dart';

enum KairosDecisionType { proceed, delay, skip, queue }

class KairosContext {
  const KairosContext({
    required this.isAppForeground,
    required this.batteryLevel,
    required this.activeSubAgents,
  });

  final bool isAppForeground;
  final int batteryLevel;
  final int activeSubAgents;
}

class KairosDecision {
  const KairosDecision._({
    required this.type,
    this.reason,
    this.untilSignal,
    this.priority,
  });

  const KairosDecision.proceed() : this._(type: KairosDecisionType.proceed);

  const KairosDecision.delay({
    required String reason,
    required String untilSignal,
  }) : this._(
         type: KairosDecisionType.delay,
         reason: reason,
         untilSignal: untilSignal,
       );

  const KairosDecision.skip({required String reason})
    : this._(type: KairosDecisionType.skip, reason: reason);

  const KairosDecision.queue({required TriggerPriority priority})
    : this._(type: KairosDecisionType.queue, priority: priority);

  final KairosDecisionType type;
  final String? reason;
  final String? untilSignal;
  final TriggerPriority? priority;
}

class MiniKairosPolicy {
  const MiniKairosPolicy({
    this.lowBatteryThreshold = 10,
    this.maxConcurrentSubAgents = 3,
  });

  final int lowBatteryThreshold;
  final int maxConcurrentSubAgents;
}

class MiniKairos {
  MiniKairos({
    required Future<KairosContext> Function() contextLoader,
    this.policy = const MiniKairosPolicy(),
  }) : _contextLoader = contextLoader;

  final Future<KairosContext> Function() _contextLoader;
  final MiniKairosPolicy policy;

  Future<KairosDecision> evaluate(TriggerConfig trigger) async {
    final context = await _contextLoader();

    if (!context.isAppForeground && trigger.requiresUserAttention) {
      return const KairosDecision.delay(
        reason: 'user_attention_required',
        untilSignal: 'app_foreground',
      );
    }

    if (context.batteryLevel < policy.lowBatteryThreshold &&
        trigger.isExpensive) {
      return const KairosDecision.skip(reason: 'battery_low');
    }

    if (context.activeSubAgents >= policy.maxConcurrentSubAgents) {
      return KairosDecision.queue(priority: trigger.priority);
    }

    return const KairosDecision.proceed();
  }
}
