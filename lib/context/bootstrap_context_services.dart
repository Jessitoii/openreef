import 'dart:math' as math;

import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/context/compactor.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/models/litert_bridge.dart';

class LexicalIntentEmbedder implements IntentEmbedder {
  const LexicalIntentEmbedder();

  static const List<String> _domains = <String>[
    'calendar',
    'email',
    'health',
    'research',
    'system',
    'memory',
    'code',
  ];

  static const Map<String, List<String>> _domainLexicon =
      <String, List<String>>{
        'calendar': <String>[
          'agenda',
          'appointment',
          'calendar',
          'date',
          'event',
          'meeting',
          'plan',
          'reminder',
          'schedule',
          'tomorrow',
        ],
        'email': <String>[
          'draft',
          'email',
          'inbox',
          'mail',
          'message',
          'reply',
          'send',
          'subject',
          'thread',
        ],
        'health': <String>[
          'exercise',
          'health',
          'hydration',
          'medication',
          'pill',
          'sleep',
          'steps',
          'symptom',
          'water',
          'workout',
        ],
        'research': <String>[
          'analyze',
          'compare',
          'find',
          'investigate',
          'lookup',
          'news',
          'research',
          'search',
          'summarize',
          'what',
        ],
        'system': <String>[
          'battery',
          'brightness',
          'clipboard',
          'device',
          'open',
          'phone',
          'settings',
          'system',
          'volume',
          'wifi',
        ],
        'memory': <String>[
          'forget',
          'memory',
          'note',
          'recall',
          'remember',
          'saved',
          'stored',
        ],
        'code': <String>[
          'bug',
          'code',
          'dart',
          'error',
          'fix',
          'flutter',
          'issue',
          'test',
          'trace',
        ],
      };

  @override
  Future<List<double>> embed(String text) async {
    final tokens = _tokenize(text);
    final embedding = List<double>.filled(_domains.length, 0);

    for (var index = 0; index < _domains.length; index++) {
      final domain = _domains[index];
      final lexicon = _domainLexicon[domain]!;
      var score = 0.0;
      for (final token in tokens) {
        for (final candidate in lexicon) {
          if (token == candidate) {
            score += 1.5;
            continue;
          }
          if (token.startsWith(candidate) ||
              candidate.startsWith(token) ||
              _normalizedStem(token) == _normalizedStem(candidate)) {
            score += 0.6;
          }
        }
      }
      embedding[index] = score == 0 ? 0.15 : score;
    }

    final magnitude = math.sqrt(
      embedding.fold<double>(0, (sum, value) => sum + (value * value)),
    );
    if (magnitude == 0) {
      return embedding;
    }

    return embedding.map((value) => value / magnitude).toList(growable: false);
  }

  static List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .map(_normalizedStem)
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  static String _normalizedStem(String token) {
    var normalized = token.trim();
    for (final suffix in const <String>['ing', 'ers', 'ies', 'ed', 'es', 's']) {
      if (normalized.length > suffix.length + 2 &&
          normalized.endsWith(suffix)) {
        normalized = normalized.substring(0, normalized.length - suffix.length);
        break;
      }
    }
    return normalized;
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

class LiteRtCompactionSummarizer implements CompactionSummarizer {
  LiteRtCompactionSummarizer({required LiteRtBridge bridge}) : _bridge = bridge;

  static const int _maxMessagesInPrompt = 20;
  static const int _maxSummaryTokens = 256;

  final LiteRtBridge _bridge;

  @override
  Future<String> summarize(
    List<AgentMessage> messages, {
    required int maxTokens,
  }) async {
    if (messages.isEmpty || maxTokens <= 0) {
      return '';
    }

    final visibleMessages = messages.length > _maxMessagesInPrompt
        ? messages.sublist(messages.length - _maxMessagesInPrompt)
        : messages;
    final prompt = StringBuffer()
      ..writeln(
        'Summarize this OpenReef conversation history for context compaction.',
      )
      ..writeln(
        'Preserve user goals, constraints, decisions, completed tool results, failures, and unresolved asks.',
      )
      ..writeln('Return plain text only.')
      ..writeln();
    for (final message in visibleMessages) {
      final prefix = switch (message.role) {
        AgentMessageRole.user => 'USER',
        AgentMessageRole.assistant => 'ASSISTANT',
        AgentMessageRole.tool => 'TOOL_RESULT',
        AgentMessageRole.toolError => 'TOOL_ERROR',
        AgentMessageRole.summary => 'SUMMARY',
        AgentMessageRole.system => 'SYSTEM',
        AgentMessageRole.standingOrder => 'STANDING_ORDER',
        AgentMessageRole.memory => 'MEMORY',
      };
      prompt.writeln('[$prefix] ${message.content}');
    }

    final buffer = StringBuffer();
    await for (final event in _bridge.generateStream(
      context: prompt.toString(),
      maxTokens: math.min(maxTokens, _maxSummaryTokens),
    )) {
      if (event.isFinished) {
        break;
      }
      buffer.write(event.chunk);
    }

    return buffer.toString().trim();
  }
}
