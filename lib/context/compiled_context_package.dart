import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/context_assembler.dart';

enum ExecutionMode {
  chat,
  reactiveToolUse,
  workflowContinuation,
  standingOrderExecution,
  triggerExecution,
  confirmationPending,
  recoveryAfterToolFailure,
  compactionRecovery,
}

class TurnClassification {
  const TurnClassification({
    required this.domain,
    required this.taskType,
    required this.likelyNeedsTools,
    required this.likelyNeedsMemory,
    required this.likelyNeedsWorkflowState,
    required this.likelyNeedsUserConfirmation,
    required this.likelyMultiStep,
    required this.confidence,
  });

  final String domain;
  final String taskType;
  final bool likelyNeedsTools;
  final bool likelyNeedsMemory;
  final bool likelyNeedsWorkflowState;
  final bool likelyNeedsUserConfirmation;
  final bool likelyMultiStep;
  final double confidence;
}

class ToolExposure {
  const ToolExposure({
    this.primaryTools = const <ToolDefinition>[],
    this.fallbackTools = const <ToolDefinition>[],
    this.excludedToolIds = const <String>[],
    this.exclusionReasons = const <String, String>{},
    this.inclusionReasons = const <String, String>{},
  });

  final List<ToolDefinition> primaryTools;
  final List<ToolDefinition> fallbackTools;
  final List<String> excludedToolIds;
  final Map<String, String> exclusionReasons;
  final Map<String, String> inclusionReasons;

  List<ToolDefinition> get exposedTools => <ToolDefinition>[
    ...primaryTools,
    ...fallbackTools,
  ];
}

class MemoryRetrievalPlan {
  const MemoryRetrievalPlan({
    required this.fetchSemantic,
    required this.fetchEpisodic,
    required this.fetchProcedural,
    required this.fetchWorking,
    required this.semanticBudget,
    required this.episodicBudget,
    required this.proceduralBudget,
    required this.workingBudget,
  });

  final bool fetchSemantic;
  final bool fetchEpisodic;
  final bool fetchProcedural;
  final bool fetchWorking;
  final int semanticBudget;
  final int episodicBudget;
  final int proceduralBudget;
  final int workingBudget;

  int get totalBudget =>
      semanticBudget + episodicBudget + proceduralBudget + workingBudget;
}

class HistorySelection {
  const HistorySelection({
    this.selectedMessages = const <AgentMessage>[],
    this.droppedMessages = const <AgentMessage>[],
    this.reason = '',
  });

  final List<AgentMessage> selectedMessages;
  final List<AgentMessage> droppedMessages;
  final String reason;
}

class WorkflowContext {
  const WorkflowContext({
    this.workflowId,
    this.objective,
    this.completedSteps = const <String>[],
    this.pendingSteps = const <String>[],
    this.blockers = const <String>[],
    this.artifacts = const <String, Object?>{},
    this.resolvedEntities = const <String, Object?>{},
    this.currentHypothesis,
  });

  final String? workflowId;
  final String? objective;
  final List<String> completedSteps;
  final List<String> pendingSteps;
  final List<String> blockers;
  final Map<String, Object?> artifacts;
  final Map<String, Object?> resolvedEntities;
  final String? currentHypothesis;

  bool get isEmpty =>
      workflowId == null &&
      objective == null &&
      completedSteps.isEmpty &&
      pendingSteps.isEmpty &&
      blockers.isEmpty &&
      artifacts.isEmpty &&
      resolvedEntities.isEmpty &&
      currentHypothesis == null;
}

enum SkillDecisionStatus {
  activated,
  skippedBudget,
  skippedPolicy,
  skippedIrrelevant,
}

class SkillActivationDecision {
  const SkillActivationDecision({
    required this.skillId,
    required this.status,
    required this.activationReason,
    required this.injectionBudget,
    this.score = 0,
    this.toolAllowanceSnapshot = const <String>[],
    this.requestedToolIds = const <String>[],
  });

  final String skillId;
  final SkillDecisionStatus status;
  final String activationReason;
  final int injectionBudget;
  final int score;
  final List<String> toolAllowanceSnapshot;
  final List<String> requestedToolIds;
}

class SkillPlan {
  const SkillPlan({
    this.activeSkills = const <SkillDefinition>[],
    this.decisions = const <SkillActivationDecision>[],
    this.candidateDecisions = const <SkillActivationDecision>[],
    this.candidateSkills = const <SkillDefinition>[],
    this.requestedToolIds = const <String>[],
    this.skillBudget = 0,
  });

  final List<SkillDefinition> activeSkills;
  final List<SkillActivationDecision> decisions;
  final List<SkillActivationDecision> candidateDecisions;
  final List<SkillDefinition> candidateSkills;
  final List<String> requestedToolIds;
  final int skillBudget;
}

