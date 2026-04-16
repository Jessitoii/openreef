import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/context/compiled_context_package.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/semantic_memory_retriever.dart';

class ContextRenderer {
  const ContextRenderer();

  List<CompiledContextSection> renderSections({
    required ContextPlan plan,
    required ReducedContextSources sources,
    required String userMessage,
  }) {
    final sections = <CompiledContextSection>[
      _section(
        id: 'identity',
        title: 'SYSTEM IDENTITY',
        content:
            '[SYSTEM IDENTITY]\nYou are OpenReef, an on-device AI agent.\nYou operate only using the provided context and tools.\nYou must not assume capabilities outside the provided context.\n[END SYSTEM IDENTITY]',
        reason: 'Base runtime identity.',
        critical: true,
        priority: 100,
      ),
      _section(
        id: 'execution_mode',
        title: 'EXECUTION MODE',
        content:
            '[EXECUTION MODE]\nmode: ${plan.executionMode.name}\ndomain: ${plan.turnClassification.domain}\ntaskType: ${plan.turnClassification.taskType}\n[END EXECUTION MODE]',
        reason: 'Execution mode is explicit for this turn.',
        critical: true,
        priority: 95,
      ),
      _section(
        id: 'core_rules',
        title: 'CORE OPERATING RULES',
        content: _renderCoreRules(),
        reason: 'Essential behavioral contract for on-device reasoning.',
        critical: true,
        priority: 94,
      ),
      _section(
        id: 'decision_policy',
        title: 'DECISION POLICY',
        content: _renderDecisionPolicy(),
        reason: 'Priority evaluation ladder for the current turn.',
        critical: true,
        priority: 93,
      ),
      _section(
        id: 'safety',
        title: 'SAFETY RULES',
        content: _renderSafety(plan.safetyEnvelope),
        reason: 'Safety envelope from policy evaluator.',
        critical: true,
        priority: 90,
      ),
      if (!sources.workflowContext.isEmpty)
        _section(
          id: 'workflow',
          title: 'WORKFLOW STATE',
          content: _renderWorkflow(sources.workflowContext),
          reason: 'Workflow state is relevant to this turn.',
          priority: 80,
          sourceCount: 1,
          metadata: <String, Object?>{
            if (sources.workflowContext.artifacts['currentStepIndex'] != null)
              'currentStepIndex':
                  sources.workflowContext.artifacts['currentStepIndex'],
            if (sources.workflowContext.resolvedEntities.isNotEmpty)
              'variables': sources.workflowContext.resolvedEntities,
            if (sources.workflowContext.currentHypothesis != null)
              'waitingReason': sources.workflowContext.currentHypothesis,
          },
        ),
      _section(
        id: 'tools',
        title: 'AVAILABLE TOOLS',
        content: _renderTools(plan.toolExposure),
        reason: 'Policy-selected tool exposure.',
        priority: 70,
        sourceCount: plan.toolExposure.primaryTools.length,
      ),
      if (plan.skillPlan.activeSkills.isNotEmpty)
        _section(
          id: 'skills',
          title: 'ACTIVE SKILLS',
          content: _renderSkills(plan.skillPlan),
          reason: 'Progressive enabled skill injection.',
          priority: 65,
          sourceCount: plan.skillPlan.activeSkills.length,
        ),
      if (sources.standingOrders.isNotEmpty)
        _section(
          id: 'standing_orders',
          title: 'STANDING ORDERS',
          content: _renderMessages('STANDING ORDERS', sources.standingOrders),
          reason: 'Structured standing-order provider output.',
          priority: 60,
          sourceCount: sources.standingOrders.length,
          role: AgentMessageRole.standingOrder,
        ),
      _section(
        id: 'memory_index',
        title: 'MEMORY POINTERS',
        content: _renderMemoryIndex(sources),
        reason: _memoryIndexReason(sources),
        critical: true,
        priority: 85,
        role: AgentMessageRole.memory,
        sourceCount: 1,
      ),
      if (sources.memoryMessages.isNotEmpty)
        _section(
          id: 'memory',
          title: 'RETRIEVED MEMORY EVIDENCE',
          content: _renderMessages(
            'RETRIEVED MEMORY EVIDENCE',
            sources.memoryMessages,
          ),
          reason: 'Retrieved memory candidates selected by plan.',
          priority: 55,
          sourceCount: sources.memoryMessages.length,
          role: AgentMessageRole.memory,
        ),
      if (sources.historySelection.selectedMessages.isNotEmpty)
        _section(
          id: 'history',
          title: 'RECENT RELEVANT HISTORY',
          content: _renderMessages(
            'RECENT RELEVANT HISTORY',
            sources.historySelection.selectedMessages,
          ),
          reason: sources.historySelection.reason,
          priority: 50,
          sourceCount: sources.historySelection.selectedMessages.length,
        ),
      if (sources.toolStateMessages.isNotEmpty)
        _section(
          id: 'tool_state',
          title: 'PREVIOUS TOOL STATE',
          content: _renderMessages(
            'PREVIOUS TOOL STATE',
            sources.toolStateMessages,
          ),
          reason: 'Reduced old tool results before injection.',
          priority: 45,
          sourceCount: sources.toolStateMessages.length,
        ),
      _section(
        id: 'user',
        title: 'USER MESSAGE',
        content:
            '[USER MESSAGE]\nResolve the user’s current request using the policy above. Be direct. Use tools only when needed.\n\n$userMessage\n[END USER MESSAGE]',
        reason: 'Current user request.',
        critical: true,
        priority: 100,
        role: AgentMessageRole.user,
      ),
    ];

    return List<CompiledContextSection>.unmodifiable(sections);
  }

