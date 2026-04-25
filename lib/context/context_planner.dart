import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/capability_retrieval.dart';
import 'package:openreef/context/compiled_context_package.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/models/embedding_model_manager.dart';

class ContextPlanner {
  ContextPlanner({
    this.toolLimit = 8,
    this.skillLimit = 2,
    this.outputReserve = ContextAssembler.outputReserve,
    CapabilityEmbeddingIndex? capabilityIndex,
    CapabilitySelector? selector,
    this.topK = 16,
  }) : _capabilityIndex =
           capabilityIndex ??
           CapabilityEmbeddingIndex(
             embedder: OnDeviceSemanticTextEmbedder.verifiedDefault(),
           ),
       _selector = selector ?? const SemanticFallbackCapabilitySelector();

  final int toolLimit;
  final int skillLimit;
  final int outputReserve;
  final int topK;
  final CapabilityEmbeddingIndex _capabilityIndex;
  final CapabilitySelector _selector;

  Future<ContextPlan> plan({
    required String userMessage,
    required List<AgentMessage> conversationHistory,
    required int modelContextWindow,
    required ToolCatalog toolCatalog,
    required SkillCatalog skillCatalog,
    required bool compactRequested,
    required ExecutionMode executionMode,
    ExecutionPolicy? executionPolicy,
  }) async {
    final classification = TurnClassifier().classify(
      userMessage: userMessage,
      conversationHistory: conversationHistory,
      compactRequested: compactRequested,
    );
    final safety = SafetyPolicyEvaluator().evaluate(toolCatalog.listTools());
    final tokenAllocation = TokenBudgetPlanner(outputReserve: outputReserve)
        .plan(
          classification: classification,
          mode: executionMode,
          modelContextWindow: modelContextWindow,
          compactRequested: compactRequested,
        );
    final candidates = const CapabilityCandidateBuilder().build(
      toolCatalog: toolCatalog,
      skillCatalog: skillCatalog,
    );
    var semanticDegradationReason = '';
    late final List<CapabilityRetrievedCandidate> retrieved;
    try {
      retrieved = await SemanticCandidateRetriever(
        index: _capabilityIndex,
        topK: topK,
      ).retrieve(userMessage: userMessage, candidates: candidates);
    } on EmbeddingModelNotReadyException catch (error) {
      semanticDegradationReason = error.userMessage;
      retrieved = const <CapabilityRetrievedCandidate>[];
    } on SemanticEmbeddingUnavailableException catch (error) {
      semanticDegradationReason = error.message;
      retrieved = const <CapabilityRetrievedCandidate>[];
    } on StateError catch (error) {
      semanticDegradationReason = error.message;
      retrieved = const <CapabilityRetrievedCandidate>[];
    }
    debugPrint(
      'OpenReef.ContextPlanner: selector.start candidates=${retrieved.length}',
    );
    var proposal = await _selector.select(
      userMessage: userMessage,
      executionMode: executionMode,
      retrievedCandidates: retrieved,
    );
    debugPrint(
      'OpenReef.ContextPlanner: selector.end primary=${proposal.primaryToolIds.length} fallback=${proposal.fallbackToolIds.length} skills=${proposal.selectedSkillIds.length} degraded=${proposal.degraded}',
    );
    var gate =
        CapabilityPolicyGate(
          toolLimit: toolLimit,
          skillLimit: skillLimit,
        ).apply(
          proposal: proposal,
          retrievedCandidates: retrieved,
          executionMode: executionMode,
          executionPolicy: executionPolicy,
          skillBudget: tokenAllocation.sectionBudgets['skills'] ?? 0,
        );
    var deterministicFallbackReason = '';
    if (gate.toolExposure.exposedTools.isEmpty &&
        (semanticDegradationReason.isNotEmpty || retrieved.isEmpty)) {
      deterministicFallbackReason = semanticDegradationReason.isNotEmpty
          ? semanticDegradationReason
          : 'semantic retrieval returned no candidates';
      final fallbackProposal = _deterministicToolFallbackProposal(
        userMessage: userMessage,
        candidates: candidates,
      );
      if (fallbackProposal.primaryToolIds.isNotEmpty) {
        debugPrint(
          'OpenReef.ContextPlanner: deterministicFallback.start reason=$deterministicFallbackReason primary=${fallbackProposal.primaryToolIds.join(',')}',
        );
        proposal = fallbackProposal;
        gate =
            CapabilityPolicyGate(
              toolLimit: toolLimit,
              skillLimit: skillLimit,
            ).apply(
              proposal: proposal,
              retrievedCandidates: _fallbackRetrievedCandidates(candidates),
              executionMode: executionMode,
              executionPolicy: executionPolicy,
              skillBudget: tokenAllocation.sectionBudgets['skills'] ?? 0,
            );
        debugPrint(
          'OpenReef.ContextPlanner: deterministicFallback.end tools=${gate.toolExposure.exposedTools.length}',
        );
      }
    }
    skillCatalog.recordTurnState(
      matchedSkillIds: retrieved
          .where((entry) => entry.candidate.kind == CapabilityKind.skill)
          .map((entry) => entry.candidate.id)
          .toList(growable: false),
      activeSkillIds: gate.skillPlan.activeSkills
          .map((skill) => skill.id)
          .toList(growable: false),
    );
    final workflowContext = WorkflowStatePlanner().plan(
      userMessage: userMessage,
      conversationHistory: conversationHistory,
      classification: classification,
      mode: executionMode,
    );
    final memoryPlan = MemoryRetrievalPlanner().plan(
      classification: classification,
      tokenAllocation: tokenAllocation,
    );
    final historyBudget = HistoryPlanner().budget(tokenAllocation);

    return ContextPlan(
      executionMode: executionMode,
      turnClassification: classification,
      toolExposure: gate.toolExposure,
      memoryRetrievalPlan: memoryPlan,
      historyBudget: historyBudget,
      skillPlan: gate.skillPlan,
      workflowContext: workflowContext,
      tokenAllocation: tokenAllocation,
      safetyEnvelope: safety,
      retrievedCandidates: retrieved
          .map((entry) => entry.candidate.id)
          .toList(growable: false),
      retrievalScores: <String, double>{
        for (final entry in retrieved) entry.candidate.id: entry.score,
      },
      selectorDecisions: <String, String>{
        for (final id in proposal.primaryToolIds) id: 'selector primary tool',
        for (final id in proposal.fallbackToolIds) id: 'selector fallback tool',
        for (final id in proposal.selectedSkillIds)
          id: 'selector selected skill',
        for (final rejection in proposal.rejected)
          rejection.id: rejection.reason,
        if (proposal.degraded)
          'selector_degraded':
              proposal.degradationReason ?? 'selector degraded',
        if (semanticDegradationReason.isNotEmpty)
          'semantic_retrieval_unavailable': semanticDegradationReason,
        if (deterministicFallbackReason.isNotEmpty)
          'deterministic_tool_fallback': deterministicFallbackReason,
      },
      selectorViolations: <String>[
        ...proposal.violations,
        ...gate.selectorViolations,
      ],
      policyRejections: gate.policyRejections,
      finalExposureReasons: gate.finalExposureReasons,
      candidateIndexVersion: _capabilityIndex.version,
      embeddingModelId: _capabilityIndex.modelId,
      policyDecisions: <ContextPolicyDecision>[
        ContextPolicyDecision(
          id: 'execution_mode',
          decision: executionMode.name,
          reason: 'Provided by executor/runtime state.',
        ),
        ContextPolicyDecision(
          id: 'tool_exposure',
          decision: '${gate.toolExposure.primaryTools.length} primary tools',
          reason: 'Semantic retrieval, selector proposal, and policy gate.',
        ),
        ContextPolicyDecision(
          id: 'skill_injection',
          decision: '${gate.skillPlan.activeSkills.length} active skills',
          reason: 'Semantic retrieval plus deterministic dependency policy.',
        ),
        if (proposal.degraded)
          ContextPolicyDecision(
            id: 'selector_degraded',
            decision: 'semantic_fallback',
            reason: proposal.degradationReason ?? 'selector degraded',
          ),
        if (semanticDegradationReason.isNotEmpty)
          ContextPolicyDecision(
            id: 'semantic_retrieval',
            decision: 'unavailable',
            reason: semanticDegradationReason,
          ),
        if (deterministicFallbackReason.isNotEmpty)
          ContextPolicyDecision(
            id: 'deterministic_tool_fallback',
            decision: '${gate.toolExposure.primaryTools.length} primary tools',
            reason: deterministicFallbackReason,
          ),
      ],
    );
  }

