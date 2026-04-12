import 'package:openreef/context/compiled_context_package.dart';

class ContextAudit {
  const ContextAudit();

  ContextAuditTrace build({
    required ContextPlan plan,
    required List<CompiledContextSection> sections,
    required List<ContextReduction> reductions,
    List<String> droppedSectionIds = const <String>[],
    List<ContextDroppedItem> droppedItems = const <ContextDroppedItem>[],
    bool degraded = false,
    String? degradationReason,
  }) {
    final included = sections
        .map((section) => section.id)
        .toList(growable: false);
    final tokenUsage = <String, int>{
      for (final section in sections) section.id: section.estimatedTokens,
    };
    final inclusionReasons = <String, String>{
      for (final section in sections) section.id: section.reason,
    };
    final exclusions = <String, String>{
      ...plan.toolExposure.exclusionReasons.map(
        (key, value) => MapEntry<String, String>('tool:$key', value),
      ),
      ...plan.policyRejections.map(
        (key, value) => MapEntry<String, String>('candidate:$key', value),
      ),
      for (final entry in plan.policyRejections.entries.where(
        (entry) => plan.skillPlan.candidateSkills.any(
          (skill) => skill.id == entry.key,
        ),
      ))
        'skill:${entry.key}': entry.value,
      for (final decision in plan.skillPlan.candidateDecisions.where(
        (decision) => decision.status != SkillDecisionStatus.activated,
      ))
        'skill:${decision.skillId}': decision.activationReason,
      for (final decision in plan.skillPlan.decisions.where(
        (decision) => decision.status != SkillDecisionStatus.activated,
      ))
        'skill:${decision.skillId}': decision.activationReason,
    };

    return ContextAuditTrace(
      traceId: 'ctx_${DateTime.now().toUtc().microsecondsSinceEpoch}',
      includedSectionIds: included,
      droppedSectionIds: droppedSectionIds,
      sectionTokenUsage: tokenUsage,
      inclusionReasons: inclusionReasons,
      exclusionReasons: exclusions,
      policyDecisions: <ContextPolicyDecision>[
        ...plan.policyDecisions,
        if (degraded)
          ContextPolicyDecision(
            id: 'context_degraded',
            decision: 'degraded',
            reason: degradationReason ?? 'Context degraded to fit budget.',
          ),
      ],
      reductions: reductions,
      droppedItems: droppedItems,
      toolInclusionReasons: plan.toolExposure.inclusionReasons,
      skillDecisions: <SkillActivationDecision>[
        ...plan.skillPlan.candidateDecisions,
        ...plan.skillPlan.decisions,
      ],
      retrievedCandidates: plan.retrievedCandidates,
      retrievalScores: plan.retrievalScores,
      selectorDecisions: plan.selectorDecisions,
      selectorViolations: plan.selectorViolations,
      policyRejections: plan.policyRejections,
      finalExposureReasons: plan.finalExposureReasons,
      candidateIndexVersion: plan.candidateIndexVersion,
      embeddingModelId: plan.embeddingModelId,
    );
  }
}
