import 'dart:convert';

import 'package:openreef/agent/agent_model_adapter.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_fact.dart';

class CompletedTurnSnapshot {
  const CompletedTurnSnapshot({
    required this.sessionKey,
    required this.userMessage,
    required this.assistantMessage,
    required this.toolOutputs,
    required this.occurredAt,
  });

  final String sessionKey;
  final String userMessage;
  final String assistantMessage;
  final List<AgentMessage> toolOutputs;
  final DateTime occurredAt;
}

class MemoryFormationResult {
  const MemoryFormationResult({required this.facts, required this.isAmbiguous});

  final List<MemoryFact> facts;
  final bool isAmbiguous;
}

abstract class MemoryFormationService {
  Future<MemoryFormationResult> extract(CompletedTurnSnapshot turn);
}

class ModelBackedMemoryFormationService implements MemoryFormationService {
  ModelBackedMemoryFormationService({required AgentModelAdapter modelAdapter})
    : _modelAdapter = modelAdapter;

  final AgentModelAdapter _modelAdapter;

  @override
  Future<MemoryFormationResult> extract(CompletedTurnSnapshot turn) async {
    final context = AssembleResult(
      messages: <AgentMessage>[
        const AgentMessage(
          role: AgentMessageRole.system,
          content:
              'Extract stable memory facts from the completed assistant turn. '
              'Return only JSON with shape '
              '{"ambiguous":bool,"facts":[{"fact":string,"category":string,"importance":1-5}]}. '
              'Categories: preference, person, event, decision, fact, task, health. '
              'If nothing durable should be saved, return {"ambiguous":false,"facts":[]}. '
              'If the turn is uncertain, speculative, or unresolved, return {"ambiguous":true,"facts":[]}. '
              'Do not call tools.',
          turnNumber: 0,
        ),
        AgentMessage(
          role: AgentMessageRole.user,
          content: _buildPrompt(turn),
          turnNumber: 1,
        ),
      ],
      intentSignal: const IntentSignal(
        primary: 'memory',
        secondary: 'general',
        confidence: 1,
      ),
      selectedTools: const <ToolDefinition>[],
      activeSkills: const <SkillDefinition>[],
      tokenBudget: const TokenBudget(
        totalBudget: 1024,
        estimatedTokens: 0,
        remaining: 1024,
        ratio: 0,
        oldToolResults: 0,
        historyBudget: 0,
        memoryBudget: 0,
        standingOrderBudget: 0,
        outputReserve: 256,
      ),
    );

    final response = await _modelAdapter.generate(context, maxTokens: 512);
    final decoded = _decodeResponse(response.rawOutput ?? response.text);
    final facts = _parseFacts(decoded['facts'], turn);
    final ambiguous = decoded['ambiguous'] == true;
    return MemoryFormationResult(facts: facts, isAmbiguous: ambiguous);
  }

  String _buildPrompt(CompletedTurnSnapshot turn) {
    final toolLines = turn.toolOutputs
        .map((message) => '[${message.role.name}] ${message.content}')
        .join('\n');
    return '''
SESSION: ${turn.sessionKey}
TIME: ${turn.occurredAt.toUtc().toIso8601String()}
USER:
${turn.userMessage}

ASSISTANT:
${turn.assistantMessage}

TOOL OUTPUTS:
$toolLines
'''
        .trim();
  }

  Map<String, Object?> _decodeResponse(String raw) {
    final trimmed = raw.trim();
    final direct = _tryDecodeMap(trimmed);
    if (direct != null) {
      return direct;
    }
    throw const FormatException('memory_extraction_invalid_json');
  }

  Map<String, Object?>? _tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  List<MemoryFact> _parseFacts(Object? rawFacts, CompletedTurnSnapshot turn) {
    if (rawFacts is! List) {
      return const <MemoryFact>[];
    }

    final facts = <MemoryFact>[];
    for (var index = 0; index < rawFacts.length; index++) {
      final item = rawFacts[index];
      if (item is! Map) {
        continue;
      }
      final factMap = Map<String, Object?>.from(item);
      final factText = (factMap['fact'] as String? ?? '').trim();
      if (factText.isEmpty) {
        continue;
      }
      final category = (factMap['category'] as String? ?? 'fact').trim();
      final importance = ((factMap['importance'] as num?)?.toInt() ?? 1).clamp(
        1,
        5,
      );
      facts.add(
        MemoryFact(
          key: _buildKey(turn, category, index),
          fact: factText,
          category: category.isEmpty ? 'fact' : category,
          importance: importance,
          metadata: <String, Object?>{
            'session_key': turn.sessionKey,
            'source': 'after_turn',
          },
        ),
      );
    }
    return List<MemoryFact>.unmodifiable(facts);
  }

  String _buildKey(CompletedTurnSnapshot turn, String category, int index) {
    final sanitizedCategory = category
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    final stamp = turn.occurredAt.toUtc().microsecondsSinceEpoch;
    return '${turn.sessionKey}_${sanitizedCategory}_${stamp}_$index';
  }
}