  CandidateSelectionProposal _deterministicToolFallbackProposal({
    required String userMessage,
    required List<CapabilityCandidate> candidates,
  }) {
    final userTokens = ContextAssembler.normalizeTokens(userMessage).toSet();
    if (userTokens.isEmpty) {
      return const CandidateSelectionProposal();
    }
    final scored = <_ScoredCapability>[];
    for (final candidate in candidates) {
      if (candidate.kind == CapabilityKind.skill || !candidate.enabled) {
        continue;
      }
      final score = _lexicalCapabilityScore(candidate, userTokens);
      if (score > 0) {
        scored.add(_ScoredCapability(candidate.id, score));
      }
    }
    scored.sort((left, right) {
      final scoreCompare = right.score.compareTo(left.score);
      if (scoreCompare != 0) return scoreCompare;
      return left.id.compareTo(right.id);
    });
    return CandidateSelectionProposal(
      primaryToolIds: scored
          .take(toolLimit)
          .map((entry) => entry.id)
          .toList(growable: false),
      degraded: true,
      degradationReason: 'selector_degraded:deterministic_tool_fallback',
      notes: const <String>[
        'Lexical fallback used after semantic retrieval produced no usable tool candidates.',
      ],
    );
  }

  List<CapabilityRetrievedCandidate> _fallbackRetrievedCandidates(
    List<CapabilityCandidate> candidates,
  ) {
    const documentBuilder = CandidateDocumentBuilder();
    return candidates
        .map(
          (candidate) => CapabilityRetrievedCandidate(
            candidate: candidate,
            score: 0,
            documentHash: 'deterministic:${candidate.id}',
            document: documentBuilder.build(candidate),
          ),
        )
        .toList(growable: false);
  }

