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

    test('protocol marker accepts unquoted argument keys', () {
      final response = parser.parse(
        '<|tool_call>call:web_search{query: "OpenAI news"}<tool_call|>',
      );

      expect(response.parserStatus, AgentResponseParserStatus.toolCall);
      expect(response.effectiveToolCalls.single.toolId, 'web_search');
      expect(
        response.effectiveToolCalls.single.arguments['query'],
        'OpenAI news',
      );
    });

    test('bare call syntax parses as text-protocol tool call', () {
      final response = parser.parse('call:volume_set{level: 100}');

      expect(response.parserStatus, AgentResponseParserStatus.toolCall);
      expect(response.effectiveToolCalls.single.toolId, 'volume_set');
      expect(response.effectiveToolCalls.single.arguments['level'], 100);
    });

    test('bare call syntax accepts MCP-style tool ids', () {
      final response = parser.parse('call:live-1/search_docs{query: "reef"}');

      expect(response.parserStatus, AgentResponseParserStatus.toolCall);
      expect(response.effectiveToolCalls.single.toolId, 'live-1/search_docs');
      expect(response.effectiveToolCalls.single.arguments['query'], 'reef');
    });

    test('xml-style tool_call JSON parses as text-protocol tool call', () {
      final response = parser.parse(
        '<tool_call>{"tool":"volume_set","arguments":{"level":1}}</tool_call>',
      );

      expect(response.parserStatus, AgentResponseParserStatus.toolCall);
      expect(response.effectiveToolCalls.single.toolId, 'volume_set');
      expect(response.effectiveToolCalls.single.arguments['level'], 1);
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
