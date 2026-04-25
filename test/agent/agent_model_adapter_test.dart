import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_model_adapter.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/models/litert_bridge.dart';

void main() {
  test(
    'LiteRt adapter passes selected tools structurally to the bridge',
    () async {
      late List<ToolDefinition> receivedTools;
      final selectedTool = ToolDefinition(
        id: 'session_status',
        embedding: const <double>[1, 0, 0],
        description: 'Session status',
        execute: (call) async => const ToolResult.success('ok'),
      );
      final adapter = LiteRtAgentModelAdapter(
        bridge: LiteRtBridge(),
        generateStreamOverride:
            ({
              required String context,
              required int maxTokens,
              required List<ToolDefinition> selectedTools,
            }) {
              receivedTools = selectedTools;
              return Stream<LiteRtGenerationEvent>.fromIterable(
                const <LiteRtGenerationEvent>[
                  LiteRtGenerationEvent(chunk: 'done', isFinished: false),
                  LiteRtGenerationEvent(chunk: '', isFinished: true),
                ],
              );
            },
      );

      final response = await adapter.generate(
        AssembleResult(
          messages: const <AgentMessage>[
            AgentMessage(role: AgentMessageRole.user, content: 'status'),
          ],
          intentSignal: const IntentSignal(
            primary: 'system',
            secondary: 'general',
            confidence: 1,
          ),
          selectedTools: <ToolDefinition>[selectedTool],
          activeSkills: const <SkillDefinition>[],
          tokenBudget: const TokenBudget(
            totalBudget: 1024,
            estimatedTokens: 1,
            remaining: 1023,
            ratio: 0.01,
            oldToolResults: 0,
            historyBudget: 0,
            memoryBudget: 0,
            standingOrderBudget: 0,
            outputReserve: 128,
          ),
        ),
        maxTokens: 128,
      );

      expect(response.text, 'done');
      expect(receivedTools, hasLength(1));
      expect(receivedTools.single, same(selectedTool));
    },
  );

  test(
    'typed tool calls suppress text parser fallback for the same generation',
    () async {
      final typedCall = ToolCall(
        id: 'typed-1',
        toolId: 'battery_info',
        arguments: const <String, Object?>{},
        rawArguments: const <String, Object?>{},
        hasRawArguments: true,
      );
      final adapter = LiteRtAgentModelAdapter(
        bridge: LiteRtBridge(),
        generateStreamOverride:
            (({
              required String context,
              required int maxTokens,
              required List<ToolDefinition> selectedTools,
            }) {
              return Stream<LiteRtGenerationEvent>.fromIterable(<
                LiteRtGenerationEvent
              >[
                LiteRtGenerationEvent(
                  chunk:
                      '{"tool_call":{"id":"text-1","tool_id":"battery_info","arguments":{"type":"object","properties":{}}}}',
                  isFinished: false,
                  toolCalls: <ToolCall>[typedCall],
                ),
                const LiteRtGenerationEvent(chunk: '', isFinished: true),
              ]);
            }),
      );

      final response = await adapter.generate(
        _assembleWithTools(<ToolDefinition>[
          ToolDefinition(
            id: 'battery_info',
            embedding: const <double>[1, 0, 0],
            execute: (call) async => const ToolResult.success('ok'),
          ),
        ]),
        maxTokens: 128,
      );

      expect(response.hasTypedToolCall, isTrue);
      expect(response.effectiveToolCalls, hasLength(1));
      expect(response.effectiveToolCalls.single.id, 'typed-1');
      expect(response.effectiveToolCalls.single.arguments, isEmpty);
      expect(
        response.effectiveToolCalls.single.source,
        ToolCallSource.flutterGemmaTyped,
      );
    },
  );

  test(
    'text fallback still parses tool JSON when no typed call is present',
    () async {
      final adapter = LiteRtAgentModelAdapter(
        bridge: LiteRtBridge(),
        generateStreamOverride:
            (({
              required String context,
              required int maxTokens,
              required List<ToolDefinition> selectedTools,
            }) {
              return Stream<LiteRtGenerationEvent>.fromIterable(const <
                LiteRtGenerationEvent
              >[
                LiteRtGenerationEvent(
                  chunk:
                      '{"tool_call":{"id":"text-1","tool_id":"battery_info","arguments":{}}}',
                  isFinished: false,
                ),
                LiteRtGenerationEvent(chunk: '', isFinished: true),
              ]);
            }),
      );

      final response = await adapter.generate(
        _assembleWithTools(<ToolDefinition>[
          ToolDefinition(
            id: 'battery_info',
            embedding: const <double>[1, 0, 0],
            execute: (call) async => const ToolResult.success('ok'),
          ),
        ]),
        maxTokens: 128,
      );

      expect(response.hasTypedToolCall, isFalse);
      expect(response.effectiveToolCalls.single.toolId, 'battery_info');
      expect(
        response.effectiveToolCalls.single.source,
        ToolCallSource.textParsed,
      );
    },
  );

  test(
    'LiteRt adapter appends tool result and continues through bridge hooks',
    () async {
      late String appendedToolName;
      late Map<String, dynamic> appendedResponse;
      final adapter = LiteRtAgentModelAdapter(
        bridge: LiteRtBridge(),
        appendToolResponseOverride:
            ({
              required String toolName,
              required Map<String, dynamic> response,
            }) async {
              appendedToolName = toolName;
              appendedResponse = response;
            },
        continueStreamOverride: ({required int maxTokens}) {
          return Stream<LiteRtGenerationEvent>.fromIterable(
            const <LiteRtGenerationEvent>[
              LiteRtGenerationEvent(chunk: 'done', isFinished: false),
              LiteRtGenerationEvent(chunk: '', isFinished: true),
            ],
          );
        },
      );

      await adapter.appendToolResponse(
        toolCall: const ToolCall(id: 'call-1', toolId: 'battery_info'),
        result: const ToolResult.success('ok'),
      );
      final response = await adapter.continueAfterToolResponses(maxTokens: 128);

      expect(appendedToolName, 'battery_info');
      expect(appendedResponse['status'], 'success');
      expect(response.text, 'done');
    },
  );
}

AssembleResult _assembleWithTools(List<ToolDefinition> tools) {
  return AssembleResult(
    messages: const <AgentMessage>[
      AgentMessage(role: AgentMessageRole.user, content: 'status'),
    ],
    intentSignal: const IntentSignal(
      primary: 'system',
      secondary: 'general',
      confidence: 1,
    ),
    selectedTools: tools,
    activeSkills: const <SkillDefinition>[],
    tokenBudget: const TokenBudget(
      totalBudget: 1024,
      estimatedTokens: 1,
      remaining: 1023,
      ratio: 0.01,
      oldToolResults: 0,
      historyBudget: 0,
      memoryBudget: 0,
      standingOrderBudget: 0,
      outputReserve: 128,
    ),
  );
}
