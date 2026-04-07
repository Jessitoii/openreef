import 'package:openreef/agent/agent_model_adapter.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/agent_notifier.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/compactor.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_former.dart';
import 'package:openreef/memory/memory_formation_service.dart';
import 'package:openreef/memory/memory_turn.dart';
import 'package:openreef/models/litert_bridge.dart';

class AgentLoop {
  AgentLoop({
    required ContextAssembler contextAssembler,
    required ReefCompactor compactor,
    required AgentModelAdapter modelAdapter,
    required ToolRouter toolRouter,
    required MemoryFormer memoryFormer,
    MemoryFormationService? memoryFormationService,
    required AgentNotifier notifier,
  }) : _contextAssembler = contextAssembler,
       _compactor = compactor,
       _modelAdapter = modelAdapter,
       _toolRouter = toolRouter,
       _memoryFormer = memoryFormer,
       _memoryFormationService = memoryFormationService,
       _notifier = notifier;

  static const int maxErrors = 3;
  static const int _maxIterations = 12;
  static const int _maxRepeatedBlockedFingerprints = 3;
  static const int _autoCompactReserveTokens = 2000;
  static const int _autoCompactSummaryTokens = 4000;

  final ContextAssembler _contextAssembler;
  final ReefCompactor _compactor;
  final AgentModelAdapter _modelAdapter;
  final ToolRouter _toolRouter;
  final MemoryFormer _memoryFormer;
  final MemoryFormationService? _memoryFormationService;
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
    var iterationCount = 0;
    var failedToolCalls = false;
    var activeBlockedFingerprint = '';
    var repeatedBlockedFingerprintCount = 0;
    final afterTurnMessageStart = context.messages.length;
    late AgentResponse response;

    try {
      response = await _modelAdapter.generate(
        context,
        maxTokens: context.tokenBudget.outputReserve,
      );
    } catch (error) {
      return _completeWithFailure(
        'generation_failure',
        _generationFailureMessage(error),
        sessionKey: sessionKey,
        hasFailedToolCalls: failedToolCalls,
      );
    }

    while (response.hasToolCall) {
      iterationCount += 1;
      if (iterationCount > _maxIterations) {
        return _freezeForLoopSafety(
          sessionKey: sessionKey,
          hasFailedToolCalls: true,
          reason: 'iteration_cap',
          body: 'Agent loop stopped after hitting the iteration cap.',
        );
      }

      if (consecutiveErrors >= maxErrors) {
        return _freezeForLoopSafety(
          sessionKey: sessionKey,
          hasFailedToolCalls: true,
          reason: 'exception_loop',
          body: 'Repeated blocked tool errors occurred.',
        );
      }

      try {
        context = await _applyCompaction(context);
      } catch (error) {
        return _completeWithFailure(
          'compaction_failure',
          'Compaction failed: $error',
          sessionKey: sessionKey,
          hasFailedToolCalls: failedToolCalls,
        );
      }

      final toolCall = response.toolCall!;
      try {
        final result = await _toolRouter.dispatch(
          toolCall,
          sessionKey: sessionKey,
        );
        context = context.appendToolResult(toolCall.id, result);

        if (result.isRejected) {
          failedToolCalls = true;
          final nextFingerprint = _fingerprintRejectedToolCall(
            toolCall,
            result,
          );
          if (activeBlockedFingerprint == nextFingerprint) {
            repeatedBlockedFingerprintCount += 1;
          } else {
            activeBlockedFingerprint = nextFingerprint;
            repeatedBlockedFingerprintCount = 1;
          }

          if (repeatedBlockedFingerprintCount >=
              _maxRepeatedBlockedFingerprints) {
            return _freezeForLoopSafety(
              sessionKey: sessionKey,
              hasFailedToolCalls: true,
              reason: 'rejection_loop',
              body: 'Repeated blocked tool rejections occurred.',
            );
          }
        } else {
          consecutiveErrors = 0;
          activeBlockedFingerprint = '';
          repeatedBlockedFingerprintCount = 0;
        }
      } catch (error) {
        failedToolCalls = true;
        consecutiveErrors += 1;
        context = context.appendToolError(toolCall.id, error);

        final nextFingerprint = _fingerprintToolException(toolCall, error);
        if (activeBlockedFingerprint == nextFingerprint) {
          repeatedBlockedFingerprintCount += 1;
        } else {
          activeBlockedFingerprint = nextFingerprint;
          repeatedBlockedFingerprintCount = 1;
        }

        if (repeatedBlockedFingerprintCount >=
            _maxRepeatedBlockedFingerprints) {
          return _freezeForLoopSafety(
            sessionKey: sessionKey,
            hasFailedToolCalls: true,
            reason: 'exception_loop',
            body: 'Repeated blocked tool errors occurred.',
          );
        }
      }

      try {
        response = await _modelAdapter.generate(
          context,
          maxTokens: context.tokenBudget.outputReserve,
        );
      } catch (error) {
        return _completeWithFailure(
          'generation_failure',
          _generationFailureMessage(error),
          sessionKey: sessionKey,
          hasFailedToolCalls: failedToolCalls,
        );
      }
    }

