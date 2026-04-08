import 'package:openreef/triggers/trigger_models.dart';

class StandingOrderApplication {
  const StandingOrderApplication({
    required this.appliedIds,
    required this.instructions,
  });

  final List<String> appliedIds;
  final String instructions;

  bool get hasInstructions => instructions.trim().isNotEmpty;
}

class StandingOrderApplicator {
  const StandingOrderApplicator();

  StandingOrderApplication apply({
    required Iterable<TriggerConfig> standingOrders,
    required TriggerConfig trigger,
    required Map<String, Object?> payload,
  }) {
    final matches = standingOrders
        .where((candidate) => candidate.enabled)
        .where((candidate) => candidate.type == TriggerType.standingOrder)
        .where((candidate) => _matches(candidate, trigger, payload))
        .toList(growable: false)
      ..sort((left, right) => left.id.compareTo(right.id));

    return StandingOrderApplication(
      appliedIds: matches.map((entry) => entry.id).toList(growable: false),
      instructions: matches
          .map((entry) => entry.prompt.trim())
          .where((entry) => entry.isNotEmpty)
          .join('\n'),
    );
  }

  bool _matches(
    TriggerConfig standingOrder,
    TriggerConfig trigger,
    Map<String, Object?> payload,
  ) {
    final spec = standingOrder.standingOrderSpec;
    if (spec == null) {
      return false;
    }
    if (!spec.appliesToTypes.contains(trigger.type)) {
      return false;
    }
    for (final entry in spec.payloadMatches.entries) {
      if (payload[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
