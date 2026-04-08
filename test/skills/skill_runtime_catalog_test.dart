import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/skills/skill_registry.dart';
import 'package:openreef/skills/skill_runtime_catalog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempRoot;
  late MemoryStorage storage;
  late MemoryIndex memoryIndex;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('skill_runtime_catalog_');
    storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    memoryIndex = MemoryIndex(storage);
    await memoryIndex.rebuild();
  });

  tearDown(() async {
    await storage.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('real installed skill changes assembled runtime context and reports active state', () async {
    await _createSkillDirectory(
      root: tempRoot,
      name: 'sleep_tracker',
      markdown: '''---
name: Sleep Tracker
description: Tracks bedtime routines.
tools_required: [notify]
trigger_patterns:
  - bedtime check
---
# Sleep Tracker
Always prompt the user with a short bedtime checklist before responding.
''',
    );

    final toolCatalog = InMemoryToolCatalog(<ToolDefinition>[
      ToolDefinition(
        id: 'notify',
        embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
        execute: _noopExecute,
      ),
      ToolDefinition(
        id: 'session_status',
        embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
        execute: _noopExecute,
      ),
      ToolDefinition(
        id: 'memory_search',
        embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
        execute: _noopExecute,
      ),
    ]);
    final skillCatalog = SkillRuntimeCatalog(
      registry: SkillRegistry(rootPaths: <String>[tempRoot.path]),
      toolCatalog: toolCatalog,
      stateFile: File('${tempRoot.path}${Platform.pathSeparator}runtime_state.json'),
    );
    await skillCatalog.reload();

    final assembler = ContextAssembler(
      memoryIndex: memoryIndex,
      embedder: const _FixedEmbedder(<double>[0, 0, 1, 0, 0, 0, 0]),
      toolCatalog: toolCatalog,
      skillCatalog: skillCatalog,
    );

    final result = await assembler.assemble(
      sessionKey: 'agent:main',
      userMessage: 'Please do a bedtime check before you answer.',
      conversationHistory: const <AgentMessage>[],
      modelContextWindow: 4096,
    );

    expect(result.activeSkills.map((skill) => skill.id), <String>['sleep_tracker']);
    expect(result.toPrompt(), contains('Sleep Tracker'));
    expect(result.toPrompt(), contains('bedtime checklist'));

    final snapshot = skillCatalog.snapshots.single;
    expect(snapshot.enabled, isTrue);
    expect(snapshot.runtimeEligible, isTrue);
    expect(snapshot.matchedThisTurn, isTrue);
    expect(snapshot.activeThisTurn, isTrue);
  });

  test('persisted enabled-state controls runtime eligibility after reload', () async {
    await _createSkillDirectory(
      root: tempRoot,
      name: 'sleep_tracker',
      markdown: '''---
tools_required: [notify]
trigger_patterns: [bedtime check]
---
# Sleep Tracker
''',
    );

    final toolCatalog = InMemoryToolCatalog(<ToolDefinition>[
      ToolDefinition(
        id: 'notify',
        embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
        execute: _noopExecute,
      ),
    ]);
    final skillCatalog = SkillRuntimeCatalog(
      registry: SkillRegistry(rootPaths: <String>[tempRoot.path]),
      toolCatalog: toolCatalog,
      stateFile: File('${tempRoot.path}${Platform.pathSeparator}runtime_state.json'),
    );

    await skillCatalog.reload();
    await skillCatalog.setSkillEnabled('sleep_tracker', false);
    await skillCatalog.reload();

    final snapshot = skillCatalog.snapshots.single;
    expect(snapshot.enabled, isFalse);
    expect(snapshot.runtimeEligible, isFalse);
  });
}

Future<void> _createSkillDirectory({
  required Directory root,
  required String name,
  required String markdown,
}) async {
  final directory = await Directory(
    '${root.path}${Platform.pathSeparator}$name',
  ).create();
  final skillFile = File('${directory.path}${Platform.pathSeparator}SKILL.md');
  await skillFile.writeAsString(markdown);
}

class _FixedEmbedder implements IntentEmbedder {
  const _FixedEmbedder(this._embedding);

  final List<double> _embedding;

  @override
  Future<List<double>> embed(String text) async => _embedding;
}

Future<ToolResult> _noopExecute(ToolCall call) async {
  return const ToolResult.success('ok');
}