  int _lexicalCapabilityScore(
    CapabilityCandidate candidate,
    Set<String> userTokens,
  ) {
    final haystack = ContextAssembler.normalizeTokens(
      [
        candidate.id,
        candidate.displayName,
        candidate.description,
        ...candidate.capabilityPhrases,
        ...candidate.usageExamples,
        ...candidate.tags,
      ].join(' '),
    ).toSet();
    var score = 0;
    for (final token in userTokens) {
      if (haystack.contains(token)) {
        score += candidate.id.contains(token) ? 3 : 1;
      }
    }
    return score;
  }
}

class TurnClassifier {
  TurnClassification classify({
    required String userMessage,
    required List<AgentMessage> conversationHistory,
    required bool compactRequested,
  }) {
    final text = userMessage.toLowerCase();
    final hasContinuation = conversationHistory.any(
      (message) =>
          message.metadata.containsKey('currentStepIndex') ||
          message.content.contains('EXECUTION_CONTINUATION_STATE'),
    );
    final hasToolFailure = conversationHistory.any(
      (message) =>
          message.isToolError ||
          (message.isToolResult &&
              (message.metadata['status']?.toString() ?? '').contains('error')),
    );
    final likelyTrigger = _containsAny(text, <String>[
      'when ',
      'every ',
      'schedule',
      'remind',
      'trigger',
      'cron',
      'alarm',
    ]);
    final likelyCode = _containsAny(text, <String>[
      'file',
      'code',
      'repository',
      'implement',
      'test',
      'debug',
    ]);
    final likelyResearch = _containsAny(text, <String>[
      'search',
      'research',
      'docs',
      'documentation',
      'lookup',
    ]);
    final likelyMemory = _containsAny(text, <String>[
      'remember',
      'memory',
      'what did you know',
      'what do you know',
      'preference',
    ]);
    final likelyConfirmation = _containsAny(text, <String>[
      'delete',
      'send',
      'call',
      'purchase',
      'remove',
      'write',
    ]);
    final likelyMultiStep = _containsAny(text, <String>[
      'plan',
      'workflow',
      'then',
      'after that',
      'step',
      'continue',
    ]);

    final domain = likelyCode
        ? 'code'
        : likelyTrigger
        ? 'calendar'
        : likelyResearch
        ? 'research'
        : likelyMemory
        ? 'memory'
        : 'general';
    final taskType = hasToolFailure
        ? 'recovery'
        : hasContinuation
        ? 'workflow'
        : likelyTrigger
        ? 'automation'
        : likelyCode
        ? 'implementation'
        : 'chat';

    return TurnClassification(
      domain: domain,
      taskType: taskType,
      likelyNeedsTools:
          likelyTrigger || likelyCode || likelyConfirmation || likelyResearch,
      likelyNeedsMemory: likelyMemory || likelyMultiStep || hasContinuation,
      likelyNeedsWorkflowState: hasContinuation || likelyMultiStep,
      likelyNeedsUserConfirmation: likelyConfirmation,
      likelyMultiStep: likelyMultiStep || hasContinuation,
      confidence: compactRequested || hasContinuation || hasToolFailure
          ? 0.95
          : 0.82,
    );
  }

