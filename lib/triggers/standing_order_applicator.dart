import 'package:openreef/agent/run_state.dart';
import 'package:openreef/triggers/trigger_models.dart';

class StandingOrderApplication {
  const StandingOrderApplication({
    required this.appliedIds,
    required this.evaluations,
  });

  final List<String> appliedIds;
  final List<StandingOrderEvaluationRecord> evaluations;

  bool get hasAppliedDirectives => appliedIds.isNotEmpty;
}

class StandingOrderApplicator {
  const StandingOrderApplicator();

  StandingOrderApplication apply({
    required Iterable<TriggerConfig> standingOrders,
    required TriggerConfig trigger,
    required Map<String, Object?> payload,
    required String runId,
    required DateTime evaluatedAt,
  }) {
    final candidates =
        standingOrders
            .where((candidate) => candidate.enabled)
            .where((candidate) => candidate.type == TriggerType.standingOrder)
            .toList(growable: false)
          ..sort((left, right) => left.id.compareTo(right.id));
    final evaluations = <StandingOrderEvaluationRecord>[];
    final appliedIds = <String>[];

    for (final candidate in candidates) {
      final matched = _matches(candidate, trigger, payload);
      if (matched) {
        appliedIds.add(candidate.id);
      }
      final spec = candidate.standingOrderSpec;
      evaluations.add(
        StandingOrderEvaluationRecord(
          evaluationId:
              '${runId}_${candidate.id}_${evaluatedAt.microsecondsSinceEpoch}',
          runId: runId,
          ruleId: candidate.id,
          triggerType: trigger.type.name,
          condition: <String, Object?>{
            'appliesToTypes':
                spec?.appliesToTypes.map((type) => type.name).toList() ??
                const <String>[],
            'payloadMatches': spec?.payloadMatches ?? const <String, Object?>{},
          },
          action: <String, Object?>{
            'type': 'apply_structured_directive',
            'ruleName': candidate.name,
          },
          priority: candidate.priority.index,
          status: matched
              ? StandingOrderEvaluationStatus.matchedApplied
              : StandingOrderEvaluationStatus.notMatched,
          reason: matched ? 'matched' : 'predicate_not_matched',
          evaluatedAt: evaluatedAt,
          displayText: candidate.prompt.trim().isEmpty
              ? null
              : candidate.prompt.trim(),
        ),
      );
    }
    return StandingOrderApplication(
      appliedIds: List<String>.unmodifiable(appliedIds),
      evaluations: List<StandingOrderEvaluationRecord>.unmodifiable(
        evaluations,
      ),
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
