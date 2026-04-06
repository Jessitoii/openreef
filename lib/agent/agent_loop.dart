import 'package:openreef/agent/agent_model_adapter.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/agent_notifier.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/compactor.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_former.dart';
import 'package:openreef/memory/memory_turn.dart';
import 'package:openreef/models/litert_bridge.dart';

class AgentLoop {
  AgentLoop({
    required ContextAssembler contextAssembler,
    required ReefCompactor compactor,
    required AgentModelAdapter modelAdapter,
    required ToolRouter toolRouter,
    required MemoryFormer memoryFormer,
    AgentNotifier notifier = const NoopAgentNotifier(),
  }) : _contextAssembler = contextAssembler,
       _compactor = compactor,
       _modelAdapter = modelAdapter,
       _toolRouter = toolRouter,
       _memoryFormer = memoryFormer,
       _notifier = notifier;

  static const int maxErrors = 3;
  static const int _autoCompactReserveTokens = 2000;
  static const int _autoCompactSummaryTokens = 4000;

  final ContextAssembler _contextAssembler;
  final ReefCompactor _compactor;
  final AgentModelAdapter _modelAdapter;
  final ToolRouter _toolRouter;
  final MemoryFormer _memoryFormer;
  final AgentNotifier _notifier;

  Future<AgentLoopResult> run(
    String userMessage, {
    required String sessionKey,
    List<AgentMessage> conversationHistory = const <AgentMessage>[],
    int modelContextWindow = 8192,
    bool compactRequested = false,
    List<String> recentFiles = const <String>[],
  }) async {
    var context = await _contextAssembler.assemble(
      sessionKey: sessionKey,
      userMessage: userMessage,
      conversationHistory: conversationHistory,
      modelContextWindow: modelContextWindow,
      compactRequested: compactRequested,
      recentFiles: recentFiles,
    );

    var consecutiveErrors = 0;
    var failedToolCalls = false;
    late AgentResponse response;

    try {
      response = await _modelAdapter.generate(
        context,
        maxTokens: context.tokenBudget.outputReserve,
      );
    } catch (error) {
      return _completeWithGenerationFailure(
        error,
        sessionKey: sessionKey,
        hasFailedToolCalls: failedToolCalls,
      );
    }

    while (response.hasToolCall) {
      if (consecutiveErrors >= maxErrors) {
        await _freezeSession(sessionKey);
        await _memoryFormer.process(
          MemoryTurn(
            facts: const [],
            hasFailedToolCalls: true,
            isAmbiguous: false,
            sessionKey: sessionKey,
          ),
        );
        return const AgentLoopResult(
          sessionResult: SessionResult.frozen,
          text: '',
        );
      }

      context = await _applyCompaction(context);
      final toolCall = response.toolCall!;
      try {
        final result = await _toolRouter.dispatch(
          toolCall,
          sessionKey: sessionKey,
        );
        context = context.appendToolResult(toolCall.id, result);
        consecutiveErrors = 0;
      } catch (error) {
        failedToolCalls = true;
        consecutiveErrors += 1;
        context = context.appendToolError(toolCall.id, error);
      }

      try {
        response = await _modelAdapter.generate(
          context,
          maxTokens: context.tokenBudget.outputReserve,
        );
      } catch (error) {
        return _completeWithGenerationFailure(
          error,
          sessionKey: sessionKey,
          hasFailedToolCalls: true,
        );
      }
    }

    await _memoryFormer.process(
      MemoryTurn(
        facts: const [],
        hasFailedToolCalls: failedToolCalls,
        isAmbiguous: false,
        sessionKey: sessionKey,
      ),
    );

    return AgentLoopResult(
      sessionResult: SessionResult.completed,
      text: response.text,
    );
  }

  Future<AgentLoopResult> _completeWithGenerationFailure(
    Object error, {
    required String sessionKey,
    required bool hasFailedToolCalls,
  }) async {
    await _memoryFormer.process(
      MemoryTurn(
        facts: const [],
        hasFailedToolCalls: hasFailedToolCalls,
        isAmbiguous: false,
        sessionKey: sessionKey,
      ),
    );

    final message = switch (error) {
      LiteRtCrashShieldException() =>
        'OpenReef paused generation to protect your phone. ${error.toString()}',
      _ => 'LiteRT generation failed: $error',
    };

    return AgentLoopResult(
      sessionResult: SessionResult.completed,
      text: message,
    );
  }

  Future<AssembleResult> _applyCompaction(AssembleResult context) async {
    var nextContext = context.copyWith(
      tokenBudget: _contextAssembler.estimateTokens(
        context,
        totalBudget: context.tokenBudget.totalBudget,
        historyBudget: context.tokenBudget.historyBudget,
        memoryBudget: context.tokenBudget.memoryBudget,
        standingOrderBudget: context.tokenBudget.standingOrderBudget,
      ),
    );

    if (nextContext.tokenBudget.oldToolResults > 0) {
      nextContext = _compactor.microCompact(nextContext);
    }

    nextContext = nextContext.copyWith(
      tokenBudget: _contextAssembler.estimateTokens(
        nextContext,
        totalBudget: nextContext.tokenBudget.totalBudget,
        historyBudget: nextContext.tokenBudget.historyBudget,
        memoryBudget: nextContext.tokenBudget.memoryBudget,
        standingOrderBudget: nextContext.tokenBudget.standingOrderBudget,
      ),
    );

    if (nextContext.tokenBudget.ratio > 0.80) {
      nextContext = await _compactor.autoCompact(
        nextContext,
        reserveTokens: _autoCompactReserveTokens,
        maxSummaryTokens: _autoCompactSummaryTokens,
      );
      nextContext = nextContext.copyWith(
        tokenBudget: _contextAssembler.estimateTokens(
          nextContext,
          totalBudget: nextContext.tokenBudget.totalBudget,
          historyBudget: nextContext.tokenBudget.historyBudget,
          memoryBudget: nextContext.tokenBudget.memoryBudget,
          standingOrderBudget: nextContext.tokenBudget.standingOrderBudget,
        ),
      );
    }

    if (nextContext.tokenBudget.remaining < 1500 ||
        nextContext.compactRequested) {
      nextContext = await _compactor.fullCompact(
        nextContext,
        reInjectRecentFiles: true,
        reInjectActiveSkills: true,
      );
      nextContext = nextContext.copyWith(
        tokenBudget: _contextAssembler.estimateTokens(
          nextContext,
          totalBudget: nextContext.tokenBudget.totalBudget,
          historyBudget: nextContext.tokenBudget.historyBudget,
          memoryBudget: nextContext.tokenBudget.memoryBudget,
          standingOrderBudget: nextContext.tokenBudget.standingOrderBudget,
        ),
        compactRequested: false,
      );
    }

    return nextContext;
  }

  Future<void> _freezeSession(String sessionKey) {
    return _notifier.freezeSession(
      sessionKey: sessionKey,
      reason: 'circuit_breaker',
      title: 'Session Frozen',
      body: '3 consecutive errors occurred.',
    );
  }
}
