import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/capability_retrieval.dart';
import 'package:openreef/context/compiled_context_package.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/context/context_planner.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('production capability embedder defaults to verified Gecko model', () {
    expect(
      OnDeviceSemanticTextEmbedder.verifiedDefault().modelId,
      OnDeviceSemanticTextEmbedder.defaultCapabilityEmbeddingModelId,
    );
    expect(OnDeviceSemanticTextEmbedder.verifiedDefault().modelId, 'gecko-256');
  });

  test(
    'semantic retriever maps volume paraphrases to one capability family',
    () async {
      final index = CapabilityEmbeddingIndex(
        embedder: const _FixtureE5Embedder(),
      );
      final retriever = SemanticCandidateRetriever(index: index, topK: 3);
      final candidates = const CapabilityCandidateBuilder().build(
        toolCatalog: _ToolCatalog(<ToolDefinition>[
          _volumeTool,
          _batteryTool,
          _notifyTool,
        ]),
        skillCatalog: InMemorySkillCatalog(<SkillDefinition>[]),
      );

      for (final prompt in const <String>[
        'set my volume to 100',
        'turn the sound all the way up',
        'increase media volume to max',
      ]) {
        final retrieved = await retriever.retrieve(
          userMessage: prompt,
          candidates: candidates,
        );
        expect(retrieved.first.candidate.id, 'volume_set');
        expect(retrieved.first.score, greaterThan(0.90));
      }
    },
  );

  test(
    'native battery command is retrieved and exposed through policy gate',
    () async {
      final plan = await _planner().plan(
        userMessage: 'what is my battery level',
        conversationHistory: const <AgentMessage>[],
        modelContextWindow: 4096,
        toolCatalog: const _ToolCatalog(<ToolDefinition>[
          _volumeTool,
          _batteryTool,
        ]),
        skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
        compactRequested: false,
        executionMode: ExecutionMode.reactiveToolUse,
      );

      expect(plan.retrievedCandidates.first, 'battery_info');
      expect(
        plan.toolExposure.primaryTools.map((tool) => tool.id),
        contains('battery_info'),
      );
      expect(
        plan.finalExposureReasons['battery_info'],
        contains('policy valid'),
      );
    },
  );

  test(
    'obvious Bluetooth intent is exposed even when selector is wrong',
    () async {
      final plan =
          await ContextPlanner(
            capabilityIndex: CapabilityEmbeddingIndex(
              embedder: const _FixtureE5Embedder(),
            ),
            selector: const _FixedSelector(<String>['battery_info']),
          ).plan(
            userMessage: 'set my Bluetooth on',
            conversationHistory: const <AgentMessage>[],
            modelContextWindow: 4096,
            toolCatalog: const _ToolCatalog(<ToolDefinition>[
              _batteryTool,
              _bluetoothTool,
            ]),
            skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
            compactRequested: false,
            executionMode: ExecutionMode.reactiveToolUse,
          );

      expect(
        plan.toolExposure.primaryTools.map((tool) => tool.id),
        contains('bluetooth_toggle'),
      );
      expect(
        plan.selectorDecisions['bluetooth_toggle'],
        'deterministic user intent tool',
      );
    },
  );

  test('deterministic device intents require action phrasing', () async {
    final actionTools = <String>{
      'bluetooth_toggle',
      'wifi_toggle',
      'volume_set',
      'brightness_set',
      'flashlight_toggle',
      'contact_read',
      'sms_send',
      'sms_draft',
    };
    final planner = ContextPlanner(
      capabilityIndex: CapabilityEmbeddingIndex(
        embedder: const _FixtureE5Embedder(),
      ),
      selector: const _FixedSelector(<String>['battery_info']),
    );

    for (final prompt in const <String>[
      'Bluetooth history',
      'what is the volume of a cylinder',
      'volume of sphere',
      'sound waves',
      'wireless architecture',
      'sms architecture',
      'Bluetooth protocol explanation',
      'write docs about SMS architecture',
    ]) {
      final plan = await planner.plan(
        userMessage: prompt,
        conversationHistory: const <AgentMessage>[],
        modelContextWindow: 4096,
        toolCatalog: const _ToolCatalog(<ToolDefinition>[
          _batteryTool,
          _bluetoothTool,
          _wifiTool,
          _volumeTool,
          _brightnessTool,
          _flashlightTool,
          _contactReadTool,
          _smsSendTool,
          _smsDraftTool,
        ]),
        skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
        compactRequested: false,
        executionMode: ExecutionMode.reactiveToolUse,
      );

      expect(
        plan.toolExposure.primaryTools.map((tool) => tool.id).toSet(),
        isNot(containsAll(actionTools)),
        reason: prompt,
      );
      expect(
        plan.toolExposure.primaryTools.map((tool) => tool.id).toSet()
          ..remove('battery_info'),
        isEmpty,
        reason: prompt,
      );
    }
  });

  test(
    'deterministic action intents prepend only registered enabled tools',
    () async {
      final planner = ContextPlanner(
        capabilityIndex: CapabilityEmbeddingIndex(
          embedder: const _FixtureE5Embedder(),
        ),
        selector: const _FixedSelector(<String>['battery_info']),
      );

      final cases = <String, List<String>>{
        'turn Bluetooth on': <String>['bluetooth_toggle'],
        'switch Bluetooth off': <String>['bluetooth_toggle'],
        'enable Wi-Fi': <String>['wifi_toggle'],
        'turn the volume all the way up': <String>['volume_set'],
        'mute the volume': <String>['volume_set'],
        'set brightness to 30%': <String>['brightness_set'],
        'enable flashlight': <String>['flashlight_toggle'],
        'send an SMS to mom': <String>['contact_read', 'sms_send', 'sms_draft'],
      };

      for (final entry in cases.entries) {
        final plan = await planner.plan(
          userMessage: entry.key,
          conversationHistory: const <AgentMessage>[],
          modelContextWindow: 4096,
          toolCatalog: const _ToolCatalog(<ToolDefinition>[
            _batteryTool,
            _bluetoothTool,
            _wifiTool,
            _volumeTool,
            _brightnessTool,
            _flashlightTool,
            _contactReadTool,
            _smsSendTool,
            _smsDraftTool,
          ]),
          skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
          compactRequested: false,
          executionMode: ExecutionMode.reactiveToolUse,
        );

        expect(
          plan.toolExposure.primaryTools.map((tool) => tool.id),
          containsAll(entry.value),
          reason: entry.key,
        );
      }
    },
  );

  test('disabled deterministic tools are not injected', () async {
    final disabledBluetooth = ToolDefinition(
      id: 'bluetooth_toggle',
      embedding: const <double>[],
      description: 'Turn Bluetooth on or off.',
      enabled: false,
      execute: _noopExecute,
    );

    final plan =
        await ContextPlanner(
          capabilityIndex: CapabilityEmbeddingIndex(
            embedder: const _FixtureE5Embedder(),
          ),
          selector: const _FixedSelector(<String>['battery_info']),
        ).plan(
          userMessage: 'turn Bluetooth on',
          conversationHistory: const <AgentMessage>[],
          modelContextWindow: 4096,
          toolCatalog: _ToolCatalog(<ToolDefinition>[
            _batteryTool,
            disabledBluetooth,
          ]),
          skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
          compactRequested: false,
          executionMode: ExecutionMode.reactiveToolUse,
        );

    expect(
      plan.toolExposure.primaryTools.map((tool) => tool.id),
      isNot(contains('bluetooth_toggle')),
    );
  });

  test('web search intent exposes search and fetch tools', () async {
    final plan =
        await ContextPlanner(
          capabilityIndex: CapabilityEmbeddingIndex(
            embedder: const _FixtureE5Embedder(),
          ),
          selector: const _FixedSelector(<String>['battery_info']),
        ).plan(
          userMessage: 'search the web for reef tank cycling',
          conversationHistory: const <AgentMessage>[],
          modelContextWindow: 4096,
          toolCatalog: const _ToolCatalog(<ToolDefinition>[
            _batteryTool,
            _webSearchTool,
            _webFetchTool,
          ]),
          skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
          compactRequested: false,
          executionMode: ExecutionMode.reactiveToolUse,
        );

    expect(
      plan.toolExposure.primaryTools.map((tool) => tool.id),
      containsAll(<String>['web_search', 'web_fetch']),
    );
  });

  test('planner degrades when semantic embedder is unavailable', () async {
    final plan =
        await ContextPlanner(
          capabilityIndex: CapabilityEmbeddingIndex(
            embedder: const _UnavailableEmbedder(),
          ),
          selector: const SemanticFallbackCapabilitySelector(),
        ).plan(
          userMessage: 'what is my battery level',
          conversationHistory: const <AgentMessage>[],
          modelContextWindow: 4096,
          toolCatalog: const _ToolCatalog(<ToolDefinition>[_batteryTool]),
          skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
          compactRequested: false,
          executionMode: ExecutionMode.reactiveToolUse,
        );

    expect(plan.retrievedCandidates, isEmpty);
    expect(plan.selectorDecisions['semantic_retrieval_unavailable'], isNotNull);
    expect(
      plan.selectorDecisions['deterministic_tool_fallback'],
      'Embedding model file paths not found.',
    );
    expect(
      plan.toolExposure.primaryTools.map((tool) => tool.id),
      contains('battery_info'),
    );
    expect(plan.finalExposureReasons['battery_info'], contains('policy valid'));
    expect(
      plan.safetyEnvelope.hardConstraints,
      isNot(
        contains('Do not execute risky tools without explicit confirmation.'),
      ),
    );
    expect(
      plan.safetyEnvelope.hardConstraints,
      contains(
        'Runtime handles confirmation for risky tools; do not ask for confirmation in chat.',
      ),
    );
    expect(
      plan.policyDecisions.any(
        (decision) =>
            decision.id == 'semantic_retrieval' &&
            decision.decision == 'unavailable',
      ),
      isTrue,
    );
  });

  test(
    'degraded fallback does not select action tools from bare nouns',
    () async {
      final planner = ContextPlanner(
        capabilityIndex: CapabilityEmbeddingIndex(
          embedder: const _UnavailableEmbedder(),
        ),
        selector: const SemanticFallbackCapabilitySelector(),
      );

      final cases = <String, List<String>>{
        'Bluetooth history': <String>['bluetooth_toggle'],
        'what is the volume of a cylinder': <String>['volume_set'],
        'volume of sphere': <String>['volume_set'],
        'sms architecture': <String>['sms_send', 'sms_draft'],
        'search my memory for yesterday': <String>['web_search'],
      };

      for (final entry in cases.entries) {
        final plan = await planner.plan(
          userMessage: entry.key,
          conversationHistory: const <AgentMessage>[],
          modelContextWindow: 4096,
          toolCatalog: const _ToolCatalog(<ToolDefinition>[
            _memorySearchTool,
            _bluetoothTool,
            _volumeTool,
            _smsSendTool,
            _smsDraftTool,
            _webSearchTool,
            _webFetchTool,
          ]),
          skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
          compactRequested: false,
          executionMode: ExecutionMode.reactiveToolUse,
        );

        final selected = plan.toolExposure.primaryTools.map((tool) => tool.id);
        for (final blockedToolId in entry.value) {
          expect(
            selected,
            isNot(contains(blockedToolId)),
            reason: entry.key,
          );
        }
      }
    },
  );

  test('degraded fallback respects disabled action tools', () async {
    final disabledBluetooth = ToolDefinition(
      id: 'bluetooth_toggle',
      embedding: const <double>[],
      description: 'Turn Bluetooth on or off.',
      enabled: false,
      execute: _noopExecute,
    );

    final plan =
        await ContextPlanner(
          capabilityIndex: CapabilityEmbeddingIndex(
            embedder: const _UnavailableEmbedder(),
          ),
          selector: const SemanticFallbackCapabilitySelector(),
        ).plan(
          userMessage: 'turn Bluetooth on',
          conversationHistory: const <AgentMessage>[],
          modelContextWindow: 4096,
          toolCatalog: _ToolCatalog(<ToolDefinition>[disabledBluetooth]),
          skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
          compactRequested: false,
          executionMode: ExecutionMode.reactiveToolUse,
        );

    expect(
      plan.toolExposure.primaryTools.map((tool) => tool.id),
      isNot(contains('bluetooth_toggle')),
    );
  });

  test('degraded fallback still exposes strict action intents', () async {
    final planner = ContextPlanner(
      capabilityIndex: CapabilityEmbeddingIndex(
        embedder: const _UnavailableEmbedder(),
      ),
      selector: const SemanticFallbackCapabilitySelector(),
    );
    final cases = <String, List<String>>{
      'turn Bluetooth on': <String>['bluetooth_toggle'],
      'turn the volume all the way up': <String>['volume_set'],
      'send an SMS to mom': <String>['sms_send', 'sms_draft'],
      'search the web for OpenAI news': <String>['web_search', 'web_fetch'],
    };

    for (final entry in cases.entries) {
      final plan = await planner.plan(
        userMessage: entry.key,
        conversationHistory: const <AgentMessage>[],
        modelContextWindow: 4096,
        toolCatalog: const _ToolCatalog(<ToolDefinition>[
          _bluetoothTool,
          _volumeTool,
          _contactReadTool,
          _smsSendTool,
          _smsDraftTool,
          _webSearchTool,
          _webFetchTool,
        ]),
        skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
        compactRequested: false,
        executionMode: ExecutionMode.reactiveToolUse,
      );

      expect(
        plan.toolExposure.primaryTools.map((tool) => tool.id),
        containsAll(entry.value),
        reason: entry.key,
      );
    }
  });

  test(
    'battery info stays in rendered tools when semantic retrieval is empty',
    () async {
      final storage = MemoryStorage(
        SqliteMemoryStorageBackend(
          path: inMemoryDatabasePath,
          databaseFactory: databaseFactoryFfi,
        ),
      );
      await storage.initialize();
      addTearDown(storage.close);

      final memoryIndex = MemoryIndex(storage);
      await memoryIndex.rebuild();
      final assembler = ContextAssembler(
        memoryIndex: memoryIndex,
        embedder: const _LegacyIntentEmbedder(),
        capabilityIndex: CapabilityEmbeddingIndex(
          embedder: const _UnavailableEmbedder(),
        ),
        toolCatalog: const _ToolCatalog(<ToolDefinition>[_batteryTool]),
        skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
        capabilitySelector: const SemanticFallbackCapabilitySelector(),
      );

      final result = await assembler.assembleRequest(
        const ContextAssemblyRequest(
          sessionKey: 'battery-test',
          userMessage: 'can you give my battery info',
          conversationHistory: <AgentMessage>[],
          modelContextWindow: 4096,
          executionMode: ExecutionMode.reactiveToolUse,
          executionSource: ExecutionSource.user,
        ),
      );

      final prompt = result.compiledPackage!.prompt.toPrompt();
      final toolsStart = prompt.indexOf('[AVAILABLE TOOLS]');
      final toolsEnd = prompt.indexOf('[END TOOLS]') + '[END TOOLS]'.length;
      debugPrint(
        'TEST_AVAILABLE_TOOLS_BLOCK:\n${prompt.substring(toolsStart, toolsEnd)}',
      );

      expect(
        result.selectedTools.map((tool) => tool.id),
        contains('battery_info'),
      );
      expect(prompt, contains('[battery_info]'));
      expect(
        prompt,
        contains('Read current battery level and charging state.'),
      );
    },
  );

  test(
    'disconnected and unknown MCP tools fail closed but stay audited',
    () async {
      final disconnected = _gmailTool(<String, Object?>{
        'mcpActive': false,
        'mcpTrusted': true,
        'mcpHasSecret': true,
      });
      final unknown = _gmailTool(const <String, Object?>{});

      for (final entry in <MapEntry<String, ToolDefinition>>[
        MapEntry<String, ToolDefinition>('mcp_disconnected', disconnected),
        MapEntry<String, ToolDefinition>('unknown_mcp_runtime_state', unknown),
      ]) {
        final plan = await _planner().plan(
          userMessage: 'check my inbox and draft replies to urgent emails',
          conversationHistory: const <AgentMessage>[],
          modelContextWindow: 4096,
          toolCatalog: _ToolCatalog(<ToolDefinition>[entry.value]),
          skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
          compactRequested: false,
          executionMode: ExecutionMode.reactiveToolUse,
        );

        expect(plan.retrievedCandidates, contains('gmail/read_inbox'));
        expect(plan.toolExposure.exposedTools, isEmpty);
        expect(plan.policyRejections['gmail/read_inbox'], entry.key);
      }
    },
  );

  test('connected MCP tool is retrieved and exposable', () async {
    final plan = await _planner().plan(
      userMessage: 'check my inbox and draft replies to urgent emails',
      conversationHistory: const <AgentMessage>[],
      modelContextWindow: 4096,
      toolCatalog: _ToolCatalog(<ToolDefinition>[
        _gmailTool(const <String, Object?>{
          'mcpActive': true,
          'mcpTrusted': true,
          'mcpHasSecret': true,
        }),
      ]),
      skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
      compactRequested: false,
      executionMode: ExecutionMode.reactiveToolUse,
    );

    expect(plan.retrievedCandidates.first, 'gmail/read_inbox');
    expect(
      plan.toolExposure.primaryTools.map((tool) => tool.id),
      contains('gmail/read_inbox'),
    );
  });

  test(
    'skill dependency gate rejects missing required tool explicitly',
    () async {
      final sleepSkill = SkillDefinition(
        id: 'sleep_tracker',
        displayName: 'Sleep Tracker',
        description: 'Track sleep and schedule morning reminders.',
        content: 'Track sleep, then schedule reminders.',
        toolsRequired: const <String>['cron_add'],
        activationTerms: const <String>['sleep', 'reminder'],
      );
      final plan = await _planner().plan(
        userMessage: 'track my sleep and remind me every morning',
        conversationHistory: const <AgentMessage>[],
        modelContextWindow: 4096,
        toolCatalog: const _ToolCatalog(<ToolDefinition>[_notifyTool]),
        skillCatalog: InMemorySkillCatalog(<SkillDefinition>[sleepSkill]),
        compactRequested: false,
        executionMode: ExecutionMode.reactiveToolUse,
      );

      expect(plan.retrievedCandidates, contains('sleep_tracker'));
      expect(plan.skillPlan.activeSkills, isEmpty);
      expect(
        plan.policyRejections['sleep_tracker'],
        contains('required tools unavailable'),
      );
    },
  );

  test('selector invented ids are ignored and audited', () async {
    final plan =
        await ContextPlanner(
          capabilityIndex: CapabilityEmbeddingIndex(
            embedder: const _FixtureE5Embedder(),
          ),
          selector: const _InventingSelector(),
        ).plan(
          userMessage: 'what is my battery level',
          conversationHistory: const <AgentMessage>[],
          modelContextWindow: 4096,
          toolCatalog: const _ToolCatalog(<ToolDefinition>[_batteryTool]),
          skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
          compactRequested: false,
          executionMode: ExecutionMode.reactiveToolUse,
        );

    expect(plan.toolExposure.exposedTools, isEmpty);
    expect(plan.selectorViolations.single, contains('invented'));
  });

  test(
    'candidate index invalidates and re-embeds changed capability documents',
    () async {
      final embedder = _CountingEmbedder();
      final index = CapabilityEmbeddingIndex(embedder: embedder);
      final retriever = SemanticCandidateRetriever(index: index, topK: 1);
      final builder = const CapabilityCandidateBuilder();

      await retriever.retrieve(
        userMessage: 'what is my battery level',
        candidates: builder.build(
          toolCatalog: const _ToolCatalog(<ToolDefinition>[_batteryTool]),
          skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
        ),
      );
      expect(embedder.documentEmbeds, 1);

      index.invalidate(reason: 'tool_enable_disable');
      final disabledBattery = ToolDefinition(
        id: _batteryTool.id,
        embedding: const <double>[],
        description: _batteryTool.description,
        category: _batteryTool.category,
        tags: _batteryTool.tags,
        enabled: false,
        runtimeMetadata: _batteryTool.runtimeMetadata,
        execute: _noopExecute,
      );
      await retriever.retrieve(
        userMessage: 'what is my battery level',
        candidates: builder.build(
          toolCatalog: _ToolCatalog(<ToolDefinition>[disabledBattery]),
          skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
        ),
      );

      expect(index.version, 1);
      expect(embedder.documentEmbeds, 2);
    },
  );

  test('request assembly preserves executor-provided trigger mode', () async {
    final temp = await Directory.systemTemp.createTemp('semantic_context_');
    final storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    addTearDown(() async {
      await storage.close();
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final memoryIndex = MemoryIndex(storage);
    await memoryIndex.rebuild();
    final assembler = ContextAssembler(
      memoryIndex: memoryIndex,
      embedder: const _LegacyIntentEmbedder(),
      capabilityIndex: CapabilityEmbeddingIndex(
        embedder: const _FixtureE5Embedder(),
      ),
      toolCatalog: const _ToolCatalog(<ToolDefinition>[_notifyTool]),
      skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
    );

    final result = await assembler.assembleRequest(
      const ContextAssemblyRequest(
        sessionKey: 'trigger:daily',
        userMessage: 'hello there',
        conversationHistory: <AgentMessage>[],
        modelContextWindow: 4096,
        executionMode: ExecutionMode.triggerExecution,
        executionSource: ExecutionSource.trigger,
      ),
    );

    expect(
      result.compiledPackage!.executionMode,
      ExecutionMode.triggerExecution,
    );
    expect(
      result.compiledPackage!.auditTrace.policyDecisions.any(
        (decision) =>
            decision.id == 'execution_mode' &&
            decision.reason.contains('executor/runtime'),
      ),
      isTrue,
    );
  });

  test('production agent paths do not call legacy context assembly', () {
    final agentLoop = File('lib/agent/agent_loop.dart').readAsStringSync();
    final executor = File(
      'lib/agent/agent_task_executor.dart',
    ).readAsStringSync();

    expect(agentLoop, isNot(contains('_contextAssembler.assemble(')));
    expect(agentLoop, contains('_contextAssembler.assembleRequest('));
    expect(
      executor,
      contains('executionMode: _contextExecutionModeFor(request)'),
    );
  });
}

ContextPlanner _planner() {
  return ContextPlanner(
    capabilityIndex: CapabilityEmbeddingIndex(
      embedder: const _FixtureE5Embedder(),
    ),
    selector: const SemanticFallbackCapabilitySelector(),
  );
}

const ToolDefinition _volumeTool = ToolDefinition(
  id: 'volume_set',
  embedding: <double>[],
  description: 'Set system or media volume level.',
  category: 'system',
  tags: <String>['audio', 'device'],
  runtimeMetadata: <String, Object?>{
    'capabilityPhrases': <String>[
      'set volume',
      'turn sound up',
      'increase media volume',
    ],
    'usageExamples': <String>['set my volume to 100'],
  },
  execute: _noopExecute,
);

const ToolDefinition _batteryTool = ToolDefinition(
  id: 'battery_info',
  embedding: <double>[],
  description: 'Read current battery level and charging state.',
  category: 'system',
  tags: <String>['device', 'battery'],
  runtimeMetadata: <String, Object?>{
    'capabilityPhrases': <String>['battery level', 'charging status'],
  },
  execute: _noopExecute,
);

const ToolDefinition _memorySearchTool = ToolDefinition(
  id: 'memory_search',
  embedding: <double>[],
  description: 'Search local memory records.',
  category: 'memory',
  tags: <String>['memory', 'search'],
  execute: _noopExecute,
);

const ToolDefinition _bluetoothTool = ToolDefinition(
  id: 'bluetooth_toggle',
  embedding: <double>[],
  description: 'Turn Bluetooth on or off.',
  category: 'system',
  tags: <String>['device', 'bluetooth'],
  execute: _noopExecute,
);

const ToolDefinition _wifiTool = ToolDefinition(
  id: 'wifi_toggle',
  embedding: <double>[],
  description: 'Turn Wi-Fi on or off.',
  category: 'system',
  tags: <String>['device', 'wifi'],
  execute: _noopExecute,
);

const ToolDefinition _brightnessTool = ToolDefinition(
  id: 'brightness_set',
  embedding: <double>[],
  description: 'Set screen brightness.',
  category: 'system',
  tags: <String>['device', 'brightness'],
  execute: _noopExecute,
);

const ToolDefinition _flashlightTool = ToolDefinition(
  id: 'flashlight_toggle',
  embedding: <double>[],
  description: 'Turn flashlight on or off.',
  category: 'system',
  tags: <String>['device', 'flashlight'],
  execute: _noopExecute,
);

const ToolDefinition _contactReadTool = ToolDefinition(
  id: 'contact_read',
  embedding: <double>[],
  description: 'Read contacts.',
  category: 'contacts',
  tags: <String>['contacts'],
  execute: _noopExecute,
);

const ToolDefinition _smsSendTool = ToolDefinition(
  id: 'sms_send',
  embedding: <double>[],
  description: 'Send an SMS.',
  category: 'communication',
  tags: <String>['sms'],
  execute: _noopExecute,
);

const ToolDefinition _smsDraftTool = ToolDefinition(
  id: 'sms_draft',
  embedding: <double>[],
  description: 'Draft an SMS.',
  category: 'communication',
  tags: <String>['sms'],
  execute: _noopExecute,
);

const ToolDefinition _webSearchTool = ToolDefinition(
  id: 'web_search',
  embedding: <double>[],
  description: 'Search the web.',
  category: 'research',
  tags: <String>['web', 'search'],
  execute: _noopExecute,
);

const ToolDefinition _webFetchTool = ToolDefinition(
  id: 'web_fetch',
  embedding: <double>[],
  description: 'Fetch a web page.',
  category: 'research',
  tags: <String>['web', 'fetch'],
  execute: _noopExecute,
);

const ToolDefinition _notifyTool = ToolDefinition(
  id: 'notify',
  embedding: <double>[],
  description: 'Show a notification.',
  category: 'system',
  execute: _noopExecute,
);

ToolDefinition _gmailTool(Map<String, Object?> mcpState) {
  return ToolDefinition(
    id: 'gmail/read_inbox',
    embedding: const <double>[],
    description: 'Read Gmail inbox messages and inspect urgent email.',
    category: 'mcp',
    source: 'mcp',
    tags: const <String>['mcp', 'gmail', 'email'],
    runtimeMetadata: <String, Object?>{
      'sourceId': 'gmail',
      'mcpToolName': 'read_inbox',
      'capabilityPhrases': const <String>[
        'check inbox',
        'read urgent emails',
        'draft email replies',
      ],
      ...mcpState,
    },
    execute: _noopExecute,
  );
}

Future<ToolResult> _noopExecute(ToolCall call) async {
  return const ToolResult.success('ok');
}

class _ToolCatalog implements ToolCatalog {
  const _ToolCatalog(this._tools);

  final List<ToolDefinition> _tools;

  @override
  ToolDefinition? byId(String id) {
    for (final tool in _tools) {
      if (tool.id == id) return tool;
    }
    return null;
  }

  @override
  List<ToolDefinition> listTools() => _tools;
}

class _FixtureE5Embedder implements SemanticTextEmbedder {
  const _FixtureE5Embedder();

  @override
  String get modelId => 'intfloat/multilingual-e5-small';

  @override
  Future<List<double>> embedDocument(String text) async => _vector(text);

  @override
  Future<List<double>> embedQuery(String text) async => _vector(text);

  List<double> _vector(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('volume') ||
        normalized.contains('sound') ||
        normalized.contains('media')) {
      return const <double>[1, 0, 0, 0, 0];
    }
    if (normalized.contains('battery') || normalized.contains('charging')) {
      return const <double>[0, 1, 0, 0, 0];
    }
    if (normalized.contains('inbox') ||
        normalized.contains('gmail') ||
        normalized.contains('email')) {
      return const <double>[0, 0, 1, 0, 0];
    }
    if (normalized.contains('sleep') || normalized.contains('remind')) {
      return const <double>[0, 0, 0, 1, 0];
    }
    return const <double>[0, 0, 0, 0, 1];
  }
}

