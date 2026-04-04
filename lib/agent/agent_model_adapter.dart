import 'package:openreef/agent/agent_models.dart';
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
  })  : _bridge = bridge,
        _parser = parser;

  final LiteRtBridge _bridge;
  final AgentResponseParser _parser;

  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    final buffer = StringBuffer();
    await for (final event in _bridge.generateStream(
      context: context.toPrompt(),
      maxTokens: maxTokens,
    )) {
      buffer.write(event.chunk);
      if (event.isFinished) {
        break;
      }
    }

    return _parser.parse(buffer.toString());
  }
}

