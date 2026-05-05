import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/models/litert_bridge.dart';

abstract class AgentModelAdapter {
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  });
}

abstract class StreamingAgentModelAdapter implements AgentModelAdapter {
  Stream<String> generateTextStream(
    AssembleResult context, {
    required int maxTokens,
  });
}

abstract class ToolResponseModelAdapter implements AgentModelAdapter {
  Future<void> appendToolResponse({
    required ToolCall toolCall,
    required ToolResult result,
  });

  Future<AgentResponse> continueAfterToolResponses({required int maxTokens});
}

abstract class CancellableAgentModelAdapter {
  Future<bool> cancelGeneration();
}

enum ToolInvocationMode { none, structuredFunctionCalls, textProtocolFallback }

abstract class ToolInvocationModeReporter {
  ToolInvocationMode toolInvocationModeFor(AssembleResult context);
}

class LiteRtAgentModelAdapter
    implements
        StreamingAgentModelAdapter,
        ToolResponseModelAdapter,
        ToolInvocationModeReporter,
        CancellableAgentModelAdapter {
  LiteRtAgentModelAdapter({
    required LiteRtBridge bridge,
    AgentResponseParser parser = const AgentResponseParser(),
    Stream<LiteRtGenerationEvent> Function({
      required String context,
      required int maxTokens,
      required List<ToolDefinition> selectedTools,
    })?
    generateStreamOverride,
    Future<void> Function({
      required String toolName,
      required Map<String, dynamic> response,
    })?
    appendToolResponseOverride,
    Stream<LiteRtGenerationEvent> Function({required int maxTokens})?
    continueStreamOverride,
  }) : _bridge = bridge,
       _parser = parser,
       _generateStreamOverride = generateStreamOverride,
       _appendToolResponseOverride = appendToolResponseOverride,
       _continueStreamOverride = continueStreamOverride;

  final LiteRtBridge _bridge;
  final AgentResponseParser _parser;
  final Stream<LiteRtGenerationEvent> Function({
    required String context,
    required int maxTokens,
    required List<ToolDefinition> selectedTools,
  })?
  _generateStreamOverride;
  final Future<void> Function({
    required String toolName,
    required Map<String, dynamic> response,
  })?
  _appendToolResponseOverride;
  final Stream<LiteRtGenerationEvent> Function({required int maxTokens})?
  _continueStreamOverride;

  @override
  ToolInvocationMode toolInvocationModeFor(AssembleResult context) {
    if (context.selectedTools.isEmpty) {
      return ToolInvocationMode.none;
    }
    if (_bridge.supportsTypedFunctionCallsFor(context.selectedTools)) {
      return ToolInvocationMode.structuredFunctionCalls;
    }
    return ToolInvocationMode.textProtocolFallback;
  }

  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    final stream = _generateStreamOverride ?? _bridge.generateStream;
    Future<AgentResponse> generateOnce() {
      return _responseFromEvents(
        stream(
          context: context.toPrompt(),
          maxTokens: maxTokens,
          selectedTools: context.selectedTools,
        ),
      );
    }

    try {
      return await generateOnce();
    } catch (error) {
      if (!_isModelClosedError(error)) {
        rethrow;
      }
      await _bridge.recoverClosedModelSession();
      return generateOnce();
    }
  }

  Future<AgentResponse> _responseFromEvents(
    Stream<LiteRtGenerationEvent> events,
  ) async {
    final buffer = StringBuffer();
    final typedToolCalls = <ToolCall>[];
    await for (final event in events) {
      if (event.chunk.isNotEmpty) {
        buffer.write(event.chunk);
      }
      if (event.toolCalls.isNotEmpty) {
        typedToolCalls.addAll(event.toolCalls);
      }
      if (event.isFinished) {
        break;
      }
    }

    final rawOutput = buffer.toString();
    if (typedToolCalls.isNotEmpty) {
      return AgentResponse(
        text: rawOutput,
        toolCalls: List<ToolCall>.unmodifiable(
          typedToolCalls.map(
            (call) => call.withSource(ToolCallSource.flutterGemmaTyped),
          ),
        ),
        toolCallSource: ToolCallSource.flutterGemmaTyped,
        rawOutput: rawOutput,
      );
    }
    return _parser.parse(rawOutput);
  }

  @override
  Stream<String> generateTextStream(
    AssembleResult context, {
    required int maxTokens,
  }) async* {
    final stream = _generateStreamOverride ?? _bridge.generateStream;
    Stream<LiteRtGenerationEvent> generateOnce() {
      return stream(
        context: context.toPrompt(),
        maxTokens: maxTokens,
        selectedTools: context.selectedTools,
      );
    }

    var retried = false;
    while (true) {
      try {
        await for (final event in generateOnce()) {
          if (event.chunk.isNotEmpty) {
            yield event.chunk;
          }
          if (event.isFinished) {
            break;
          }
        }
        return;
      } catch (error) {
        if (retried || !_isModelClosedError(error)) {
          rethrow;
        }
        retried = true;
        await _bridge.recoverClosedModelSession();
      }
    }
  }

  @override
  Future<void> appendToolResponse({
    required ToolCall toolCall,
    required ToolResult result,
  }) {
    final append = _appendToolResponseOverride ?? _bridge.appendToolResponse;
    return append(
      toolName: toolCall.toolId,
      response: Map<String, dynamic>.from(result.toMap()),
    );
  }

  @override
  Future<AgentResponse> continueAfterToolResponses({
    required int maxTokens,
  }) async {
    final stream = _continueStreamOverride ?? _bridge.continueStream;
    Future<AgentResponse> continueOnce() {
      return _responseFromEvents(stream(maxTokens: maxTokens));
    }

    try {
      return await continueOnce();
    } catch (error) {
      if (!_isModelClosedError(error)) {
        rethrow;
      }
      await _bridge.recoverClosedModelSession();
      return continueOnce();
    }
  }

  @override
  Future<bool> cancelGeneration() {
    return _bridge.stopGeneration();
  }

  bool _isModelClosedError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('model is closed') ||
        message.contains('bad state: model is closed');
  }
}
