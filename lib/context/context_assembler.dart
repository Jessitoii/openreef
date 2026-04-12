import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/capability_retrieval.dart';
import 'package:openreef/context/compiled_context_package.dart';
import 'package:openreef/context/context_audit.dart';
import 'package:openreef/context/context_planner.dart';
import 'package:openreef/context/context_reducer.dart';
import 'package:openreef/context/context_renderer.dart';
import 'package:openreef/context/context_retriever.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/models/embedding_model_manager.dart';
import 'package:openreef/skills/skill.dart';

class IntentSignal {
  const IntentSignal({
    required this.primary,
    required this.secondary,
    required this.confidence,
  });

  final String primary;
  final String secondary;
  final double confidence;
}

class TokenBudget {
  const TokenBudget({
    required this.totalBudget,
    required this.estimatedTokens,
    required this.remaining,
    required this.ratio,
    required this.oldToolResults,
    required this.historyBudget,
    required this.memoryBudget,
    required this.standingOrderBudget,
    required this.outputReserve,
  });

  final int totalBudget;
  final int estimatedTokens;
  final int remaining;
  final double ratio;
  final int oldToolResults;
  final int historyBudget;
  final int memoryBudget;
  final int standingOrderBudget;
  final int outputReserve;
}

class SkillDefinition {
  const SkillDefinition({
    required this.id,
    required this.displayName,
    required this.content,
    required this.toolsRequired,
    this.description = '',
    this.triggerPatterns = const <String>[],
    this.runtimeEligible = true,
    this.priority = 0,
    this.maxTokens = 150,
    this.allowedModes = const <ExecutionMode>{},
    this.incompatibleSkillIds = const <String>[],
    this.activationTerms = const <String>[],
    this.sourceType = SkillSourceType.user,
  });

  final String id;
  final String displayName;
  final String content;
  final List<String> toolsRequired;
  final String description;
  final List<String> triggerPatterns;
  final bool runtimeEligible;
  final int priority;
  final int maxTokens;
  final Set<ExecutionMode> allowedModes;
  final List<String> incompatibleSkillIds;
  final List<String> activationTerms;
  final SkillSourceType sourceType;

  SkillDefinition copyWith({
    String? id,
    String? displayName,
    String? content,
    List<String>? toolsRequired,
    String? description,
    List<String>? triggerPatterns,
    bool? runtimeEligible,
    int? priority,
    int? maxTokens,
    Set<ExecutionMode>? allowedModes,
    List<String>? incompatibleSkillIds,
    List<String>? activationTerms,
    SkillSourceType? sourceType,
  }) {
    return SkillDefinition(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      content: content ?? this.content,
      toolsRequired: toolsRequired ?? this.toolsRequired,
      description: description ?? this.description,
      triggerPatterns: triggerPatterns ?? this.triggerPatterns,
      runtimeEligible: runtimeEligible ?? this.runtimeEligible,
      priority: priority ?? this.priority,
      maxTokens: maxTokens ?? this.maxTokens,
      allowedModes: allowedModes ?? this.allowedModes,
      incompatibleSkillIds: incompatibleSkillIds ?? this.incompatibleSkillIds,
      activationTerms: activationTerms ?? this.activationTerms,
      sourceType: sourceType ?? this.sourceType,
    );
  }
}

abstract class SkillCatalog {
  List<SkillDefinition> listSkills();

  void recordTurnState({
    required List<String> matchedSkillIds,
    required List<String> activeSkillIds,
  }) {}
}

class InMemorySkillCatalog implements SkillCatalog {
  InMemorySkillCatalog(this._skills);

  final List<SkillDefinition> _skills;

  @override
  List<SkillDefinition> listSkills() =>
      List<SkillDefinition>.unmodifiable(_skills);

  @override
  void recordTurnState({
    required List<String> matchedSkillIds,
    required List<String> activeSkillIds,
  }) {}
}

