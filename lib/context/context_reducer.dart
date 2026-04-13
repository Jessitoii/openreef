import 'dart:math' as math;

import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/context/compiled_context_package.dart';
import 'package:openreef/context/context_assembler.dart';

class ContextReducer {
  const ContextReducer();

  ReducedContextSources reduce({
    required ContextPlan plan,
    required RetrievedContextSources sources,
    required List<AgentMessage> conversationHistory,
  }) {
    final reductions = <ContextReduction>[];
    final droppedItems = <ContextDroppedItem>[];
    final history = HistoryReducer().reduce(
      conversationHistory,
      maxTokens: plan.historyBudget,
      reductions: reductions,
      droppedItems: droppedItems,
    );
    final toolState = ToolResultReducer().reduce(
      conversationHistory
          .where((message) => message.isToolResult || message.isToolError)
          .toList(),
      maxTokens: plan.tokenAllocation.sectionBudgets['tool_state'] ?? 0,
      reductions: reductions,
      droppedItems: droppedItems,
    );
    final memory = MemoryReducer().reduce(
      sources.memoryMessages,
      maxTokens: plan.memoryRetrievalPlan.totalBudget,
      reductions: reductions,
      droppedItems: droppedItems,
    );
    final standingOrders = _slice(
      sources.standingOrders,
      plan.tokenAllocation.sectionBudgets['standing_orders'] ?? 0,
      'standing_orders',
      reductions,
      droppedItems,
    );

    final estimated = ContextAssembler.estimateMessagesTokens(<AgentMessage>[
      ...history.selectedMessages,
      ...toolState,
      ...memory,
      ...standingOrders,
    ]);

    return ReducedContextSources(
      memoryIndexBlock: sources.memoryIndexBlock,
      memoryMessages: memory,
      standingOrders: standingOrders,
      historySelection: history,
      toolStateMessages: toolState,
      workflowContext: sources.workflowContext,
      reductions: List<ContextReduction>.unmodifiable(reductions),
      droppedItems: List<ContextDroppedItem>.unmodifiable(droppedItems),
      compactRecommended:
          plan.tokenAllocation.compactRecommended ||
          estimated + plan.tokenAllocation.outputReserve >
              (plan.tokenAllocation.totalBudget * 0.82).floor(),
      memoryRetrievalStatus: sources.memoryRetrievalStatus,
      memoryRetrievalReason: sources.memoryRetrievalReason,
      embeddingModelIdUsed: sources.embeddingModelIdUsed,
      skippedCrossModelCount: sources.skippedCrossModelCount,
    );
  }

  List<AgentMessage> _slice(
    List<AgentMessage> messages,
    int maxTokens,
    String sectionId,
    List<ContextReduction> reductions,
    List<ContextDroppedItem> droppedItems,
  ) {
    final before = ContextAssembler.estimateMessagesTokens(messages);
    final selected = _takeNewest(messages, maxTokens);
    final after = ContextAssembler.estimateMessagesTokens(selected);
    if (after < before) {
      for (final message in messages.where(
        (message) => !selected.contains(message),
      )) {
        droppedItems.add(
          ContextDroppedItem(
            sectionId: sectionId,
            itemId:
                message.turnNumber?.toString() ??
                message.content.hashCode.toString(),
            reason: 'Dropped by section budget slice.',
            estimatedTokens: ContextAssembler.estimateTextTokens(
              message.content,
            ),
          ),
        );
      }
      reductions.add(
        ContextReduction(
          sectionId: sectionId,
          strategy: 'budget_slice',
          beforeTokens: before,
          afterTokens: after,
          reason: 'Section exceeded planned token budget.',
        ),
      );
    }
    return selected;
  }

  List<AgentMessage> _takeNewest(List<AgentMessage> messages, int maxTokens) {
    final selected = <AgentMessage>[];
    var used = 0;
    for (final message in messages.reversed) {
      final tokens = ContextAssembler.estimateTextTokens(message.content);
      if (used + tokens > maxTokens) continue;
      selected.add(message);
      used += tokens;
    }
    return selected.reversed.toList(growable: false);
  }
}

class HistoryReducer {
  HistorySelection reduce(
    List<AgentMessage> history, {
    required int maxTokens,
    required List<ContextReduction> reductions,
    required List<ContextDroppedItem> droppedItems,
  }) {
    if (history.isEmpty) {
      return const HistorySelection(reason: 'No prior history.');
    }
    final protected = <AgentMessage>[];
    final firstUser = history.where(
      (message) => message.role == AgentMessageRole.user,
    );
    if (firstUser.isNotEmpty) {
      protected.add(firstUser.first);
    }
    protected.addAll(
      history.where(
        (message) =>
            message.content.toLowerCase().contains('confirm') ||
            message.content.toLowerCase().contains('constraint') ||
            message.content.contains('EXECUTION_CONTINUATION_STATE'),
      ),
    );

    final selected = <AgentMessage>[];
    final seen = <AgentMessage>{};
    var used = 0;

    void addIfFits(AgentMessage message) {
      if (seen.contains(message)) return;
      final tokens = ContextAssembler.estimateTextTokens(message.content);
      if (used + tokens > maxTokens) return;
      selected.add(message);
      seen.add(message);
      used += tokens;
    }

    for (final message in protected) {
      addIfFits(message);
    }
    for (final message in history.reversed) {
      if (message.isToolResult || message.isToolError) {
        continue;
      }
      addIfFits(message);
    }
    selected.sort(
      (left, right) => (left.turnNumber ?? 0).compareTo(right.turnNumber ?? 0),
    );
    final dropped = history
        .where((message) => !seen.contains(message))
        .toList();
    for (final message in dropped) {
      droppedItems.add(
        ContextDroppedItem(
          sectionId: message.isToolResult || message.isToolError
              ? 'tool_state'
              : 'history',
          itemId:
              message.turnNumber?.toString() ??
              message.content.hashCode.toString(),
          reason: message.isToolResult || message.isToolError
              ? 'Tool messages are reduced into previous tool state.'
              : 'Dropped by structural history planning.',
          estimatedTokens: ContextAssembler.estimateTextTokens(message.content),
        ),
      );
    }
    if (dropped.isNotEmpty) {
      reductions.add(
        ContextReduction(
          sectionId: 'history',
          strategy: 'structural_selection',
          beforeTokens: ContextAssembler.estimateMessagesTokens(history),
          afterTokens: ContextAssembler.estimateMessagesTokens(selected),
          reason:
              'Preserved root, constraints, continuation, and recent turns.',
        ),
      );
    }
    return HistorySelection(
      selectedMessages: List<AgentMessage>.unmodifiable(selected),
      droppedMessages: List<AgentMessage>.unmodifiable(dropped),
      reason: 'Structural history planning.',
    );
  }
}

