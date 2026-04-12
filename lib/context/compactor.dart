import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/context/context_assembler.dart';

abstract class CompactionSummarizer {
  Future<String> summarize(
    List<AgentMessage> messages, {
    required int maxTokens,
  });
}

class ReefCompactor {
  const ReefCompactor({required CompactionSummarizer summarizer})
    : _summarizer = summarizer;

  static const String _prunedToolResult = '[tool result pruned]';
  static const String _prunedToolError = '[tool error pruned]';
  static const int _fallbackSummaryMessageLimit = 6;

  final CompactionSummarizer _summarizer;

  AssembleResult microCompact(AssembleResult context) {
    final currentTurn = context.messages.fold<int>(
      0,
      (current, message) =>
          (message.turnNumber ?? 0) > current ? message.turnNumber! : current,
    );
    final messages = context.messages
        .map((message) {
          if (!message.isToolResult && !message.isToolError) {
            return message;
          }

          final turnNumber = message.turnNumber ?? currentTurn;
          if (currentTurn - turnNumber > 5) {
            return message.copyWith(
              content: message.isToolError
                  ? _prunedToolError
                  : _prunedToolResult,
            );
          }
          return message;
        })
        .toList(growable: false);

    return context.copyWith(messages: messages, clearCompiledPackage: true);
  }

  Future<AssembleResult> autoCompact(
    AssembleResult context, {
    required int reserveTokens,
    required int maxSummaryTokens,
  }) async {
    final split = _splitHistory(context.messages, keepRecentTurns: 8);
    if (split.oldMessages.isEmpty) {
      return context;
    }

    final summary = await _safeSummarize(
      split.oldMessages,
      maxTokens: maxSummaryTokens,
    );

    return context.copyWith(
      messages: <AgentMessage>[
        AgentMessage(
          role: AgentMessageRole.summary,
          content: '[COMPACT SUMMARY]\n$summary\n[END COMPACT]',
          turnNumber: split.summaryTurnNumber,
          metadata: <String, Object?>{
            'reserve_tokens': reserveTokens,
            'compaction_level': 'auto',
          },
        ),
        ...split.recentMessages,
      ],
      clearCompiledPackage: true,
    );
  }

  Future<AssembleResult> fullCompact(
    AssembleResult context, {
    bool reInjectRecentFiles = false,
    bool reInjectActiveSkills = false,
  }) async {
    final split = _splitHistory(context.messages, keepRecentTurns: 4);
    final messagesToSummarize = split.oldMessages.isEmpty
        ? context.messages
        : split.oldMessages;
    final summary = await _safeSummarize(
      messagesToSummarize,
      maxTokens: context.tokenBudget.outputReserve,
    );

    final rebuiltMessages = <AgentMessage>[
      ..._criticalContextMessages(context),
      AgentMessage(
        role: AgentMessageRole.summary,
        content: '[COMPACT SUMMARY]\n$summary\n[END COMPACT]',
        turnNumber: split.summaryTurnNumber,
        metadata: const <String, Object?>{'compaction_level': 'full'},
      ),
      ...split.recentMessages,
    ];

    if (reInjectRecentFiles && context.recentFiles.isNotEmpty) {
      rebuiltMessages.insert(
        0,
        AgentMessage(
          role: AgentMessageRole.system,
          content:
              '[RECENT FILES]\n${context.recentFiles.join('\n')}\n[END RECENT FILES]',
          turnNumber: 0,
        ),
      );
    }

    if (reInjectActiveSkills && context.activeSkills.isNotEmpty) {
      rebuiltMessages.insert(
        0,
        AgentMessage(
          role: AgentMessageRole.system,
          content:
              '[ACTIVE SKILLS]\n${context.activeSkills.map((skill) => skill.content).join('\n')}\n[END ACTIVE SKILLS]',
          turnNumber: 0,
        ),
      );
    }

    return context.copyWith(
      messages: rebuiltMessages,
      compactRequested: false,
      clearCompiledPackage: true,
    );
  }

  List<AgentMessage> _criticalContextMessages(AssembleResult context) {
    final package = context.compiledPackage;
    if (package == null) {
      return const <AgentMessage>[];
    }
    return package.prompt.sections
        .where(
          (section) =>
              section.critical &&
              section.id != 'user' &&
              section.id != 'execution_mode',
        )
        .map((section) => section.toMessage())
        .toList(growable: false);
  }

  Future<String> _safeSummarize(
    List<AgentMessage> messages, {
    required int maxTokens,
  }) async {
    try {
      final summary = await _summarizer.summarize(
        messages,
        maxTokens: maxTokens,
      );
      final normalized = summary.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    } catch (_) {
      // Fall back to a deterministic inline summary to keep the loop alive.
    }

    return _fallbackSummary(messages, maxTokens: maxTokens);
  }

  String _fallbackSummary(
    List<AgentMessage> messages, {
    required int maxTokens,
  }) {
    final segments = messages
        .take(_fallbackSummaryMessageLimit)
        .map(
          (message) =>
              '[${message.role.name}] ${_truncate(message.content, maxTokens)}',
        )
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);

    if (segments.isEmpty) {
      return '[fallback summary unavailable]';
    }

    return segments.join('\n');
  }

  String _truncate(String content, int maxTokens) {
    final words = content
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    if (words.isEmpty) {
      return '';
    }

    final limit = maxTokens <= 0 ? 1 : maxTokens;
    return words.take(limit).join(' ');
  }

  _HistorySplit _splitHistory(
    List<AgentMessage> messages, {
    required int keepRecentTurns,
  }) {
    final turnNumbers =
        messages
            .map((message) => message.turnNumber)
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();
    if (turnNumbers.length <= keepRecentTurns) {
      return _HistorySplit(
        oldMessages: const <AgentMessage>[],
        recentMessages: messages,
        summaryTurnNumber: turnNumbers.isEmpty ? 0 : turnNumbers.first,
      );
    }

    final preservedTurns = turnNumbers.sublist(
      turnNumbers.length - keepRecentTurns,
    );
    final preservedSet = preservedTurns.toSet();
    final oldMessages = <AgentMessage>[];
    final recentMessages = <AgentMessage>[];
    for (final message in messages) {
      final turnNumber = message.turnNumber;
      if (turnNumber != null && preservedSet.contains(turnNumber)) {
        recentMessages.add(message);
      } else if (turnNumber == null &&
          message.role == AgentMessageRole.system) {
        recentMessages.add(message);
      } else {
        oldMessages.add(message);
      }
    }

    return _HistorySplit(
      oldMessages: oldMessages,
      recentMessages: recentMessages,
      summaryTurnNumber: preservedTurns.first,
    );
  }
}

class _HistorySplit {
  const _HistorySplit({
    required this.oldMessages,
    required this.recentMessages,
    required this.summaryTurnNumber,
  });

  final List<AgentMessage> oldMessages;
  final List<AgentMessage> recentMessages;
  final int summaryTurnNumber;
}