class ContextAssemblyRequest {
  const ContextAssemblyRequest({
    required this.sessionKey,
    required this.userMessage,
    required this.conversationHistory,
    required this.modelContextWindow,
    required this.executionMode,
    this.executionSource = ExecutionSource.user,
    this.executionPolicy,
    this.compactRequested = false,
    this.recentFiles = const <String>[],
    this.workflowContext = const WorkflowContext(),
    this.metadata = const <String, Object?>{},
  });

  final String sessionKey;
  final String userMessage;
  final List<AgentMessage> conversationHistory;
  final int modelContextWindow;
  final ExecutionMode executionMode;
  final ExecutionSource executionSource;
  final ExecutionPolicy? executionPolicy;
  final bool compactRequested;
  final List<String> recentFiles;
  final WorkflowContext workflowContext;
  final Map<String, Object?> metadata;
}

abstract class IntentEmbedder {
  Future<List<double>> embed(String text);
}

class _IntentSemanticTextEmbedder implements SemanticTextEmbedder {
  const _IntentSemanticTextEmbedder(this._embedder);

  final IntentEmbedder _embedder;

  @override
  String get modelId => 'legacy_intent_embedder_compatibility';

  @override
  Future<List<double>> embedDocument(String text) => _embedder.embed(text);

  @override
  Future<List<double>> embedQuery(String text) => _embedder.embed(text);
}

abstract class MemoryContextProvider {
  Future<List<AgentMessage>> retrieveRelevantMemories({
    required String userMessage,
    required IntentSignal intentSignal,
    required int maxTokens,
  });
}

abstract class StandingOrderProvider {
  Future<List<AgentMessage>> loadStandingOrders({
    required String sessionKey,
    required int maxTokens,
  });
}

class EmptyMemoryContextProvider implements MemoryContextProvider {
  const EmptyMemoryContextProvider();

  @override
  Future<List<AgentMessage>> retrieveRelevantMemories({
    required String userMessage,
    required IntentSignal intentSignal,
    required int maxTokens,
  }) async {
    return const <AgentMessage>[];
  }
}

class EmptyStandingOrderProvider implements StandingOrderProvider {
  const EmptyStandingOrderProvider();

  @override
  Future<List<AgentMessage>> loadStandingOrders({
    required String sessionKey,
    required int maxTokens,
  }) async {
    return const <AgentMessage>[];
  }
}

class AssembleResult {
  const AssembleResult({
    required this.messages,
    required this.intentSignal,
    required this.selectedTools,
    required this.activeSkills,
    required this.tokenBudget,
    this.compiledPackage,
    this.compactRequested = false,
    this.recentFiles = const <String>[],
  });

  final List<AgentMessage> messages;
  final IntentSignal intentSignal;
  final List<ToolDefinition> selectedTools;
  final List<SkillDefinition> activeSkills;
  final TokenBudget tokenBudget;
  final CompiledContextPackage? compiledPackage;
  final bool compactRequested;
  final List<String> recentFiles;

  AssembleResult copyWith({
    List<AgentMessage>? messages,
    IntentSignal? intentSignal,
    List<ToolDefinition>? selectedTools,
    List<SkillDefinition>? activeSkills,
    TokenBudget? tokenBudget,
    CompiledContextPackage? compiledPackage,
    bool clearCompiledPackage = false,
    bool? compactRequested,
    List<String>? recentFiles,
  }) {
    return AssembleResult(
      messages: messages ?? this.messages,
      intentSignal: intentSignal ?? this.intentSignal,
      selectedTools: selectedTools ?? this.selectedTools,
      activeSkills: activeSkills ?? this.activeSkills,
      tokenBudget: tokenBudget ?? this.tokenBudget,
      compiledPackage: clearCompiledPackage
          ? null
          : compiledPackage ?? this.compiledPackage,
      compactRequested: compactRequested ?? this.compactRequested,
      recentFiles: recentFiles ?? this.recentFiles,
    );
  }

