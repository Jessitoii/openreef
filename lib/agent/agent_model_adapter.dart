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

class LiteRtAgentModelAdapter
    implements StreamingAgentModelAdapter, ToolResponseModelAdapter {
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
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    final stream = _generateStreamOverride ?? _bridge.generateStream;
    return _responseFromEvents(
      stream(
        context: context.toPrompt(),
        maxTokens: maxTokens,
        selectedTools: context.selectedTools,
      ),
    );
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
    await for (final event in stream(
      context: context.toPrompt(),
      maxTokens: maxTokens,
      selectedTools: context.selectedTools,
    )) {
      if (event.chunk.isNotEmpty) {
        yield event.chunk;
      }
      if (event.isFinished) {
        break;
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
  Future<AgentResponse> continueAfterToolResponses({required int maxTokens}) {
    final stream = _continueStreamOverride ?? _bridge.continueStream;
    return _responseFromEvents(stream(maxTokens: maxTokens));
  }
}