class _CountingEmbedder extends _FixtureE5Embedder {
  int documentEmbeds = 0;

  @override
  Future<List<double>> embedDocument(String text) async {
    documentEmbeds += 1;
    return super.embedDocument(text);
  }
}

class _UnavailableEmbedder implements SemanticTextEmbedder {
  const _UnavailableEmbedder();

  @override
  String get modelId => 'unavailable-fixture';

  @override
  Future<List<double>> embedDocument(String text) async {
    throw const SemanticEmbeddingUnavailableException(
      'unavailable-fixture',
      'Embedding model file paths not found.',
    );
  }

  @override
  Future<List<double>> embedQuery(String text) async {
    throw const SemanticEmbeddingUnavailableException(
      'unavailable-fixture',
      'Embedding model file paths not found.',
    );
  }
}

class _LegacyIntentEmbedder implements IntentEmbedder {
  const _LegacyIntentEmbedder();

  @override
  Future<List<double>> embed(String text) async {
    return const <double>[0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5];
  }
}

class _InventingSelector implements CapabilitySelector {
  const _InventingSelector();

  @override
  Future<CandidateSelectionProposal> select({
    required String userMessage,
    required ExecutionMode executionMode,
    required List<CapabilityRetrievedCandidate> retrievedCandidates,
  }) async {
    return const CandidateSelectionProposal(
      primaryToolIds: <String>['made_up_tool'],
    );
  }
}

class _FixedSelector implements CapabilitySelector {
  const _FixedSelector(this.toolIds);

  final List<String> toolIds;

  @override
  Future<CandidateSelectionProposal> select({
    required String userMessage,
    required ExecutionMode executionMode,
    required List<CapabilityRetrievedCandidate> retrievedCandidates,
  }) async {
    return CandidateSelectionProposal(primaryToolIds: toolIds);
  }
}