  CompiledPrompt renderPrompt(List<CompiledContextSection> sections) {
    var turn = 0;
    final messages = <AgentMessage>[];
    for (final section in sections) {
      messages.add(
        section.toMessage(
          turnNumber: section.role == AgentMessageRole.user ? ++turn : 0,
        ),
      );
    }
    return CompiledPrompt(
      sections: sections,
      messages: List<AgentMessage>.unmodifiable(messages),
      estimatedTokens: sections.fold<int>(
        0,
        (sum, section) => sum + section.estimatedTokens,
      ),
    );
  }

  RenderedContextPackage renderWithinBudget({
    required List<CompiledContextSection> sections,
    required TokenAllocation tokenAllocation,
  }) {
    final droppedSectionIds = <String>[];
    final droppedItems = <ContextDroppedItem>[];
    final reductions = <ContextReduction>[];
    final budget = tokenAllocation.totalBudget - tokenAllocation.outputReserve;
    final selected = List<CompiledContextSection>.from(sections);

    int totalTokens() =>
        selected.fold<int>(0, (sum, section) => sum + section.estimatedTokens);

    final optional = selected.where((section) => !section.critical).toList()
      ..sort((left, right) {
        final priorityCompare = left.priority.compareTo(right.priority);
        if (priorityCompare != 0) return priorityCompare;
        return right.estimatedTokens.compareTo(left.estimatedTokens);
      });
    for (final section in optional) {
      if (totalTokens() <= budget) {
        break;
      }
      selected.removeWhere((candidate) => candidate.id == section.id);
      droppedSectionIds.add(section.id);
      droppedItems.add(
        ContextDroppedItem(
          sectionId: section.id,
          itemId: section.id,
          reason: 'Dropped optional section to enforce final context budget.',
          estimatedTokens: section.estimatedTokens,
        ),
      );
      reductions.add(
        ContextReduction(
          sectionId: section.id,
          strategy: 'drop_optional_section',
          beforeTokens: section.estimatedTokens,
          afterTokens: 0,
          reason: 'Final rendered package exceeded token budget.',
        ),
      );
    }

    var degraded = false;
    String? degradationReason;
    if (totalTokens() > budget) {
      degraded = true;
      degradationReason = 'critical_sections_exceeded_context_budget';
      for (var index = 0; index < selected.length; index++) {
        final section = selected[index];
        if (section.id != 'user') {
          continue;
        }
        final targetTokens = (budget * 0.20).floor().clamp(16, 256).toInt();
        final trimmed = ContextAssembler.trimToTokens(
          section.content,
          targetTokens,
        );
        selected[index] = _section(
          id: section.id,
          title: section.title,
          content:
              '$trimmed\n[DEGRADED CONTEXT: user message trimmed to fit budget]',
          reason: '${section.reason} Trimmed by final budget enforcement.',
          priority: section.priority,
          critical: section.critical,
          sourceCount: section.sourceCount,
          role: section.role,
          metadata: section.metadata,
        );
        reductions.add(
          ContextReduction(
            sectionId: section.id,
            strategy: 'trim_critical_user_section',
            beforeTokens: section.estimatedTokens,
            afterTokens: selected[index].estimatedTokens,
            reason: degradationReason,
          ),
        );
      }
    }
    if (totalTokens() > budget) {
      for (var index = 0; index < selected.length; index++) {
        if (totalTokens() <= budget) {
          break;
        }
        final section = selected[index];
        if (!section.critical || section.id == 'identity') {
          continue;
        }
        final trimmed = ContextAssembler.trimToTokens(section.content, 40);
        selected[index] = _section(
          id: section.id,
          title: section.title,
          content: '$trimmed\n[DEGRADED CONTEXT: critical section trimmed]',
          reason: '${section.reason} Trimmed by critical budget enforcement.',
          priority: section.priority,
          critical: section.critical,
          sourceCount: section.sourceCount,
          role: section.role,
          metadata: section.metadata,
        );
        reductions.add(
          ContextReduction(
            sectionId: section.id,
            strategy: 'trim_critical_section',
            beforeTokens: section.estimatedTokens,
            afterTokens: selected[index].estimatedTokens,
            reason:
                degradationReason ??
                'critical_sections_exceeded_context_budget',
          ),
        );
      }
    }

    return RenderedContextPackage(
      sections: List<CompiledContextSection>.unmodifiable(selected),
      prompt: renderPrompt(selected),
      droppedSectionIds: List<String>.unmodifiable(droppedSectionIds),
      droppedItems: List<ContextDroppedItem>.unmodifiable(droppedItems),
      reductions: List<ContextReduction>.unmodifiable(reductions),
      degraded: degraded,
      degradationReason: degradationReason,
    );
  }