  bool _containsAny(String text, List<String> needles) {
    return needles.any(text.contains);
  }
}

class ExecutionModeResolver {
  ExecutionMode resolve({
    required TurnClassification classification,
    required List<AgentMessage> conversationHistory,
    required bool compactRequested,
  }) {
    if (compactRequested) {
      return ExecutionMode.compactionRecovery;
    }
    if (classification.taskType == 'recovery') {
      return ExecutionMode.recoveryAfterToolFailure;
    }
    if (classification.likelyNeedsWorkflowState) {
      return ExecutionMode.workflowContinuation;
    }
    if (classification.taskType == 'automation') {
      return ExecutionMode.triggerExecution;
    }
    if (classification.likelyNeedsUserConfirmation) {
      return ExecutionMode.confirmationPending;
    }
    if (classification.likelyNeedsTools) {
      return ExecutionMode.reactiveToolUse;
    }
    return ExecutionMode.chat;
  }
}

class SafetyPolicyEvaluator {
  SafetyEnvelope evaluate(List<ToolDefinition> tools) {
    final risky = tools
        .where(
          (tool) =>
              tool.requiresConfirmation ||
              tool.runtimeMetadata['destructive'] == true ||
              tool.tags.contains('destructive'),
        )
        .map((tool) => tool.id)
        .toList(growable: false);
    return SafetyEnvelope(
      confirmationRequired: risky.isNotEmpty,
      riskyToolIds: risky,
      hardConstraints: const <String>[
        'Runtime handles confirmation for risky tools; do not ask for confirmation in chat.',
        'Unavailable or disabled tools must not be called.',
      ],
    );
  }
}

class ToolExposurePlanner {
  const ToolExposurePlanner({required this.toolLimit});

  final int toolLimit;