  AssembleResult appendToolResult(String toolCallId, ToolResult result) {
    final nextMessages = List<AgentMessage>.from(messages)
      ..add(
        AgentMessage(
          role: AgentMessageRole.tool,
          content: result.toContextString(),
          toolCallId: toolCallId,
          turnNumber: _nextTurnNumber(messages),
          metadata: result.toMap(),
        ),
      );
    return copyWith(messages: nextMessages);
  }

  AssembleResult appendToolError(String toolCallId, Object error) {
    final nextMessages = List<AgentMessage>.from(messages)
      ..add(
        AgentMessage(
          role: AgentMessageRole.toolError,
          content: error.toString(),
          toolCallId: toolCallId,
          turnNumber: _nextTurnNumber(messages),
        ),
      );
    return copyWith(messages: nextMessages);
  }

  String toPrompt() =>
      messages.map((message) => message.toPromptSegment()).join('\n');

  static int _nextTurnNumber(List<AgentMessage> messages) {
    final maxTurn = messages.fold<int>(
      0,
      (current, message) => math.max(current, message.turnNumber ?? 0),
    );
    return maxTurn + 1;
  }
}

class ContextAssembler {
  ContextAssembler({
    required MemoryIndex memoryIndex,
    required IntentEmbedder embedder,
    required ToolCatalog toolCatalog,
    required SkillCatalog skillCatalog,
    MemoryContextProvider memoryContextProvider =
        const EmptyMemoryContextProvider(),
    StandingOrderProvider standingOrderProvider =
        const EmptyStandingOrderProvider(),
    CapabilityEmbeddingIndex? capabilityIndex,
    CapabilitySelector? capabilitySelector,
    EmbeddingModelReadinessProvider? embeddingReadinessProvider,
  }) : _memoryIndex = memoryIndex,
       _embedder = embedder,
       _toolCatalog = toolCatalog,
       _skillCatalog = skillCatalog,
       _memoryContextProvider = memoryContextProvider,
       _standingOrderProvider = standingOrderProvider,
       _capabilityIndex =
           capabilityIndex ??
           CapabilityEmbeddingIndex(
             embedder: _IntentSemanticTextEmbedder(embedder),
           ),
       _capabilitySelector = capabilitySelector,
       _embeddingReadinessProvider = embeddingReadinessProvider;

  static const int outputReserve = 1024;
  static const int _toolLimit = 8;
  static const int _skillLimit = 2;

