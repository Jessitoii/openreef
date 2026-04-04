import 'dart:math' as math;

import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/context/compactor.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';

class KeywordIntentEmbedder implements IntentEmbedder {
  const KeywordIntentEmbedder();

  static const List<String> _domains = <String>[
    'calendar',
    'email',
    'health',
    'research',
    'system',
    'memory',
    'code',
  ];

  static const Map<String, List<String>> _keywords = <String, List<String>>{
    'calendar': <String>['calendar', 'schedule', 'meeting', 'event'],
    'email': <String>['email', 'mail', 'inbox', 'reply'],
    'health': <String>['health', 'sleep', 'steps', 'workout'],
    'research': <String>['research', 'summarize', 'analyze', 'investigate'],
    'system': <String>['battery', 'volume', 'clipboard', 'device', 'system'],
    'memory': <String>['remember', 'memory', 'recall', 'note'],
    'code': <String>['code', 'bug', 'flutter', 'dart', 'test'],
  };

  @override
  Future<List<double>> embed(String text) async {
    final lowered = text.toLowerCase();
    final embedding = List<double>.filled(_domains.length, 0);

    for (var index = 0; index < _domains.length; index++) {
      final domain = _domains[index];
      final matches = _keywords[domain]!
          .where((keyword) => lowered.contains(keyword))
          .length;
      embedding[index] = matches == 0 ? 0.1 : matches.toDouble();
    }

    final magnitude = math.sqrt(
      embedding.fold<double>(0, (sum, value) => sum + (value * value)),
    );
    if (magnitude == 0) {
      return embedding;
    }

    return embedding.map((value) => value / magnitude).toList(growable: false);
  }
}

class MemoryStorageContextProvider implements MemoryContextProvider {
  const MemoryStorageContextProvider(this._storage);

  static const int _maxRecords = 6;

  final MemoryStorage _storage;

  @override
  Future<List<AgentMessage>> retrieveRelevantMemories({
    required String userMessage,
    required IntentSignal intentSignal,
    required int maxTokens,
  }) async {
    if (maxTokens <= 0) {
      return const <AgentMessage>[];
    }

    final queryTokens = userMessage
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toSet();

    final records = await _storage.readRecords();
    final scoredRecords =
        records
            .map(
              (record) =>
                  (record: record, score: _scoreRecord(record, queryTokens)),
            )
            .where((entry) => entry.score > 0)
            .toList()
          ..sort((left, right) {
            final scoreCompare = right.score.compareTo(left.score);
            if (scoreCompare != 0) {
              return scoreCompare;
            }
            return right.record.createdAt.compareTo(left.record.createdAt);
          });

    final selected = <AgentMessage>[];
    var usedTokens = 0;
    for (final entry in scoredRecords.take(_maxRecords)) {
      final message = AgentMessage(
        role: AgentMessageRole.memory,
        content: _formatRecord(entry.record),
        turnNumber: 0,
        metadata: <String, Object?>{
          'memory_key': entry.record.key,
          'category': entry.record.category,
        },
      );
      final estimatedTokens = message.content
          .trim()
          .split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty)
          .length;
      if (usedTokens + estimatedTokens > maxTokens) {
        continue;
      }
      usedTokens += estimatedTokens;
      selected.add(message);
    }

    return selected;
  }

  int _scoreRecord(MemoryRecord record, Set<String> queryTokens) {
    final content = '${record.category} ${record.content}'.toLowerCase();
    final tokenMatches = queryTokens.where(content.contains).length;
    return (record.importance * 2) + tokenMatches;
  }

  String _formatRecord(MemoryRecord record) {
    return '[${record.category}] ${record.content}';
  }
}

class InlineCompactionSummarizer implements CompactionSummarizer {
  const InlineCompactionSummarizer();

  @override
  Future<String> summarize(
    List<AgentMessage> messages, {
    required int maxTokens,
  }) async {
    if (messages.isEmpty || maxTokens <= 0) {
      return '';
    }

    final tokens = <String>[];
    for (final message in messages) {
      final prefix = switch (message.role) {
        AgentMessageRole.user => 'USER:',
        AgentMessageRole.assistant => 'ASSISTANT:',
        AgentMessageRole.tool => 'TOOL:',
        AgentMessageRole.toolError => 'TOOL_ERROR:',
        AgentMessageRole.summary => 'SUMMARY:',
        AgentMessageRole.system => 'SYSTEM:',
        AgentMessageRole.standingOrder => 'ORDER:',
        AgentMessageRole.memory => 'MEMORY:',
      };
      for (final token in '$prefix ${message.content}'.split(RegExp(r'\s+'))) {
        if (token.isEmpty) {
          continue;
        }
        if (tokens.length >= maxTokens) {
          return tokens.join(' ');
        }
        tokens.add(token);
      }
    }

    return tokens.join(' ');
  }
}