  ToolExposure plan({
    required TurnClassification classification,
    required ExecutionMode mode,
    required SafetyEnvelope safetyEnvelope,
    required ToolCatalog toolCatalog,
    Set<String> skillRequestedToolIds = const <String>{},
  }) {
    final enabled = toolCatalog
        .listTools()
        .where((tool) => tool.enabled)
        .toList();
    final selected = <ToolDefinition>[];
    final seen = <String>{};
    final exclusions = <String, String>{};
    final inclusions = <String, String>{};

    for (final tool in toolCatalog.listTools().where((tool) => !tool.enabled)) {
      exclusions[tool.id] = 'disabled';
    }

    void addById(String id, String reason) {
      if (selected.length >= toolLimit) {
        exclusions[id] = 'tool budget exhausted';
        return;
      }
      final tool = toolCatalog.byId(id);
      if (tool == null) {
        exclusions[id] = 'missing';
        return;
      }
      if (!tool.enabled) {
        exclusions[id] = 'disabled';
        return;
      }
      if (safetyEnvelope.forbiddenToolIds.contains(tool.id)) {
        exclusions[id] = 'forbidden by safety policy';
        return;
      }
      if (seen.add(tool.id)) {
        selected.add(tool);
        inclusions[tool.id] = reason;
      } else {
        final existing = inclusions[tool.id];
        if (existing == null || existing.contains(reason)) {
          return;
        }
        inclusions[tool.id] = '$existing; $reason';
      }
    }

    for (final id in const <String>[
      'session_status',
      'memory_save',
      'memory_search',
      'notify',
      'settings_read',
    ]) {
      addById(id, 'core runtime tool');
    }

    if (classification.domain == 'calendar' ||
        mode == ExecutionMode.triggerExecution) {
      for (final id in const <String>[
        'trigger_create',
        'trigger_list',
        'alarm_set',
        'cron_add',
      ]) {
        addById(id, 'automation policy match');
      }
    }
    if (classification.domain == 'code') {
      addById('file_read', 'code/file task');
      if (classification.likelyNeedsUserConfirmation) {
        addById('file_write', 'confirmed file task');
      }
    }
    if (selected.any((tool) => tool.requiresConfirmation)) {
      addById('user_confirm', 'confirmation support for risky tool');
    }
    for (final id in skillRequestedToolIds) {
      addById(id, 'required by relevant skill candidate');
    }

    final scored = enabled.where((tool) => !seen.contains(tool.id)).toList()
      ..sort((left, right) {
        final rightScore = _score(right, classification, mode);
        final leftScore = _score(left, classification, mode);
        return rightScore.compareTo(leftScore);
      });
    for (final tool in scored) {
      if (selected.length >= toolLimit) {
        exclusions[tool.id] = 'tool budget exhausted';
        continue;
      }
      if (_score(tool, classification, mode) <= 0) {
        exclusions[tool.id] = 'irrelevant to mode/task';
        continue;
      }
      if (seen.add(tool.id)) {
        selected.add(tool);
        inclusions[tool.id] = 'matched task/tool policy score';
      }
    }

    return ToolExposure(
      primaryTools: List<ToolDefinition>.unmodifiable(selected),
      excludedToolIds: exclusions.keys.toList(growable: false),
      exclusionReasons: Map<String, String>.unmodifiable(exclusions),
      inclusionReasons: Map<String, String>.unmodifiable(inclusions),
    );
  }

  int _score(
    ToolDefinition tool,
    TurnClassification classification,
    ExecutionMode mode,
  ) {
    var score = 0;
    if (tool.category == classification.domain) score += 4;
    if (tool.tags.contains(classification.domain)) score += 3;
    if (tool.tags.contains(classification.taskType)) score += 2;
    final searchable =
        '${tool.id} ${tool.description} ${tool.category} ${tool.tags.join(' ')}'
            .toLowerCase();
    for (final token in <String>[
      classification.domain,
      classification.taskType,
      'search',
      'docs',
    ]) {
      if (searchable.contains(token)) {
        score += 1;
      }
    }
    if (tool.requiresConfirmation &&
        classification.likelyNeedsUserConfirmation) {
      score += 2;
    }
    if (mode == ExecutionMode.workflowContinuation &&
        tool.runtimeMetadata['requiresWorkflowState'] == true) {
      score += 3;
    }
    return score;
  }
}

class MemoryRetrievalPlanner {
  MemoryRetrievalPlan plan({
    required TurnClassification classification,
    required TokenAllocation tokenAllocation,
  }) {
    final budget = tokenAllocation.sectionBudgets['memory'] ?? 0;
    return MemoryRetrievalPlan(
      fetchSemantic: classification.likelyNeedsMemory,
      fetchEpisodic: classification.likelyMultiStep,
      fetchProcedural: classification.taskType != 'chat',
      fetchWorking: true,
      semanticBudget: (budget * 0.45).floor(),
      episodicBudget: (budget * 0.25).floor(),
      proceduralBudget: (budget * 0.15).floor(),
      workingBudget: math.max(0, budget - (budget * 0.85).floor()),
    );
  }
}

class HistoryPlanner {
  int budget(TokenAllocation tokenAllocation) {
    return tokenAllocation.sectionBudgets['history'] ?? 0;
  }
}

