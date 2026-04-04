import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/context/context_assembler.dart';

abstract class CompactionSummarizer {
  Future<String> summarize(
    List<AgentMessage> messages, {
    required int maxTokens,
  });
}

class ReefCompactor {
  const ReefCompactor({
    required CompactionSummarizer summarizer,
  }) : _summarizer = summarizer;

  final CompactionSummarizer _summarizer;

  AssembleResult microCompact(AssembleResult context) {
    final currentTurn = context.messages.fold<int>(
      0,
      (current, message) => (message.turnNumber ?? 0) > current
          ? message.turnNumber!
          : current,
    );
    final messages = context.messages.map((message) {
      if (!message.isToolResult) {
        return message;
      }

      final turnNumber = message.turnNumber ?? currentTurn;
      if (currentTurn - turnNumber > 5) {
        return message.copyWith(content: '[tool result pruned]');
      }
      return message;
    }).toList(growable: false);

    return context.copyWith(messages: messages);
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

    final summary = await _summarizer.summarize(
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
          },
        ),
        ...split.recentMessages,
      ],
    );
  }

  Future<AssembleResult> fullCompact(
    AssembleResult context, {
    bool reInjectRecentFiles = false,
    bool reInjectActiveSkills = false,
  }) async {
    final split = _splitHistory(context.messages, keepRecentTurns: 4);
    final summary = await _summarizer.summarize(
      split.oldMessages.isEmpty ? context.messages : split.oldMessages,
      maxTokens: context.tokenBudget.outputReserve,
    );

    final rebuiltMessages = <AgentMessage>[
      AgentMessage(
        role: AgentMessageRole.summary,
        content: '[COMPACT SUMMARY]\n$summary\n[END COMPACT]',
        turnNumber: split.summaryTurnNumber,
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
    );
  }

  _HistorySplit _splitHistory(
    List<AgentMessage> messages, {
    required int keepRecentTurns,
  }) {
    final turnNumbers = messages
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

    final preservedTurns = turnNumbers.sublist(turnNumbers.length - keepRecentTurns);
    final preservedSet = preservedTurns.toSet();
    final oldMessages = <AgentMessage>[];
    final recentMessages = <AgentMessage>[];
    for (final message in messages) {
      final turnNumber = message.turnNumber;
      if (turnNumber != null && preservedSet.contains(turnNumber)) {
        recentMessages.add(message);
      } else if (turnNumber == null && message.role == AgentMessageRole.system) {
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
