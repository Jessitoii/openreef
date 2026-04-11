import 'dart:math' as math;

import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/memory/memory_index.dart';

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
    this.triggerPatterns = const <String>[],
    this.runtimeEligible = true,
  });

  final String id;
  final String displayName;
  final String content;
  final List<String> toolsRequired;
  final List<String> triggerPatterns;
  final bool runtimeEligible;
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

abstract class IntentEmbedder {
  Future<List<double>> embed(String text);
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
    this.compactRequested = false,
    this.recentFiles = const <String>[],
  });

  final List<AgentMessage> messages;
  final IntentSignal intentSignal;
  final List<ToolDefinition> selectedTools;
  final List<SkillDefinition> activeSkills;
  final TokenBudget tokenBudget;
  final bool compactRequested;
  final List<String> recentFiles;

  AssembleResult copyWith({
    List<AgentMessage>? messages,
    IntentSignal? intentSignal,
    List<ToolDefinition>? selectedTools,
    List<SkillDefinition>? activeSkills,
    TokenBudget? tokenBudget,
    bool? compactRequested,
    List<String>? recentFiles,
  }) {
    return AssembleResult(
      messages: messages ?? this.messages,
      intentSignal: intentSignal ?? this.intentSignal,
      selectedTools: selectedTools ?? this.selectedTools,
      activeSkills: activeSkills ?? this.activeSkills,
      tokenBudget: tokenBudget ?? this.tokenBudget,
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

  String toPrompt() => messages.map((message) => message.toPromptSegment()).join('\n');

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
  })  : _memoryIndex = memoryIndex,
        _embedder = embedder,
        _toolCatalog = toolCatalog,
        _skillCatalog = skillCatalog,
        _memoryContextProvider = memoryContextProvider,
        _standingOrderProvider = standingOrderProvider;

  static const int outputReserve = 1024;
  static const int _toolLimit = 8;
  static const int _skillLimit = 2;
  static const int _skillTokenLimit = 150;

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

  Future<AssembleResult> assemble({
    required String sessionKey,
    required String userMessage,
    required List<AgentMessage> conversationHistory,
    required int modelContextWindow,
    bool compactRequested = false,
    List<String> recentFiles = const <String>[],
  }) async {
    final intentSignal = await detectIntent(userMessage);
    final selectedTools = await selectTools(
      userMessage: userMessage,
      intentSignal: intentSignal,
    );
    final activeSkills = gateSkills(userMessage);
    final memoryIndexBlock = await _memoryIndex.toContextBlock();

    final systemMessages = <AgentMessage>[
      const AgentMessage(
        role: AgentMessageRole.system,
        content: 'OpenReef agent core',
        turnNumber: 0,
      ),
      AgentMessage(
        role: AgentMessageRole.system,
        content: memoryIndexBlock,
        turnNumber: 0,
      ),
      AgentMessage(
        role: AgentMessageRole.system,
        content: _serializeTools(selectedTools),
        turnNumber: 0,
      ),
      if (activeSkills.isNotEmpty)
        AgentMessage(
          role: AgentMessageRole.system,
          content: _serializeSkills(activeSkills),
          turnNumber: 0,
        ),
    ];

    final systemUsed = _estimateMessagesTokens(systemMessages);
    final remaining = math.max(0, modelContextWindow - systemUsed - outputReserve);
    final historyBudget = (remaining * 0.6).floor();
    final memoryBudget = (remaining * 0.3).floor();
    final standingOrderBudget = remaining - historyBudget - memoryBudget;

    final boundedHistory = _sliceNewestFirst(
      conversationHistory,
      maxTokens: historyBudget,
    );
    final memoryContext = _sliceNewestFirst(
      await _memoryContextProvider.retrieveRelevantMemories(
        userMessage: userMessage,
        intentSignal: intentSignal,
        maxTokens: memoryBudget,
      ),
      maxTokens: memoryBudget,
    );
    final standingOrders = _sliceNewestFirst(
      await _standingOrderProvider.loadStandingOrders(
        sessionKey: sessionKey,
        maxTokens: standingOrderBudget,
      ),
      maxTokens: standingOrderBudget,
    );

    final messages = <AgentMessage>[
      ...systemMessages,
      ...standingOrders,
      ...memoryContext,
      ...boundedHistory,
      AgentMessage(
        role: AgentMessageRole.user,
        content: userMessage,
        turnNumber: _inferNextTurnNumber(conversationHistory),
      ),
    ];

    final assembled = AssembleResult(
      messages: messages,
      intentSignal: intentSignal,
      selectedTools: selectedTools,
      activeSkills: activeSkills,
      recentFiles: recentFiles,
      compactRequested: compactRequested,
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

    return assembled.copyWith(
      tokenBudget: estimateTokens(
        assembled,
        totalBudget: modelContextWindow,
        historyBudget: historyBudget,
        memoryBudget: memoryBudget,
        standingOrderBudget: standingOrderBudget,
      ),
    );
  }

  Future<IntentSignal> detectIntent(String userMessage) async {
    final embedding = await _embedder.embed(userMessage);
    final scored = _intentCentroids.entries
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
    final embedding = await _embedder.embed(userMessage);
    final enabledTools = _toolCatalog
        .listTools()
        .where((tool) => tool.enabled)
        .toList(growable: false);

    final scored = enabledTools
        .map(
          (tool) => MapEntry<ToolDefinition, double>(
            tool,
            _cosineSimilarity(embedding, tool.embedding),
          ),
        )
        .toList()
      ..sort((left, right) => right.value.compareTo(left.value));

    final selected = <ToolDefinition>[];
    final seen = <String>{};

    void addToolById(String id) {
      final tool = _toolCatalog.byId(id);
      if (tool == null || !tool.enabled || seen.contains(tool.id)) {
        return;
      }
      selected.add(tool);
      seen.add(tool.id);
    }

    addToolById('session_status');
    addToolById('memory_save');
    addToolById('memory_search');
    addToolById('notify');
    addToolById('settings_read');

    for (final entry in scored) {
      if (selected.length >= _toolLimit) {
        break;
      }
      if (seen.add(entry.key.id)) {
        selected.add(entry.key);
      }
    }

    if (intentSignal.primary == 'calendar') {
      addToolById('trigger_create');
      addToolById('trigger_list');
      addToolById('alarm_set');
      addToolById('cron_add');
    }

    if (intentSignal.primary == 'code') {
      addToolById('file_read');
      addToolById('file_write');
    }

    if (selected.any((tool) => tool.requiresConfirmation)) {
      addToolById('user_confirm');
    }

    return selected.take(_toolLimit).toList(growable: false);
  }

  List<SkillDefinition> gateSkills(String userMessage) {
    final normalizedTokens = _normalizeTokens(userMessage);
    final matched = <SkillDefinition>[];
    final active = <SkillDefinition>[];
    for (final skill in _skillCatalog.listSkills()) {
      if (!skill.runtimeEligible) {
        continue;
      }
      final hasMatch = skill.triggerPatterns.any(
        (pattern) => _matchesPattern(
          normalizedTokens,
          _normalizeTokens(pattern),
        ),
      );
      if (!hasMatch) {
        continue;
      }
      matched.add(skill);
      if (active.length >= _skillLimit) {
        continue;
      }
      active.add(
        SkillDefinition(
          id: skill.id,
          displayName: skill.displayName,
          content: _trimToTokens(skill.content, _skillTokenLimit),
          toolsRequired: skill.toolsRequired,
          triggerPatterns: skill.triggerPatterns,
          runtimeEligible: skill.runtimeEligible,
        ),
      );
    }
    _skillCatalog.recordTurnState(
      matchedSkillIds: matched.map((skill) => skill.id).toList(growable: false),
      activeSkillIds: active.map((skill) => skill.id).toList(growable: false),
    );
    return active;
  }

  TokenBudget estimateTokens(
    AssembleResult context, {
    int totalBudget = 8192,
    int? historyBudget,
    int? memoryBudget,
    int? standingOrderBudget,
  }) {
    final estimatedTokens = _estimateMessagesTokens(context.messages);
    final remaining = math.max(0, totalBudget - estimatedTokens - outputReserve);
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
      standingOrderBudget: standingOrderBudget ??
          (remaining - (remaining * 0.6).floor() - (remaining * 0.3).floor()),
      outputReserve: outputReserve,
    );
  }

  List<AgentMessage> _sliceNewestFirst(
    List<AgentMessage> source, {
    required int maxTokens,
  }) {
    final selected = <AgentMessage>[];
    var used = 0;
    for (final message in source.reversed) {
      final messageTokens = _estimateTextTokens(message.content);
      if (used + messageTokens > maxTokens) {
        continue;
      }
      used += messageTokens;
      selected.add(message);
    }
    return selected.reversed.toList(growable: false);
  }

  String _serializeTools(List<ToolDefinition> tools) {
    final buffer = StringBuffer('[AVAILABLE TOOLS]\n');
    for (final tool in tools) {
      final suffix = tool.description.trim().isEmpty ? '' : ': ${tool.description.trim()}';
      buffer.writeln(
        '- ${tool.id}${tool.requiresConfirmation ? ' (confirm)' : ''}$suffix',
      );
    }
    buffer.write('[END TOOLS]');
    return buffer.toString();
  }

  String _serializeSkills(List<SkillDefinition> skills) {
    final buffer = StringBuffer('[ACTIVE SKILLS]\n');
    for (final skill in skills) {
      buffer.writeln('## ${skill.displayName}');
      buffer.writeln(skill.content);
    }
    buffer.write('[END SKILLS]');
    return buffer.toString();
  }

  static List<String> _normalizeTokens(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  static bool _matchesPattern(
    List<String> userTokens,
    List<String> patternTokens,
  ) {
    if (userTokens.isEmpty || patternTokens.isEmpty) {
      return false;
    }
    if (patternTokens.length > userTokens.length) {
      return false;
    }

    for (var start = 0; start <= userTokens.length - patternTokens.length; start++) {
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

  static int _estimateMessagesTokens(List<AgentMessage> messages) {
    return messages.fold<int>(
      0,
      (sum, message) => sum + _estimateTextTokens(message.content),
    );
  }

  static int _estimateTextTokens(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return 0;
    }
    return normalized.split(RegExp(r'\s+')).length;
  }

  static String _trimToTokens(String content, int maxTokens) {
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