class SkillPlanner {
  const SkillPlanner({required this.skillLimit});

  final int skillLimit;

  SkillPlan planCandidates({
    required String userMessage,
    required TurnClassification classification,
    required ExecutionMode mode,
    required SkillCatalog skillCatalog,
    required int skillBudget,
  }) {
    final normalized = _normalizeTokens(userMessage);
    final scored = <_ScoredSkill>[];
    final decisions = <SkillActivationDecision>[];

    for (final skill in skillCatalog.listSkills()) {
      if (!skill.runtimeEligible) {
        decisions.add(
          SkillActivationDecision(
            skillId: skill.id,
            status: SkillDecisionStatus.skippedPolicy,
            activationReason:
                'Skill is disabled, missing tools, or runtime-ineligible.',
            injectionBudget: 0,
          ),
        );
        continue;
      }
      if (skill.allowedModes.isNotEmpty && !skill.allowedModes.contains(mode)) {
        decisions.add(
          SkillActivationDecision(
            skillId: skill.id,
            status: SkillDecisionStatus.skippedPolicy,
            activationReason: 'Execution mode ${mode.name} is not allowed.',
            injectionBudget: 0,
          ),
        );
        continue;
      }
      final scoreResult = _scoreSkill(skill, normalized, classification, mode);
      final score = scoreResult.score;
      if (score <= 0) {
        decisions.add(
          SkillActivationDecision(
            skillId: skill.id,
            status: SkillDecisionStatus.skippedIrrelevant,
            activationReason: 'No activation policy matched this turn.',
            injectionBudget: 0,
          ),
        );
        continue;
      }
      scored.add(_ScoredSkill(skill, score));
      decisions.add(
        SkillActivationDecision(
          skillId: skill.id,
          status: SkillDecisionStatus.skippedBudget,
          activationReason: scoreResult.reason,
          injectionBudget: 0,
          score: score,
          requestedToolIds: skill.toolsRequired,
        ),
      );
    }

    scored.sort((left, right) {
      final priorityCompare = right.skill.priority.compareTo(
        left.skill.priority,
      );
      if (priorityCompare != 0) return priorityCompare;
      return right.score.compareTo(left.score);
    });

    final requestedToolIds = <String>{};
    for (final entry in scored.take(skillLimit)) {
      requestedToolIds.addAll(entry.skill.toolsRequired);
    }
    return SkillPlan(
      decisions: List<SkillActivationDecision>.unmodifiable(decisions),
      candidateDecisions: List<SkillActivationDecision>.unmodifiable(decisions),
      candidateSkills: scored
          .map((entry) => entry.skill)
          .toList(growable: false),
      requestedToolIds: requestedToolIds.toList(growable: false),
      skillBudget: skillBudget,
    );
  }