class TokenAllocation {
  const TokenAllocation({
    required this.totalBudget,
    required this.outputReserve,
    required this.sectionBudgets,
    this.compactRecommended = false,
    this.compactRequired = false,
  });

  final int totalBudget;
  final int outputReserve;
  final Map<String, int> sectionBudgets;
  final bool compactRecommended;
  final bool compactRequired;
}

class SafetyEnvelope {
  const SafetyEnvelope({
    this.confirmationRequired = false,
    this.riskyToolIds = const <String>[],
    this.forbiddenToolIds = const <String>[],
    this.warningInstructions = const <String>[],
    this.hardConstraints = const <String>[],
  });

  final bool confirmationRequired;
  final List<String> riskyToolIds;
  final List<String> forbiddenToolIds;
  final List<String> warningInstructions;
  final List<String> hardConstraints;
}

class ContextPolicyDecision {
  const ContextPolicyDecision({
    required this.id,
    required this.decision,
    required this.reason,
  });

  final String id;
  final String decision;
  final String reason;
}

class ContextReduction {
  const ContextReduction({
    required this.sectionId,
    required this.strategy,
    required this.beforeTokens,
    required this.afterTokens,
    required this.reason,
  });

  final String sectionId;
  final String strategy;
  final int beforeTokens;
  final int afterTokens;
  final String reason;
}

class ContextDroppedItem {
  const ContextDroppedItem({
    required this.sectionId,
    required this.itemId,
    required this.reason,
    this.estimatedTokens = 0,
  });

  final String sectionId;
  final String itemId;
  final String reason;
  final int estimatedTokens;
}

class ContextAuditTrace {
  const ContextAuditTrace({
    required this.traceId,
    this.includedSectionIds = const <String>[],
    this.droppedSectionIds = const <String>[],
    this.sectionTokenUsage = const <String, int>{},
    this.inclusionReasons = const <String, String>{},
    this.exclusionReasons = const <String, String>{},
    this.policyDecisions = const <ContextPolicyDecision>[],
    this.reductions = const <ContextReduction>[],
    this.droppedItems = const <ContextDroppedItem>[],
    this.toolInclusionReasons = const <String, String>{},
    this.skillDecisions = const <SkillActivationDecision>[],
    this.retrievedCandidates = const <String>[],
    this.retrievalScores = const <String, double>{},
    this.selectorDecisions = const <String, String>{},
    this.selectorViolations = const <String>[],
    this.policyRejections = const <String, String>{},
    this.finalExposureReasons = const <String, String>{},
    this.candidateIndexVersion = 0,
    this.embeddingModelId = '',
  });

  final String traceId;
  final List<String> includedSectionIds;
  final List<String> droppedSectionIds;
  final Map<String, int> sectionTokenUsage;
  final Map<String, String> inclusionReasons;
  final Map<String, String> exclusionReasons;
  final List<ContextPolicyDecision> policyDecisions;
  final List<ContextReduction> reductions;
  final List<ContextDroppedItem> droppedItems;
  final Map<String, String> toolInclusionReasons;
  final List<SkillActivationDecision> skillDecisions;
  final List<String> retrievedCandidates;
  final Map<String, double> retrievalScores;
  final Map<String, String> selectorDecisions;
  final List<String> selectorViolations;
  final Map<String, String> policyRejections;
  final Map<String, String> finalExposureReasons;
  final int candidateIndexVersion;
  final String embeddingModelId;
}

class ContextPlan {
  const ContextPlan({
    required this.executionMode,
    required this.turnClassification,
    required this.toolExposure,
    required this.memoryRetrievalPlan,
    required this.historyBudget,
    required this.skillPlan,
    required this.workflowContext,
    required this.tokenAllocation,
    required this.safetyEnvelope,
    this.retrievedCandidates = const <String>[],
    this.retrievalScores = const <String, double>{},
    this.selectorDecisions = const <String, String>{},
    this.selectorViolations = const <String>[],
    this.policyRejections = const <String, String>{},
    this.finalExposureReasons = const <String, String>{},
    this.candidateIndexVersion = 0,
    this.embeddingModelId = '',
    this.policyDecisions = const <ContextPolicyDecision>[],
  });

  final ExecutionMode executionMode;
  final TurnClassification turnClassification;
  final ToolExposure toolExposure;
  final MemoryRetrievalPlan memoryRetrievalPlan;
  final int historyBudget;
  final SkillPlan skillPlan;
  final WorkflowContext workflowContext;
  final TokenAllocation tokenAllocation;
  final SafetyEnvelope safetyEnvelope;
  final List<String> retrievedCandidates;
  final Map<String, double> retrievalScores;
  final Map<String, String> selectorDecisions;
  final List<String> selectorViolations;
  final Map<String, String> policyRejections;
  final Map<String, String> finalExposureReasons;
  final int candidateIndexVersion;
  final String embeddingModelId;
  final List<ContextPolicyDecision> policyDecisions;
}

