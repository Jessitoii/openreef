import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/models/litert_bridge.dart';
import 'package:openreef/tools/tool_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final LiteRtBridge bridge = LiteRtBridge();
  const MethodChannel deviceStatsChannel = MethodChannel(
    'openreef/device_stats',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceStatsChannel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceStatsChannel, null);
  });

  test('getDeviceStats returns null when channel is unavailable', () async {
    final stats = await bridge.getDeviceStats();

    expect(stats, isNull);
  });

  test('getInferenceStats returns fallback defaults', () async {
    final stats = await bridge.getInferenceStats();

    expect(stats.tps, 0);
    expect(stats.latencyMs, 0);
  });

  test('getDeviceStats parses legacy native key names', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceStatsChannel, (call) async {
          expect(call.method, 'getDeviceStats');
          return <Object?, Object?>{'freeram': 1.75, 'npu_ready': false};
        });

    final stats = await bridge.getDeviceStats();

    expect(stats, isNotNull);
    expect(stats!.freeRam, 1.75);
    expect(stats.npuReady, isFalse);
  });

  test('generateStream throws when model not initialized', () {
    expect(
      () => bridge.generateStream(context: 'Hello', maxTokens: 16),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'tool call config only enables function calls when tools are selected',
    () {
      final empty = bridge.buildToolCallConfig(const <ToolDefinition>[]);
      expect(empty.tools, isEmpty);
      expect(empty.supportsFunctionCalls, isFalse);
      expect(empty.toolChoice, ToolChoice.none);

      final withTools = bridge.buildToolCallConfig(<ToolDefinition>[
        ToolDefinition(
          id: 'mcp_source/search_docs',
          embedding: const <double>[1, 0, 0],
          description: 'Search docs',
          source: 'mcp',
          category: 'mcp',
          argumentSchema: const <ToolArgumentSpec>[
            ToolArgumentSpec(
              name: 'query',
              type: ToolArgumentType.string,
              description: 'Search query',
            ),
          ],
          execute: (call) async => const ToolResult.success('ok'),
        ),
      ]);

      expect(withTools.tools, hasLength(1));
      expect(withTools.tools.single.name, 'mcp_source/search_docs');
      expect(withTools.supportsFunctionCalls, isTrue);
      expect(withTools.toolChoice, ToolChoice.auto);
      debugPrint(
        'TEST_STRUCTURED_TOOL_CONFIG: tools=${withTools.tools.map((tool) => tool.name).join(',')} '
        'supportsFunctionCalls=${withTools.supportsFunctionCalls} '
        'toolChoice=${withTools.toolChoice.runtimeType}',
      );
    },
  );

  test('tool call config can honestly disable typed function calls', () {
    final disabled = bridge.buildToolCallConfig(<ToolDefinition>[
      ToolDefinition(
        id: 'battery_info',
        embedding: const <double>[1, 0, 0],
        execute: (call) async => const ToolResult.success('ok'),
      ),
    ], supportsTypedFunctionCalls: false);

    expect(disabled.tools, isEmpty);
    expect(disabled.supportsFunctionCalls, isFalse);
    expect(disabled.toolChoice, ToolChoice.none);
  });

  test('crash shield exception prints user-facing message', () {
    const error = LiteRtCrashShieldException('Low RAM');

    expect(error.toString(), 'Low RAM');
  });
}