class ToolResultReducer {
  List<AgentMessage> reduce(
    List<AgentMessage> toolMessages, {
    required int maxTokens,
    required List<ContextReduction> reductions,
    required List<ContextDroppedItem> droppedItems,
  }) {
    if (toolMessages.isEmpty) {
      return const <AgentMessage>[];
    }
    final summaries = toolMessages.map(_summarize).toList(growable: false);
    final before = ContextAssembler.estimateMessagesTokens(toolMessages);
    final selected = <AgentMessage>[];
    var used = 0;
    for (final message in summaries.reversed) {
      final tokens = ContextAssembler.estimateTextTokens(message.content);
      if (used + tokens > math.max(1, maxTokens)) {
        continue;
      }
      selected.add(message);
      used += tokens;
    }
    final result = selected.reversed.toList(growable: false);
    final dropped = summaries.where((message) => !result.contains(message));
    for (final message in dropped) {
      droppedItems.add(
        ContextDroppedItem(
          sectionId: 'tool_state',
          itemId: message.toolCallId ?? message.content.hashCode.toString(),
          reason:
              'Dropped reduced tool result because tool-state budget was exhausted.',
          estimatedTokens: ContextAssembler.estimateTextTokens(message.content),
        ),
      );
    }
    final after = ContextAssembler.estimateMessagesTokens(result);
    reductions.add(
      ContextReduction(
        sectionId: 'tool_state',
        strategy: 'tool_result_summary',
        beforeTokens: before,
        afterTokens: after,
        reason: 'Old tool results are normalized before prompt injection.',
      ),
    );
    return result;
  }

  AgentMessage _summarize(AgentMessage message) {
    final status =
        message.metadata['status']?.toString() ??
        message.metadata['statusName']?.toString() ??
        'unknown';
    final toolId =
        message.metadata['toolId']?.toString() ??
        message.metadata['tool_id']?.toString() ??
        'unknown';
    final reason = message.metadata['metadata'] is Map
        ? ((message.metadata['metadata'] as Map)['reason'] ??
              (message.metadata['metadata'] as Map)['errorCode'])
        : message.metadata['reason'] ?? message.metadata['errorCode'];
    final buffer = StringBuffer()
      ..writeln('[TOOL RESULT SUMMARY]')
      ..writeln('tool: $toolId')
      ..writeln('status: $status')
      ..writeln('summary: ${_firstLine(message.content)}');
    if (reason != null) {
      buffer.writeln('reason: $reason');
    }
    buffer.write('[END TOOL RESULT SUMMARY]');
    return AgentMessage(
      role: message.role,
      content: buffer.toString(),
      toolCallId: message.toolCallId,
      turnNumber: message.turnNumber,
      metadata: <String, Object?>{
        ...message.metadata,
        'reduced': true,
        'context_section_id': 'tool_state',
      },
    );
  }

  String _firstLine(String value) {
    final line = value.split('\n').first.trim();
    return line.length > 180 ? '${line.substring(0, 180)}...' : line;
  }
}

class MemoryReducer {
  List<AgentMessage> reduce(
    List<AgentMessage> memories, {
    required int maxTokens,
    required List<ContextReduction> reductions,
    required List<ContextDroppedItem> droppedItems,
  }) {
    final before = ContextAssembler.estimateMessagesTokens(memories);
    final selected = <AgentMessage>[];
    var used = 0;
    for (final memory in memories) {
      final tokens = ContextAssembler.estimateTextTokens(memory.content);
      if (used + tokens > maxTokens) continue;
      selected.add(memory);
      used += tokens;
    }
    if (selected.length != memories.length) {
      for (final memory in memories.where(
        (memory) => !selected.contains(memory),
      )) {
        droppedItems.add(
          ContextDroppedItem(
            sectionId: 'memory',
            itemId:
                memory.turnNumber?.toString() ??
                memory.content.hashCode.toString(),
            reason:
                'Dropped memory candidate because memory budget was exhausted.',
            estimatedTokens: ContextAssembler.estimateTextTokens(
              memory.content,
            ),
          ),
        );
      }
      reductions.add(
        ContextReduction(
          sectionId: 'memory',
          strategy: 'ranked_budget_slice',
          beforeTokens: before,
          afterTokens: ContextAssembler.estimateMessagesTokens(selected),
          reason: 'Memory candidates exceeded planned budget.',
        ),
      );
    }
    return selected;
  }
}