class CompiledContextSection {
  const CompiledContextSection({
    required this.id,
    required this.title,
    required this.content,
    required this.estimatedTokens,
    required this.reason,
    this.priority = 0,
    this.critical = false,
    this.sourceCount = 0,
    this.role = AgentMessageRole.system,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String title;
  final String content;
  final int estimatedTokens;
  final String reason;
  final int priority;
  final bool critical;
  final int sourceCount;
  final AgentMessageRole role;
  final Map<String, Object?> metadata;

  AgentMessage toMessage({int turnNumber = 0}) {
    return AgentMessage(
      role: role,
      content: content,
      turnNumber: turnNumber,
      metadata: <String, Object?>{
        'context_section_id': id,
        'context_section_title': title,
        'critical': critical,
        'estimated_tokens': estimatedTokens,
        'reason': reason,
        ...metadata,
      },
    );
  }
}

class CompiledPrompt {
  const CompiledPrompt({
    required this.sections,
    required this.messages,
    required this.estimatedTokens,
  });

  final List<CompiledContextSection> sections;
  final List<AgentMessage> messages;
  final int estimatedTokens;

  String toPrompt() =>
      messages.map((message) => message.toPromptSegment()).join('\n');
}

class MemorySelection {
  const MemorySelection({
    this.memoryIndexBlock = '',
    this.messages = const <AgentMessage>[],
    this.degraded = false,
  });

  final String memoryIndexBlock;
  final List<AgentMessage> messages;
  final bool degraded;
}

class RetrievedContextSources {
  const RetrievedContextSources({
    required this.memoryIndexBlock,
    this.memoryMessages = const <AgentMessage>[],
    this.standingOrders = const <AgentMessage>[],
    this.workflowContext = const WorkflowContext(),
  });

  final String memoryIndexBlock;
  final List<AgentMessage> memoryMessages;
  final List<AgentMessage> standingOrders;
  final WorkflowContext workflowContext;
}

class ReducedContextSources {
  const ReducedContextSources({
    required this.memoryIndexBlock,
    this.memoryMessages = const <AgentMessage>[],
    this.standingOrders = const <AgentMessage>[],
    this.historySelection = const HistorySelection(),
    this.toolStateMessages = const <AgentMessage>[],
    this.workflowContext = const WorkflowContext(),
    this.reductions = const <ContextReduction>[],
    this.droppedItems = const <ContextDroppedItem>[],
    this.compactRecommended = false,
  });

  final String memoryIndexBlock;
  final List<AgentMessage> memoryMessages;
  final List<AgentMessage> standingOrders;
  final HistorySelection historySelection;
  final List<AgentMessage> toolStateMessages;
  final WorkflowContext workflowContext;
  final List<ContextReduction> reductions;
  final List<ContextDroppedItem> droppedItems;
  final bool compactRecommended;
}

class RenderedContextPackage {
  const RenderedContextPackage({
    required this.prompt,
    required this.sections,
    this.droppedSectionIds = const <String>[],
    this.droppedItems = const <ContextDroppedItem>[],
    this.reductions = const <ContextReduction>[],
    this.degraded = false,
    this.degradationReason,
  });

  final CompiledPrompt prompt;
  final List<CompiledContextSection> sections;
  final List<String> droppedSectionIds;
  final List<ContextDroppedItem> droppedItems;
  final List<ContextReduction> reductions;
  final bool degraded;
  final String? degradationReason;
}

class CompiledContextPackage {
  const CompiledContextPackage({
    required this.prompt,
    required this.plan,
    required this.toolExposure,
    required this.memorySelection,
    required this.historySelection,
    required this.workflowContext,
    required this.tokenAllocation,
    required this.safetyEnvelope,
    required this.auditTrace,
    required this.compactRequested,
    required this.compactRecommended,
    required this.executionMode,
    this.degraded = false,
    this.degradationReason,
  });

  final CompiledPrompt prompt;
  final ContextPlan plan;
  final ToolExposure toolExposure;
  final MemorySelection memorySelection;
  final HistorySelection historySelection;
  final WorkflowContext workflowContext;
  final TokenAllocation tokenAllocation;
  final SafetyEnvelope safetyEnvelope;
  final ContextAuditTrace auditTrace;
  final bool compactRequested;
  final bool compactRecommended;
  final ExecutionMode executionMode;
  final bool degraded;
  final String? degradationReason;
}
