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
}