  SkillPlan finalizePlan({
    required SkillPlan candidatePlan,
    required ExecutionMode mode,
    required SkillCatalog skillCatalog,
    required Set<String> exposedToolIds,
  }) {
    final candidatesById = <String, SkillActivationDecision>{
      for (final decision in candidatePlan.candidateDecisions)
        decision.skillId: decision,
    };
    final scored = <_ScoredSkill>[];
    for (final skill in candidatePlan.candidateSkills) {
      final decision = candidatesById[skill.id];
      if (decision == null || decision.score <= 0) {
        continue;
      }
      scored.add(_ScoredSkill(skill, decision.score));
    }
    scored.sort((left, right) {
      final priorityCompare = right.skill.priority.compareTo(
        left.skill.priority,
      );
      if (priorityCompare != 0) return priorityCompare;
      return right.score.compareTo(left.score);
    });

    final active = <SkillDefinition>[];
    var remainingBudget = candidatePlan.skillBudget;
    final decisions = <SkillActivationDecision>[];
    for (final entry in scored) {
      final incompatible = active.any(
        (activeSkill) =>
            entry.skill.incompatibleSkillIds.contains(activeSkill.id) ||
            activeSkill.incompatibleSkillIds.contains(entry.skill.id),
      );
      if (incompatible) {
        decisions.add(
          SkillActivationDecision(
            skillId: entry.skill.id,
            status: SkillDecisionStatus.skippedPolicy,
            activationReason: 'Incompatible with an already active skill.',
            injectionBudget: 0,
            score: entry.score,
            requestedToolIds: entry.skill.toolsRequired,
          ),
        );
        continue;
      }
      final missingTools = entry.skill.toolsRequired
          .where((toolId) => !exposedToolIds.contains(toolId))
          .toList(growable: false);
      if (missingTools.isNotEmpty) {
        decisions.add(
          SkillActivationDecision(
            skillId: entry.skill.id,
            status: SkillDecisionStatus.skippedPolicy,
            activationReason:
                'Required tools are not exposed: ${missingTools.join(', ')}.',
            injectionBudget: 0,
            score: entry.score,
            requestedToolIds: entry.skill.toolsRequired,
          ),
        );
        continue;
      }
      final perSkillBudget = math.min(entry.skill.maxTokens, remainingBudget);
      if (active.length >= skillLimit || perSkillBudget <= 0) {
        decisions.add(
          SkillActivationDecision(
            skillId: entry.skill.id,
            status: SkillDecisionStatus.skippedBudget,
            activationReason: 'Progressive skill budget exhausted.',
            injectionBudget: 0,
            score: entry.score,
            requestedToolIds: entry.skill.toolsRequired,
          ),
        );
        continue;
      }
      final trimmed = ContextAssembler.trimToTokens(
        entry.skill.content,
        perSkillBudget,
      );
      active.add(
        entry.skill.copyWith(content: trimmed, maxTokens: perSkillBudget),
      );
      remainingBudget -= _estimateTextTokens(trimmed);
      decisions.add(
        SkillActivationDecision(
          skillId: entry.skill.id,
          status: SkillDecisionStatus.activated,
          activationReason:
              candidatesById[entry.skill.id]?.activationReason ??
              'Matched activation policy.',
          injectionBudget: perSkillBudget,
          score: entry.score,
          toolAllowanceSnapshot: exposedToolIds.toList(growable: false),
          requestedToolIds: entry.skill.toolsRequired,
        ),
      );
    }

    skillCatalog.recordTurnState(
      matchedSkillIds: scored
          .map((entry) => entry.skill.id)
          .toList(growable: false),
      activeSkillIds: active.map((skill) => skill.id).toList(growable: false),
    );

    return SkillPlan(
      activeSkills: List<SkillDefinition>.unmodifiable(active),
      decisions: List<SkillActivationDecision>.unmodifiable(decisions),
      candidateDecisions: candidatePlan.candidateDecisions,
      candidateSkills: candidatePlan.candidateSkills,
      requestedToolIds: candidatePlan.requestedToolIds,
      skillBudget: candidatePlan.skillBudget,
    );
  }

  _SkillScore _scoreSkill(
    SkillDefinition skill,
    List<String> userTokens,
    TurnClassification classification,
    ExecutionMode mode,
  ) {
    var score = 0;
    final reasons = <String>[];
    for (final pattern in skill.triggerPatterns) {
      if (ContextAssembler.matchesPattern(
        userTokens,
        ContextAssembler.normalizeTokens(pattern),
      )) {
        score += 8;
        reasons.add('matched trigger "$pattern"');
      }
    }
    final haystack = ContextAssembler.normalizeTokens(
      '${skill.displayName} ${skill.description} ${skill.activationTerms.join(' ')}',
    ).toSet();
    final overlap = userTokens.where(haystack.contains).toList();
    score += overlap.length;
    if (overlap.isNotEmpty) {
      reasons.add('matched terms ${overlap.join(', ')}');
    }
    if (skill.activationTerms.contains(classification.domain)) {
      score += 3;
      reasons.add('matched domain ${classification.domain}');
    }
    if (skill.activationTerms.contains(classification.taskType)) {
      score += 3;
      reasons.add('matched task ${classification.taskType}');
    }
    if (mode == ExecutionMode.workflowContinuation &&
        skill.activationTerms.contains('workflow')) {
      score += 2;
      reasons.add('matched workflow mode');
    }
    return _SkillScore(
      score,
      reasons.isEmpty ? 'No policy match.' : reasons.join('; '),
    );
  }