  CompiledContextSection _section({
    required String id,
    required String title,
    required String content,
    required String reason,
    int priority = 0,
    bool critical = false,
    int sourceCount = 0,
    AgentMessageRole role = AgentMessageRole.system,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return CompiledContextSection(
      id: id,
      title: title,
      content: content,
      estimatedTokens: ContextAssembler.estimateTextTokens(content),
      reason: reason,
      priority: priority,
      critical: critical,
      sourceCount: sourceCount,
      role: role,
      metadata: metadata,
    );
  }

  String _renderCoreRules() {
    return '''[CORE OPERATING RULES]
- Follow section priority.
- Answer using available evidence only.
- Use tools when external action or data is required.
- If required info is missing and no tool can get it, ask a concise clarification.
- NEVER fabricate tool results, permissions, or memory.
- Never ask for tool permission or confirmation in chat.
[END CORE OPERATING RULES]''';
  }

  String _renderDecisionPolicy() {
    return '''[DECISION POLICY]
Priority ladder:
1. If WORKFLOW STATE defines active steps or blockers, address them or continue.
2. Else if user asks an action requiring a tool, use the best matching AVAILABLE TOOL.
3. Else if answer is fully supported by current context, answer directly.
4. Else if memory/history hints are uncertain, state uncertainty briefly and ask or use a tool.
5. Else ask a brief clarification.

Evidence priority: USER MESSAGE > WORKFLOW STATE > PREVIOUS TOOL STATE (success) > RETRIEVED MEMORY > RECENT HISTORY.
[END DECISION POLICY]''';
  }

  String _renderSafety(SafetyEnvelope envelope) {
    final buffer = StringBuffer('[SAFETY RULES]\n')
      ..writeln(
        '- Runtime gating: ${envelope.confirmationRequired ? 'present' : 'none'}',
      );
    if (envelope.riskyToolIds.isNotEmpty) {
      buffer.writeln(
        '- High-risk tools (use cautiously): ${envelope.riskyToolIds.join(', ')}',
      );
    }
    if (envelope.hardConstraints.isNotEmpty) {
      buffer.writeln('- Hard Constraints (MUST OBEY):');
      for (final constraint in envelope.hardConstraints) {
        buffer.writeln('  * $constraint');
      }
    }
    buffer.write('[END SAFETY RULES]');
    return buffer.toString();
  }

  String _renderTools(ToolExposure exposure) {
    final buffer = StringBuffer('[AVAILABLE TOOLS]\n')
      ..writeln('ONLY the tools listed below exist for this turn.')
      ..writeln('Do not assume or reference unavailable tools.')
      ..writeln('===');
    for (final tool in exposure.primaryTools) {
      final suffix = tool.description.trim().isEmpty
          ? ''
          : ' - ${tool.description.trim()}';
      buffer.writeln(
        '- [${tool.id}]${tool.requiresConfirmation ? ' (Requires Confirmation)' : ''}$suffix',
      );
    }
    if (exposure.exclusionReasons.isNotEmpty) {
      buffer.writeln('===');
      buffer.writeln('Excluded (UNAVAILABLE):');
      for (final entry in exposure.exclusionReasons.entries) {
        buffer.writeln('- ${entry.key}: ${entry.value}');
      }
    }
    buffer.write('[END TOOLS]');
    return buffer.toString();
  }

  String _renderSkills(SkillPlan plan) {
    final buffer = StringBuffer('[ACTIVE SKILLS]\n')
      ..writeln(
        'Use skill instructions ONLY when relevant to the user request or active workflow.',
      )
      ..writeln('===');
    for (final skill in plan.activeSkills) {
      final decision = plan.decisions.where((item) => item.skillId == skill.id);
      final reason = decision.isEmpty
          ? 'policy match'
          : decision.first.activationReason;
      buffer
        ..writeln('Skill: ${skill.displayName} (${skill.id})')
        ..writeln('Context: $reason');
      if (skill.toolsRequired.isNotEmpty) {
        buffer.writeln('Requires Tools: ${skill.toolsRequired.join(', ')}');
      }
      buffer
        ..writeln('Instructions:')
        ..writeln(skill.content.trim())
        ..writeln('---');
    }
    buffer.write('[END SKILLS]');
    return buffer.toString();
  }

  String _renderWorkflow(WorkflowContext workflow) {
    final buffer = StringBuffer('[WORKFLOW STATE]\n')
      ..writeln('This is the CURRENT execution state. Not background info.')
      ..writeln('===');
    if (workflow.workflowId != null) {
      buffer.writeln('Active Workflow: ${workflow.workflowId}');
    }
    if (workflow.objective != null) {
      buffer.writeln('Objective: ${workflow.objective}');
      buffer.writeln('-> Keep response aligned to this objective.');
    }
    if (workflow.blockers.isNotEmpty) {
      buffer.writeln('Blockers: ${workflow.blockers.join(' | ')}');
      buffer.writeln(
        '-> RESOLVE blockers: ask user for missing input, or use a tool to unblock.',
      );
    } else if (workflow.pendingSteps.isNotEmpty) {
      buffer.writeln('Pending Steps: ${workflow.pendingSteps.join(' | ')}');
      buffer.writeln('-> CONTINUE from the nearest unfinished step.');
    }
    if (workflow.completedSteps.isNotEmpty) {
      buffer.writeln('Completed Steps: ${workflow.completedSteps.join(' | ')}');
    }
    if (workflow.resolvedEntities.isNotEmpty) {
      buffer.writeln('Resolved Variables: ${workflow.resolvedEntities}');
    }
    if (workflow.currentHypothesis != null) {
      buffer.writeln('Reasoning/Wait State: ${workflow.currentHypothesis}');
    }
    buffer.write('[END WORKFLOW STATE]');
    return buffer.toString();
  }

  String _renderMemoryIndex(ReducedContextSources sources) {
    final buffer = StringBuffer('[MEMORY POINTERS]\n');
    if (sources.memoryRetrievalStatus ==
        SemanticMemoryRetrievalStatus.unavailable) {
      buffer
        ..writeln('STATUS: UNAVAILABLE')
        ..writeln('-> Action: Do not rely on semantic memory for this turn.')
        ..writeln('reason: ${sources.memoryRetrievalReason}')
        ..writeln('embeddingModelId: ${sources.embeddingModelIdUsed}')
        ..write('[END MEMORY POINTERS]');
      return buffer.toString();
    }
    if (sources.memoryRetrievalStatus ==
        SemanticMemoryRetrievalStatus.degraded) {
      buffer
        ..writeln('STATUS: DEGRADED (partial/mismatched index)')
        ..writeln(
          '-> Action: Use cautiously; prefer current turn evidence and tool results.',
        )
        ..writeln('reason: ${sources.memoryRetrievalReason}')
        ..writeln('embeddingModelId: ${sources.embeddingModelIdUsed}')
        ..writeln('excludedMatches: ${sources.skippedCrossModelCount}')
        ..write('[END MEMORY POINTERS]');
      return buffer.toString();
    }
    if (sources.memoryIndexBlock.trim().isEmpty) {
      buffer
        ..writeln('STATUS: NO POINTERS')
        ..writeln('-> Action: Continue without memory assumptions.')
        ..write('[END MEMORY POINTERS]');
      return buffer.toString();
    }
    buffer
      ..writeln(sources.memoryIndexBlock)
      ..write('[END MEMORY POINTERS]');
    return buffer.toString();
  }

  String _memoryIndexReason(ReducedContextSources sources) {
    return switch (sources.memoryRetrievalStatus) {
      SemanticMemoryRetrievalStatus.unavailable =>
        'Semantic memory retrieval unavailable for this turn.',
      SemanticMemoryRetrievalStatus.degraded =>
        'Semantic memory retrieval degraded because of model mismatch or partial results.',
      SemanticMemoryRetrievalStatus.success =>
        'Semantic memory retrieval returned real matches.',
      SemanticMemoryRetrievalStatus.noMatches =>
        sources.memoryIndexBlock.trim().isEmpty
            ? 'No memory pointers available.'
            : 'Memory pointers available without semantic matches.',
    };
  }

  String _renderMessages(String title, List<AgentMessage> messages) {
    final buffer = StringBuffer('[$title]\n');
    if (title == 'PREVIOUS TOOL STATE') {
      buffer.writeln(
        'Rule: Recent tool results are authoritative ONLY if successful and shown below.',
      );
    } else if (title == 'RECENT RELEVANT HISTORY') {
      buffer.writeln(
        'Rule: History is secondary evidence. Current message and explicit tool results take priority.',
      );
    }
    for (final message in messages) {
      buffer.writeln(message.toPromptSegment());
    }
    buffer.write('[END $title]');
    return buffer.toString();
  }
}