    await _persistCompletedTurnMemory(
      sessionKey: sessionKey,
      userMessage: userMessage,
      responseText: response.text,
      context: context,
      afterTurnMessageStart: afterTurnMessageStart,
      hasFailedToolCalls: failedToolCalls,
    );

    return AgentLoopResult(
      sessionResult: SessionResult.completed,
      text: response.text,
      reason: 'completed',
    );
  }

  Future<AgentLoopResult> _completeWithFailure(
    String reason,
    String message, {
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

    return AgentLoopResult(
      sessionResult: SessionResult.failed,
      text: message,
      reason: reason,
    );
  }

  Future<void> _persistCompletedTurnMemory({
    required String sessionKey,
    required String userMessage,
    required String responseText,
    required AssembleResult context,
    required int afterTurnMessageStart,
    required bool hasFailedToolCalls,
  }) async {
    if (hasFailedToolCalls) {
      await _memoryFormer.process(
        MemoryTurn(
          facts: const [],
          hasFailedToolCalls: true,
          isAmbiguous: false,
          sessionKey: sessionKey,
        ),
      );
      return;
    }

    final formationService = _memoryFormationService;
    if (formationService == null) {
      return;
    }

    try {
      final result = await formationService.extract(
        CompletedTurnSnapshot(
          sessionKey: sessionKey,
          userMessage: userMessage,
          assistantMessage: responseText,
          toolOutputs: context.messages
              .skip(afterTurnMessageStart)
              .where(
                (message) =>
                    message.role == AgentMessageRole.tool ||
                    message.role == AgentMessageRole.toolError,
              )
              .toList(growable: false),
          occurredAt: DateTime.now(),
        ),
      );
      await _memoryFormer.process(
        MemoryTurn(
          facts: result.facts,
          hasFailedToolCalls: false,
          isAmbiguous: result.isAmbiguous,
          sessionKey: sessionKey,
        ),
      );
    } catch (_) {
      // Extraction failures must be deterministic no-write events.
    }
  }

  Future<AgentLoopResult> _freezeForLoopSafety({
    required String sessionKey,
    required bool hasFailedToolCalls,
    required String reason,
    required String body,
  }) async {
    await _freezeSession(sessionKey, reason: reason, body: body);
    await _memoryFormer.process(
      MemoryTurn(
        facts: const [],
        hasFailedToolCalls: hasFailedToolCalls,
        isAmbiguous: false,
        sessionKey: sessionKey,
      ),
    );
    return AgentLoopResult(
      sessionResult: SessionResult.frozen,
      text: '',
      reason: reason,
    );
  }

  String _generationFailureMessage(Object error) {
    return switch (error) {
      LiteRtCrashShieldException() =>
        'OpenReef paused generation to protect your phone. ${error.toString()}',
      _ => 'LiteRT generation failed: $error',
    };
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

  String _fingerprintRejectedToolCall(ToolCall call, ToolResult result) {
    final reason =
        result.metadata[ToolRouter.rejectionReasonKey] as String? ??
        'rejected_unknown';
    return '${call.toolId}|${_canonicalizeValue(call.arguments)}|rejected|$reason';
  }

  String _fingerprintToolException(ToolCall call, Object error) {
    final category = _normalizeExceptionCategory(error);
    return '${call.toolId}|${_canonicalizeValue(call.arguments)}|exception|$category';
  }

  String _normalizeExceptionCategory(Object error) {
    if (error is ArgumentError ||
        error is FormatException ||
        error is UnsupportedError) {
      return 'validation_error';
    }
    if (error is StateError || error is Exception) {
      return 'execution_error';
    }
    return 'unknown_error';
  }

  String _canonicalizeValue(Object? value) {
    if (value == null) {
      return 'null';
    }
    if (value is bool || value is num) {
      return value.toString();
    }
    if (value is String) {
      return '"$value"';
    }
    if (value is List) {
      return '[${value.map(_canonicalizeValue).join(',')}]';
    }
    if (value is Map) {
      final normalized = value.map(
        (key, nestedValue) => MapEntry(key.toString(), nestedValue),
      );
      final keys = normalized.keys.toList()..sort();
      return '{${keys.map((key) => '"$key":${_canonicalizeValue(normalized[key])}').join(',')}}';
    }
    return '"${value.toString()}"';
  }

  Future<void> _freezeSession(
    String sessionKey, {
    required String reason,
    required String body,
  }) {
    return _notifier.freezeSession(
      sessionKey: sessionKey,
      reason: reason,
      title: 'Session Frozen',
      body: body,
    );
  }
}
