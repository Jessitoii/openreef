import 'dart:io';

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
