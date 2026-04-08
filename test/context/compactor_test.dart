import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/compactor.dart';
import 'package:openreef/context/context_assembler.dart';

void main() {
  test('micro compaction prunes old tool results and tool errors only', () {
    final compactor = ReefCompactor(
      summarizer: _StaticSummarizer('summary'),
    );
    final context = _contextWithMessages(<AgentMessage>[
      const AgentMessage(
        role: AgentMessageRole.tool,
        content: 'old tool result payload',
        turnNumber: 1,
      ),
      const AgentMessage(
        role: AgentMessageRole.toolError,
        content: 'old tool error payload',
        turnNumber: 1,
      ),
      const AgentMessage(
        role: AgentMessageRole.assistant,
        content: 'assistant text',
        turnNumber: 1,
      ),
      const AgentMessage(
        role: AgentMessageRole.assistant,
        content: 'latest assistant text',
        turnNumber: 8,
      ),
    ]);

    final compacted = compactor.microCompact(context);

    expect(compacted.messages[0].content, '[tool result pruned]');
    expect(compacted.messages[1].content, '[tool error pruned]');
    expect(compacted.messages[2].content, 'assistant text');
  });

  test('auto compaction falls back to deterministic summary on summarizer failure', () async {
    final compactor = ReefCompactor(
      summarizer: _ThrowingSummarizer(),
    );
    final compacted = await compactor.autoCompact(
      _contextWithMessages(_buildTurns(10)),
      reserveTokens: 2000,
      maxSummaryTokens: 8,
    );

    final summaryMessage = compacted.messages.first;
    expect(summaryMessage.role, AgentMessageRole.summary);
    expect(summaryMessage.metadata['compaction_level'], 'auto');
    expect(summaryMessage.content, contains('[COMPACT SUMMARY]'));
    expect(summaryMessage.content, contains('[assistant]'));
  });

  test('full compaction falls back to deterministic summary and preserves reinjected context', () async {
    final compactor = ReefCompactor(
      summarizer: _EmptySummarizer(),
    );
    final context = _contextWithMessages(
      _buildTurns(6),
      recentFiles: const <String>['lib/agent/agent_loop.dart'],
      activeSkills: const <SkillDefinition>[
        SkillDefinition(
          id: 'skill-1',
          displayName: 'skill-1',
          content: 'skill content',
          toolsRequired: <String>[],
        ),
      ],
      compactRequested: true,
    );

    final compacted = await compactor.fullCompact(
      context,
      reInjectRecentFiles: true,
      reInjectActiveSkills: true,
    );

    expect(compacted.compactRequested, isFalse);
    expect(compacted.messages.first.content, contains('[ACTIVE SKILLS]'));
    expect(compacted.messages[1].content, contains('[RECENT FILES]'));
    expect(compacted.messages[2].role, AgentMessageRole.summary);
    expect(compacted.messages[2].metadata['compaction_level'], 'full');
    expect(compacted.messages[2].content, contains('[assistant]'));
  });
}

AssembleResult _contextWithMessages(
  List<AgentMessage> messages, {
  List<String> recentFiles = const <String>[],
  List<SkillDefinition> activeSkills = const <SkillDefinition>[],
  bool compactRequested = false,
}) {
  return AssembleResult(
    messages: messages,
    intentSignal: const IntentSignal(
      primary: 'general',
      secondary: 'general',
      confidence: 1,
    ),
    selectedTools: const <ToolDefinition>[],
    activeSkills: activeSkills,
    tokenBudget: const TokenBudget(
      totalBudget: 8192,
      estimatedTokens: 1000,
      remaining: 7000,
      ratio: 0.2,
      oldToolResults: 1,
      historyBudget: 2000,
      memoryBudget: 1000,
      standingOrderBudget: 500,
      outputReserve: 32,
    ),
    compactRequested: compactRequested,
    recentFiles: recentFiles,
  );
}

List<AgentMessage> _buildTurns(int turnCount) {
  return List<AgentMessage>.generate(
    turnCount,
    (index) => AgentMessage(
      role: AgentMessageRole.assistant,
      content: 'assistant message ${index + 1}',
      turnNumber: index + 1,
    ),
    growable: false,
  );
}

class _StaticSummarizer implements CompactionSummarizer {
  const _StaticSummarizer(this.summary);

  final String summary;

  @override
  Future<String> summarize(
    List<AgentMessage> messages, {
    required int maxTokens,
  }) async {
    return summary;
  }
}

class _ThrowingSummarizer implements CompactionSummarizer {
  @override
  Future<String> summarize(
    List<AgentMessage> messages, {
    required int maxTokens,
  }) async {
    throw StateError('summary failed');
  }
}

class _EmptySummarizer implements CompactionSummarizer {
  @override
  Future<String> summarize(
    List<AgentMessage> messages, {
    required int maxTokens,
  }) async {
    return '   ';
  }
}