  List<String> _normalizeTokens(String text) =>
      ContextAssembler.normalizeTokens(text);

  int _estimateTextTokens(String text) =>
      ContextAssembler.estimateTextTokens(text);
}

class WorkflowStatePlanner {
  WorkflowContext plan({
    required String userMessage,
    required List<AgentMessage> conversationHistory,
    required TurnClassification classification,
    required ExecutionMode mode,
  }) {
    if (!classification.likelyNeedsWorkflowState &&
        mode != ExecutionMode.workflowContinuation) {
      return const WorkflowContext();
    }
    final continuationMessage = conversationHistory.where(
      (message) => message.content.contains('EXECUTION_CONTINUATION_STATE'),
    );
    final metadata = continuationMessage.isEmpty
        ? const <String, Object?>{}
        : continuationMessage.last.metadata;
    return WorkflowContext(
      workflowId: metadata['workflowId'] as String? ?? 'active_session',
      objective: userMessage,
      completedSteps: _stringsFrom(metadata['completedSteps']),
      pendingSteps: _stringsFrom(metadata['pendingSteps']),
      blockers: _stringsFrom(metadata['blockers']),
      artifacts: <String, Object?>{
        ..._mapFrom(metadata['artifacts']),
        if (metadata['currentStepIndex'] != null)
          'currentStepIndex': metadata['currentStepIndex'],
      },
      resolvedEntities: _mapFrom(metadata['variables']),
      currentHypothesis: metadata['waitingReason'] as String?,
    );
  }

  List<String> _stringsFrom(Object? value) {
    if (value is List) {
      return value.map((entry) => entry.toString()).toList(growable: false);
    }
    return const <String>[];
  }

  Map<String, Object?> _mapFrom(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    return const <String, Object?>{};
  }
}

class TokenBudgetPlanner {
  const TokenBudgetPlanner({required this.outputReserve});

  final int outputReserve;

  TokenAllocation plan({
    required TurnClassification classification,
    required ExecutionMode mode,
    required int modelContextWindow,
    required bool compactRequested,
  }) {
    final allocatable = math.max(0, modelContextWindow - outputReserve);
    final workflowWeight = mode == ExecutionMode.workflowContinuation
        ? 0.12
        : 0.04;
    final skillsWeight = classification.taskType == 'chat' ? 0.08 : 0.12;
    final toolWeight = classification.likelyNeedsTools ? 0.14 : 0.08;
    final memoryWeight = classification.likelyNeedsMemory ? 0.24 : 0.16;
    final standingWeight = 0.08;
    final safetyWeight = 0.05;
    final historyWeight = math.max(
      0.15,
      1 -
          workflowWeight -
          skillsWeight -
          toolWeight -
          memoryWeight -
          standingWeight -
          safetyWeight,
    );

    final sectionBudgets = <String, int>{
      'identity': 120,
      'mode': 80,
      'safety': (allocatable * safetyWeight).floor(),
      'workflow': (allocatable * workflowWeight).floor(),
      'tools': (allocatable * toolWeight).floor(),
      'skills': (allocatable * skillsWeight).floor(),
      'standing_orders': (allocatable * standingWeight).floor(),
      'memory': (allocatable * memoryWeight).floor(),
      'history': (allocatable * historyWeight).floor(),
      'tool_state': (allocatable * 0.08).floor(),
      'user': 400,
    };

    return TokenAllocation(
      totalBudget: modelContextWindow,
      outputReserve: outputReserve,
      sectionBudgets: Map<String, int>.unmodifiable(sectionBudgets),
      compactRecommended: compactRequested || modelContextWindow < 3000,
      compactRequired: modelContextWindow < 1800,
    );
  }
}

class _ScoredSkill {
  const _ScoredSkill(this.skill, this.score);

  final SkillDefinition skill;
  final int score;
}

class _ScoredCapability {
  const _ScoredCapability(this.id, this.score);

  final String id;
  final int score;
}

class _SkillScore {
  const _SkillScore(this.score, this.reason);

  final int score;
  final String reason;
}
