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

class LiteRtAgentModelAdapter implements AgentModelAdapter {
  LiteRtAgentModelAdapter({
    required LiteRtBridge bridge,
    AgentResponseParser parser = const AgentResponseParser(),
    Stream<LiteRtGenerationEvent> Function({
      required String context,
      required int maxTokens,
      required List<ToolDefinition> selectedTools,
    })?
    generateStreamOverride,
  }) : _bridge = bridge,
       _parser = parser,
       _generateStreamOverride = generateStreamOverride;

  final LiteRtBridge _bridge;
  final AgentResponseParser _parser;
  final Stream<LiteRtGenerationEvent> Function({
    required String context,
    required int maxTokens,
    required List<ToolDefinition> selectedTools,
  })?
  _generateStreamOverride;

  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    final buffer = StringBuffer();
    final stream = _generateStreamOverride ?? _bridge.generateStream;
    await for (final event in stream(
      context: context.toPrompt(),
      maxTokens: maxTokens,
      selectedTools: context.selectedTools,
    )) {
      buffer.write(event.chunk);
      if (event.isFinished) {
        break;
      }
    }

    return _parser.parse(buffer.toString());
  }
}
