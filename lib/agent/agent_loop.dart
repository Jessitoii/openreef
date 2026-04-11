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
    LoopControl control = const LoopControl(),
    LoopContinuation continuation = const LoopContinuation(),
  }) async {
    final startedAt = DateTime.now().toUtc();
    final seededHistory =
        continuation.currentStepIndex == 0 &&
            continuation.variables.isEmpty &&
            continuation.waitingReason == null
        ? conversationHistory
        : <AgentMessage>[
            ...conversationHistory,
            AgentMessage(
              role: AgentMessageRole.system,
              content:
                  'EXECUTION_CONTINUATION_STATE ${continuation.toMetadata()}',
              metadata: continuation.toMetadata(),
            ),
          ];
    var context = await _contextAssembler.assemble(
      sessionKey: sessionKey,
      userMessage: userMessage,
      conversationHistory: seededHistory,
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
    final toolsUsed = <String>[];
    final toolResults = <ToolResult>[];
    var currentStepIndex = continuation.currentStepIndex;
    var variables = Map<String, Object?>.from(continuation.variables);
    late AgentResponse response;

    final cancellation = _checkCancelled(control);
    if (cancellation != null) {
      return _cancelledResult(
        cancellation,
        toolsUsed: toolsUsed,
        toolResults: toolResults,
        continuation: LoopContinuation(
          currentStepIndex: currentStepIndex,
          variables: variables,
          waitingReason: continuation.waitingReason,
          waitingMetadata: continuation.waitingMetadata,
          resumeToken: continuation.resumeToken,
        ),
      );
    }

    try {
      response = await _modelAdapter.generate(
        context,
        maxTokens: context.tokenBudget.outputReserve,
      );
      final cancellationAfterGeneration = _checkCancelled(control);
      if (cancellationAfterGeneration != null) {
        return _cancelledResult(
          cancellationAfterGeneration,
          toolsUsed: toolsUsed,
          toolResults: toolResults,
          continuation: LoopContinuation(
            currentStepIndex: currentStepIndex,
            variables: variables,
            waitingReason: continuation.waitingReason,
            waitingMetadata: continuation.waitingMetadata,
            resumeToken: continuation.resumeToken,
          ),
        );
      }
    } catch (error) {
      return _completeWithFailure(
        'generation_failure',
        _generationFailureMessage(error),
        sessionKey: sessionKey,
        hasFailedToolCalls: failedToolCalls,
        toolsUsed: toolsUsed,
        toolResults: toolResults,
        continuation: LoopContinuation(
          currentStepIndex: currentStepIndex,
          variables: variables,
          waitingReason: continuation.waitingReason,
          waitingMetadata: continuation.waitingMetadata,
          resumeToken: continuation.resumeToken,
        ),
      );
    }

    while (response.hasToolCall) {
      iterationCount += 1;
      currentStepIndex += 1;
      final cancellation = _checkCancelled(control);
      if (cancellation != null) {
        return _cancelledResult(
          cancellation,
          toolsUsed: toolsUsed,
          toolResults: toolResults,
          continuation: LoopContinuation(
            currentStepIndex: currentStepIndex,
            variables: variables,
            waitingReason: continuation.waitingReason,
            waitingMetadata: continuation.waitingMetadata,
            resumeToken: continuation.resumeToken,
          ),
        );
      }
      if (_timedOut(startedAt, control)) {
        return _completeWithFailure(
          'timeout',
          'Execution timed out.',
          sessionKey: sessionKey,
          hasFailedToolCalls: failedToolCalls,
          toolsUsed: toolsUsed,
          toolResults: toolResults,
          continuation: LoopContinuation(
            currentStepIndex: currentStepIndex,
            variables: variables,
            waitingReason: continuation.waitingReason,
            waitingMetadata: continuation.waitingMetadata,
            resumeToken: continuation.resumeToken,
          ),
        );
      }
      if (iterationCount > control.maxSteps ||
          iterationCount > _maxIterations) {
        return _freezeForLoopSafety(
          sessionKey: sessionKey,
          hasFailedToolCalls: true,
          reason: 'iteration_cap',
          body: 'Agent loop stopped after hitting the iteration cap.',
          toolsUsed: toolsUsed,
          toolResults: toolResults,
          continuation: LoopContinuation(
            currentStepIndex: currentStepIndex,
            variables: variables,
            waitingReason: continuation.waitingReason,
            waitingMetadata: continuation.waitingMetadata,
            resumeToken: continuation.resumeToken,
          ),
        );
      }

      if (toolsUsed.length >= control.maxToolCalls) {
        return _freezeForLoopSafety(
          sessionKey: sessionKey,
          hasFailedToolCalls: true,
          reason: 'tool_call_cap',
          body: 'Agent loop stopped after hitting the tool call cap.',
          toolsUsed: toolsUsed,
          toolResults: toolResults,
          continuation: LoopContinuation(
            currentStepIndex: currentStepIndex,
            variables: variables,
            waitingReason: continuation.waitingReason,
            waitingMetadata: continuation.waitingMetadata,
            resumeToken: continuation.resumeToken,
          ),
        );
      }

      if (consecutiveErrors >= maxErrors) {
        return _freezeForLoopSafety(
          sessionKey: sessionKey,
          hasFailedToolCalls: true,
          reason: 'exception_loop',
          body: 'Repeated blocked tool errors occurred.',
          toolsUsed: toolsUsed,
          toolResults: toolResults,
          continuation: LoopContinuation(
            currentStepIndex: currentStepIndex,
            variables: variables,
            waitingReason: continuation.waitingReason,
            waitingMetadata: continuation.waitingMetadata,
            resumeToken: continuation.resumeToken,
          ),
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
          toolsUsed: toolsUsed,
          toolResults: toolResults,
          continuation: LoopContinuation(
            currentStepIndex: currentStepIndex,
            variables: variables,
            waitingReason: continuation.waitingReason,
            waitingMetadata: continuation.waitingMetadata,
            resumeToken: continuation.resumeToken,
          ),
        );
      }

      final pendingToolCalls = response.effectiveToolCalls;
      for (final toolCall in pendingToolCalls) {
        final cancellationBeforeTool = _checkCancelled(control);
        if (cancellationBeforeTool != null) {
          final result = ToolResult.failure(
            'Tool execution was cancelled.',
            toolId: toolCall.toolId,
            callId: toolCall.id,
            status: ToolResultStatus.cancelled,
            userVisibleMessage: 'Tool execution was cancelled.',
            metadata: <String, Object?>{
              'reason': cancellationBeforeTool,
              'errorCode': 'tool_cancelled',
            },
          );
          toolsUsed.add(toolCall.toolId);
          toolResults.add(result);
          context = context.appendToolResult(toolCall.id, result);
          return _cancelledResult(
            cancellationBeforeTool,
            toolsUsed: toolsUsed,
            toolResults: toolResults,
            continuation: LoopContinuation(
              currentStepIndex: currentStepIndex,
              variables: variables,
              waitingReason: continuation.waitingReason,
              waitingMetadata: continuation.waitingMetadata,
              resumeToken: continuation.resumeToken,
            ),
          );
        }

        if (toolsUsed.length >= control.maxToolCalls) {
          return _freezeForLoopSafety(
            sessionKey: sessionKey,
            hasFailedToolCalls: true,
            reason: 'tool_call_cap',
            body: 'Agent loop stopped after hitting the tool call cap.',
            toolsUsed: toolsUsed,
            toolResults: toolResults,
            continuation: LoopContinuation(
              currentStepIndex: currentStepIndex,
              variables: variables,
              waitingReason: continuation.waitingReason,
              waitingMetadata: continuation.waitingMetadata,
              resumeToken: continuation.resumeToken,
            ),
          );
        }

        toolsUsed.add(toolCall.toolId);
        try {
          final result = await _toolRouter.dispatch(
            toolCall,
            sessionKey: sessionKey,
          );
          toolResults.add(result);
          variables['lastToolId'] = toolCall.toolId;
          variables['lastToolStatus'] = result.statusName;
          variables['lastToolSummary'] = result.summary;
          context = context.appendToolResult(toolCall.id, result);

          if (result.isError) {
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
              final reason = result.status == ToolResultStatus.executionError
                  ? 'exception_loop'
                  : 'rejection_loop';
              return _freezeForLoopSafety(
                sessionKey: sessionKey,
                hasFailedToolCalls: true,
                reason: reason,
                body: result.status == ToolResultStatus.executionError
                    ? 'Repeated blocked tool errors occurred.'
                    : 'Repeated blocked tool rejections occurred.',
                toolsUsed: toolsUsed,
                toolResults: toolResults,
                continuation: LoopContinuation(
                  currentStepIndex: currentStepIndex,
                  variables: variables,
                  waitingReason: continuation.waitingReason,
                  waitingMetadata: continuation.waitingMetadata,
                  resumeToken: continuation.resumeToken,
                ),
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
          final result = ToolResult.failure(
            'Tool dispatch failed: $error',
            toolId: toolCall.toolId,
            callId: toolCall.id,
            status: ToolResultStatus.executionError,
            userVisibleMessage: 'Tool dispatch failed.',
            metadata: <String, Object?>{
              'reason': 'router_contract_violation',
              'errorCode': 'router_contract_violation',
              'errorMessage': error.toString(),
            },
          );
          toolResults.add(result);
          context = context.appendToolResult(toolCall.id, result);

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
              toolsUsed: toolsUsed,
              toolResults: toolResults,
              continuation: LoopContinuation(
                currentStepIndex: currentStepIndex,
                variables: variables,
                waitingReason: continuation.waitingReason,
                waitingMetadata: continuation.waitingMetadata,
                resumeToken: continuation.resumeToken,
              ),
            );
          }
        }
      }

      try {
        response = await _modelAdapter.generate(
          context,
          maxTokens: context.tokenBudget.outputReserve,
        );
        final cancellationAfterGeneration = _checkCancelled(control);
        if (cancellationAfterGeneration != null) {
          return _cancelledResult(
            cancellationAfterGeneration,
            toolsUsed: toolsUsed,
            toolResults: toolResults,
            continuation: LoopContinuation(
              currentStepIndex: currentStepIndex,
              variables: variables,
              waitingReason: continuation.waitingReason,
              waitingMetadata: continuation.waitingMetadata,
              resumeToken: continuation.resumeToken,
            ),
          );
        }
      } catch (error) {
        return _completeWithFailure(
          'generation_failure',
          _generationFailureMessage(error),
          sessionKey: sessionKey,
          hasFailedToolCalls: failedToolCalls,
          toolsUsed: toolsUsed,
          toolResults: toolResults,
          continuation: LoopContinuation(
            currentStepIndex: currentStepIndex,
            variables: variables,
            waitingReason: continuation.waitingReason,
            waitingMetadata: continuation.waitingMetadata,
            resumeToken: continuation.resumeToken,
          ),
        );
      }
    }

    currentStepIndex += 1;
    variables['lastResponseText'] = response.text;

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
      toolsUsed: List<String>.unmodifiable(toolsUsed),
      toolResults: List<ToolResult>.unmodifiable(toolResults),
      stepCount: currentStepIndex - continuation.currentStepIndex,
      toolCallCount: toolsUsed.length,
      continuation: LoopContinuation(
        currentStepIndex: currentStepIndex,
        variables: variables,
        waitingReason: continuation.waitingReason,
        waitingMetadata: continuation.waitingMetadata,
        resumeToken: continuation.resumeToken,
      ),
    );
  }

  Future<AgentLoopResult> _completeWithFailure(
    String reason,
    String message, {
    required String sessionKey,
    required bool hasFailedToolCalls,
    required List<String> toolsUsed,
    required List<ToolResult> toolResults,
    required LoopContinuation continuation,
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
      toolsUsed: List<String>.unmodifiable(toolsUsed),
      toolResults: List<ToolResult>.unmodifiable(toolResults),
      stepCount: continuation.currentStepIndex,
      toolCallCount: toolsUsed.length,
      continuation: continuation,
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
    required List<String> toolsUsed,
    required List<ToolResult> toolResults,
    required LoopContinuation continuation,
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
      toolsUsed: List<String>.unmodifiable(toolsUsed),
      toolResults: List<ToolResult>.unmodifiable(toolResults),
      stepCount: continuation.currentStepIndex,
      toolCallCount: toolsUsed.length,
      continuation: continuation,
    );
  }

  AgentLoopResult _cancelledResult(
    String reason, {
    required List<String> toolsUsed,
    required List<ToolResult> toolResults,
    required LoopContinuation continuation,
  }) {
    return AgentLoopResult(
      sessionResult: SessionResult.cancelled,
      text: '',
      reason: reason,
      toolsUsed: List<String>.unmodifiable(toolsUsed),
      toolResults: List<ToolResult>.unmodifiable(toolResults),
      stepCount: continuation.currentStepIndex,
      toolCallCount: toolsUsed.length,
      continuation: continuation,
    );
  }

  String? _checkCancelled(LoopControl control) {
    final cancellation = control.cancellationSignal;
    if (cancellation == null || !cancellation.isCancelled) {
      return null;
    }
    return cancellation.reason ?? 'cancelled';
  }

  bool _timedOut(DateTime startedAt, LoopControl control) {
    return DateTime.now().toUtc().difference(startedAt) > control.timeout;
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
        result.metadata['reason'] as String? ??
        result.metadata[ToolRouter.rejectionReasonKey] as String? ??
        result.metadata['errorCode'] as String? ??
        '${result.statusName}_unknown';
    return '${call.toolId}|${_canonicalizeValue(call.arguments)}|${result.statusName}|$reason';
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