  static const Map<String, List<double>> _intentCentroids =
      <String, List<double>>{
        'calendar': <double>[1, 0, 0, 0, 0, 0, 0],
        'email': <double>[0, 1, 0, 0, 0, 0, 0],
        'health': <double>[0, 0, 1, 0, 0, 0, 0],
        'research': <double>[0, 0, 0, 1, 0, 0, 0],
        'system': <double>[0, 0, 0, 0, 1, 0, 0],
        'memory': <double>[0, 0, 0, 0, 0, 1, 0],
        'code': <double>[0, 0, 0, 0, 0, 0, 1],
        'general': <double>[0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
      };

  final MemoryIndex _memoryIndex;
  final IntentEmbedder _embedder;
  final ToolCatalog _toolCatalog;
  final SkillCatalog _skillCatalog;
  final MemoryContextProvider _memoryContextProvider;
  final StandingOrderProvider _standingOrderProvider;
  final CapabilityEmbeddingIndex _capabilityIndex;
  final CapabilitySelector? _capabilitySelector;
  final EmbeddingModelReadinessProvider? _embeddingReadinessProvider;

  Future<AssembleResult> assemble({
    required String sessionKey,
    required String userMessage,
    required List<AgentMessage> conversationHistory,
    required int modelContextWindow,
    bool compactRequested = false,
    List<String> recentFiles = const <String>[],
  }) async {
    final legacyClassification = TurnClassifier().classify(
      userMessage: userMessage,
      conversationHistory: conversationHistory,
      compactRequested: compactRequested,
    );
    return assembleRequest(
      ContextAssemblyRequest(
        sessionKey: sessionKey,
        userMessage: userMessage,
        conversationHistory: conversationHistory,
        modelContextWindow: modelContextWindow,
        executionMode: ExecutionModeResolver().resolve(
          classification: legacyClassification,
          conversationHistory: conversationHistory,
          compactRequested: compactRequested,
        ),
        compactRequested: compactRequested,
        recentFiles: recentFiles,
      ),
    );
  }

  Future<AssembleResult> assembleRequest(ContextAssemblyRequest request) async {
    debugPrint(
      'OpenReef.ContextAssembler: assembleRequest.start session=${request.sessionKey} mode=${request.executionMode.name}',
    );
    final readiness = await _embeddingReadinessProvider?.checkReadiness();
    if (readiness != null && !readiness.isReady) {
      debugPrint(
        'OpenReef.ContextAssembler: embeddingReadiness.blocked status=${readiness.status.name} model=${readiness.model?.id ?? 'none'}',
      );
      throw EmbeddingModelNotReadyException(readiness);
    }
    // ignore: deprecated_member_use_from_same_package
    final intentSignal = await detectIntent(request.userMessage);
    final planner = ContextPlanner(
      toolLimit: _toolLimit,
      skillLimit: _skillLimit,
      outputReserve: outputReserve,
      capabilityIndex: _capabilityIndex,
      selector: _capabilitySelector,
    );
    final plan = await planner.plan(
      userMessage: request.userMessage,
      conversationHistory: request.conversationHistory,
      modelContextWindow: request.modelContextWindow,
      toolCatalog: _toolCatalog,
      skillCatalog: _skillCatalog,
      compactRequested: request.compactRequested,
      executionMode: request.executionMode,
      executionPolicy: request.executionPolicy,
    );
    debugPrint(
      'OpenReef.ContextAssembler: plan.end retrieved=${plan.retrievedCandidates.length} tools=${plan.toolExposure.exposedTools.length} skills=${plan.skillPlan.activeSkills.length}',
    );
    final retrieved =
        await ContextRetriever(
          memoryIndex: _memoryIndex,
          memoryContextProvider: _memoryContextProvider,
          standingOrderProvider: _standingOrderProvider,
        ).retrieve(
          sessionKey: request.sessionKey,
          userMessage: request.userMessage,
          plan: plan,
          intentSignal: intentSignal,
        );
    debugPrint('OpenReef.ContextAssembler: retrieve.end');
    final reduced = const ContextReducer().reduce(
      plan: plan,
      sources: retrieved,
      conversationHistory: request.conversationHistory,
    );
    debugPrint('OpenReef.ContextAssembler: reduce.end');
    final renderer = const ContextRenderer();
    final sections = renderer.renderSections(
      plan: plan,
      sources: reduced,
      userMessage: request.userMessage,
    );
    debugPrint(
      'OpenReef.ContextAssembler: renderSections.end sections=${sections.length}',
    );
    final rendered = renderer.renderWithinBudget(
      sections: sections,
      tokenAllocation: plan.tokenAllocation,
    );
    debugPrint(
      'OpenReef.ContextAssembler: renderBudget.end tokens=${rendered.prompt.estimatedTokens} degraded=${rendered.degraded}',
    );
    final audit = const ContextAudit().build(
      plan: plan,
      sections: rendered.sections,
      reductions: <ContextReduction>[
        ...reduced.reductions,
        ...rendered.reductions,
      ],
      droppedSectionIds: rendered.droppedSectionIds,
      droppedItems: <ContextDroppedItem>[
        ...reduced.droppedItems,
        ...rendered.droppedItems,
      ],
      degraded: rendered.degraded,
      degradationReason: rendered.degradationReason,
    );
    final compactRecommended =
        reduced.compactRecommended || plan.tokenAllocation.compactRecommended;
    final package = CompiledContextPackage(
      prompt: rendered.prompt,
      plan: plan,
      toolExposure: plan.toolExposure,
      memorySelection: MemorySelection(
        memoryIndexBlock: reduced.memoryIndexBlock,
        messages: reduced.memoryMessages,
      ),
      historySelection: reduced.historySelection,
      workflowContext: reduced.workflowContext,
      tokenAllocation: plan.tokenAllocation,
      safetyEnvelope: plan.safetyEnvelope,
      auditTrace: audit,
      compactRequested:
          request.compactRequested || plan.tokenAllocation.compactRequired,
      compactRecommended: compactRecommended,
      executionMode: plan.executionMode,
      degraded: rendered.degraded,
      degradationReason: rendered.degradationReason,
    );

    final messages = rendered.prompt.messages;
    final selectedTools = plan.toolExposure.primaryTools;
    final activeSkills = plan.skillPlan.activeSkills;

    final assembled = AssembleResult(
      messages: messages,
      intentSignal: intentSignal,
      selectedTools: selectedTools,
      activeSkills: activeSkills,
      recentFiles: request.recentFiles,
      compiledPackage: package,
      compactRequested:
          request.compactRequested || plan.tokenAllocation.compactRequired,
      tokenBudget: const TokenBudget(
        totalBudget: 0,
        estimatedTokens: 0,
        remaining: 0,
        ratio: 0,
        oldToolResults: 0,
        historyBudget: 0,
        memoryBudget: 0,
        standingOrderBudget: 0,
        outputReserve: outputReserve,
      ),
    );

    final result = assembled.copyWith(
      tokenBudget: estimateTokens(
        assembled,
        totalBudget: request.modelContextWindow,
        historyBudget: plan.tokenAllocation.sectionBudgets['history'] ?? 0,
        memoryBudget: plan.tokenAllocation.sectionBudgets['memory'] ?? 0,
        standingOrderBudget:
            plan.tokenAllocation.sectionBudgets['standing_orders'] ?? 0,
      ),
    );
    debugPrint('OpenReef.ContextAssembler: assembleRequest.end');
    return result;
  }

  @Deprecated(
    'Legacy memory compatibility only. Context routing uses ContextPlanner.',
  )
  Future<IntentSignal> detectIntent(String userMessage) async {
    final embedding = await _embedder.embed(userMessage);
    final scored =
        _intentCentroids.entries
            .map(
              (entry) => MapEntry<String, double>(
                entry.key,
                _cosineSimilarity(embedding, entry.value),
              ),
            )
            .toList()
          ..sort((left, right) => right.value.compareTo(left.value));

    final primary = scored.first;
    final secondary = scored.length > 1 ? scored[1] : primary;
    return IntentSignal(
      primary: primary.key,
      secondary: secondary.key,
      confidence: primary.value,
    );
  }

  Future<List<ToolDefinition>> selectTools({
    required String userMessage,
    required IntentSignal intentSignal,
  }) async {
    final plan =
        await ContextPlanner(
          toolLimit: _toolLimit,
          skillLimit: _skillLimit,
          outputReserve: outputReserve,
          capabilityIndex: _capabilityIndex,
          selector: _capabilitySelector,
        ).plan(
          userMessage: userMessage,
          conversationHistory: const <AgentMessage>[],
          modelContextWindow: 8192,
          toolCatalog: _toolCatalog,
          skillCatalog: _skillCatalog,
          compactRequested: false,
          executionMode: ExecutionMode.chat,
        );
    return plan.toolExposure.primaryTools;
  }

  Future<List<SkillDefinition>> gateSkills(String userMessage) async {
    final plan =
        await ContextPlanner(
          toolLimit: _toolLimit,
          skillLimit: _skillLimit,
          outputReserve: outputReserve,
          capabilityIndex: _capabilityIndex,
          selector: _capabilitySelector,
        ).plan(
          userMessage: userMessage,
          conversationHistory: const <AgentMessage>[],
          modelContextWindow: 8192,
          toolCatalog: _toolCatalog,
          skillCatalog: _skillCatalog,
          compactRequested: false,
          executionMode: ExecutionMode.chat,
        );
    return plan.skillPlan.activeSkills;
  }

  TokenBudget estimateTokens(
    AssembleResult context, {
    int totalBudget = 8192,
    int? historyBudget,
    int? memoryBudget,
    int? standingOrderBudget,
  }) {
    final estimatedTokens = _estimateMessagesTokens(context.messages);
    final remaining = math.max(
      0,
      totalBudget - estimatedTokens - outputReserve,
    );
    final ratio = totalBudget == 0 ? 0.0 : estimatedTokens / totalBudget;
    final currentTurn = _inferNextTurnNumber(context.messages) - 1;
    final oldToolResults = context.messages
        .where((message) => message.isToolResult)
        .where(
          (message) => currentTurn - (message.turnNumber ?? currentTurn) > 5,
        )
        .length;

    return TokenBudget(
      totalBudget: totalBudget,
      estimatedTokens: estimatedTokens,
      remaining: remaining,
      ratio: ratio,
      oldToolResults: oldToolResults,
      historyBudget: historyBudget ?? (remaining * 0.6).floor(),
      memoryBudget: memoryBudget ?? (remaining * 0.3).floor(),
      standingOrderBudget:
          standingOrderBudget ??
          (remaining - (remaining * 0.6).floor() - (remaining * 0.3).floor()),
      outputReserve: outputReserve,
    );
  }

  static List<String> normalizeTokens(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  static bool matchesPattern(
    List<String> userTokens,
    List<String> patternTokens,
  ) {
    if (userTokens.isEmpty || patternTokens.isEmpty) {
      return false;
    }
    if (patternTokens.length > userTokens.length) {
      return false;
    }

    for (
      var start = 0;
      start <= userTokens.length - patternTokens.length;
      start++
    ) {
      var matched = true;
      for (var offset = 0; offset < patternTokens.length; offset++) {
        if (userTokens[start + offset] != patternTokens[offset]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        return true;
      }
    }
    return false;
  }

  static int estimateMessagesTokens(List<AgentMessage> messages) {
    return messages.fold<int>(
      0,
      (sum, message) => sum + _estimateTextTokens(message.content),
    );
  }

  static int estimateTextTokens(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return 0;
    }
    return normalized.split(RegExp(r'\s+')).length;
  }

  static String trimToTokens(String content, int maxTokens) {
    final normalized = content.trim();
    if (normalized.isEmpty) {
      return '';
    }
    final words = normalized.split(RegExp(r'\s+'));
    if (words.length <= maxTokens) {
      return normalized;
    }
    return words.take(maxTokens).join(' ');
  }

  static int _inferNextTurnNumber(List<AgentMessage> messages) {
    final maxTurn = messages.fold<int>(
      0,
      (current, message) => math.max(current, message.turnNumber ?? 0),
    );
    return maxTurn + 1;
  }

  static int _estimateMessagesTokens(List<AgentMessage> messages) =>
      estimateMessagesTokens(messages);

  static int _estimateTextTokens(String text) => estimateTextTokens(text);

  static double _cosineSimilarity(List<double> left, List<double> right) {
    final length = math.min(left.length, right.length).toInt();
    if (length == 0) {
      return 0;
    }

    var dot = 0.0;
    var leftMagnitude = 0.0;
    var rightMagnitude = 0.0;

    for (var index = 0; index < length; index++) {
      dot += left[index] * right[index];
      leftMagnitude += left[index] * left[index];
      rightMagnitude += right[index] * right[index];
    }

    if (leftMagnitude == 0 || rightMagnitude == 0) {
      return 0;
    }
    return dot / (math.sqrt(leftMagnitude) * math.sqrt(rightMagnitude));
  }
}
