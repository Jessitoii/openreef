import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';

void main() {
  test('agent message renders prompt segment with role', () {
    const message = AgentMessage(
      role: AgentMessageRole.user,
      content: 'Hello reef',
    );

    expect(message.toPromptSegment(), '[USER] Hello reef');
  });

  group('AgentResponseParser', () {
    const parser = AgentResponseParser();

    test('valid structured tool call parses to executable request', () {
      final response = parser.parse(
        '{"tool_call":{"id":"call-1","tool_id":"battery_info","arguments":{}}}',
      );

      expect(response.parserStatus, AgentResponseParserStatus.toolCall);
      expect(response.hasToolCall, isTrue);
      expect(response.text, isEmpty);
      expect(response.effectiveToolCalls.single.id, 'call-1');
      expect(response.effectiveToolCalls.single.toolId, 'battery_info');
    });

    test('valid protocol marker parses without visible text', () {
      final response = parser.parse(
        '<|tool_call>call:battery_info{}<tool_call|>',
      );

      expect(response.parserStatus, AgentResponseParserStatus.toolCall);
      expect(response.hasToolCall, isTrue);
      expect(response.text, isEmpty);
      expect(response.effectiveToolCalls.single.toolId, 'battery_info');
    });

    test('protocol control token leakage is rejected', () {
      final response = parser.parse('<|assistant|> hello');

      expect(response.hasParserFailure, isTrue);
      expect(response.parserError, 'malformed_tool_call');
      expect(response.hasToolCall, isFalse);
      expect(response.text, isEmpty);
    });

    test('partial structured envelope is rejected', () {
      final response = parser.parse(
        '<|tool_call>call:battery_info{"bad"<tool_call|>',
      );

      expect(response.hasParserFailure, isTrue);
      expect(response.hasToolCall, isFalse);
      expect(response.text, isEmpty);
    });

    test('malformed structured output never becomes visible text', () {
      final response = parser.parse('{"tool_call":');

      expect(response.hasParserFailure, isTrue);
      expect(response.effectiveToolCalls, isEmpty);
      expect(response.text, isEmpty);
    });

    test('embedded structured tool call suppresses surrounding prose', () {
      final response = parser.parse(
        'Sure. {"tool_call":{"id":"call-1","tool_id":"battery_info","arguments":{}}}',
      );

      expect(response.parserStatus, AgentResponseParserStatus.toolCall);
      expect(response.hasToolCall, isTrue);
      expect(response.text, isEmpty);
      expect(response.effectiveToolCalls.single.toolId, 'battery_info');
    });
  });
}
