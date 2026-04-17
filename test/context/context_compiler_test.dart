import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/compiled_context_package.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/skills/skill_registry.dart';
import 'package:openreef/skills/builtin_skill_source.dart';
import 'package:openreef/skills/skill.dart';
import 'package:openreef/skills/skill_runtime_catalog.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempRoot;
  late MemoryStorage storage;
  late MemoryIndex memoryIndex;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('context_compiler_');
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

  test(
    'enabled registry skill is selected and injected with audit trace',
    () async {
      await _createSkillDirectory(
        root: tempRoot,
        name: 'reef_planner',
        markdown: '''---
name: Reef Planner
description: Handles reef planning workflows.
tools_required: [notify]
trigger_patterns: [reef plan]
activation_terms: [workflow, planning]
priority: 4
max_tokens: 40
---
# Reef Planner
Use a short plan, verify constraints, and keep outputs structured.
''',
      );
      final toolCatalog = _toolCatalog();
      final skillCatalog = await _skillCatalog(toolCatalog, tempRoot);

      final assembler = _assembler(
        memoryIndex: memoryIndex,
        toolCatalog: toolCatalog,
        skillCatalog: skillCatalog,
      );

      final result = await assembler.assemble(
        sessionKey: 'agent:main',
        userMessage: 'Please make a reef plan for tomorrow.',
        conversationHistory: const <AgentMessage>[],
        modelContextWindow: 4096,
      );

      final package = result.compiledPackage!;
      expect(
        result.activeSkills.map((skill) => skill.id),
        contains('reef_planner'),
      );
      expect(result.toPrompt(), contains('[ACTIVE SKILLS]'));
      expect(result.toPrompt(), contains('Reef Planner'));
      expect(
        package.auditTrace.skillDecisions.any(
          (decision) =>
              decision.skillId == 'reef_planner' &&
              decision.status == SkillDecisionStatus.activated,
        ),
        isTrue,
      );
    },
  );

  test('production-like built-in source registers bundled skills', () async {
    final bundle = _MapAssetBundle(<String, String>{
      'assets/skills/context_auditor/SKILL.md': '''---
name: Context Auditor
tools_required: [memory_search]
trigger_patterns: [context audit]
---
# Context Auditor
Audit context.
''',
      'assets/skills/memory_curator/SKILL.md': '''---
name: Memory Curator
tools_required: [memory_search, memory_save]
trigger_patterns: [remember this]
---
# Memory Curator
Curate memory.
''',
    });
    final builtInRoot = await const BuiltInSkillSource(
      assetPaths: <String>[
        'assets/skills/context_auditor/SKILL.md',
        'assets/skills/memory_curator/SKILL.md',
      ],
    ).materialize(parentDirectory: tempRoot, bundle: bundle);
    final catalog = SkillRuntimeCatalog(
      registry: SkillRegistry(
        rootPaths: const <String>[],
        roots: <SkillRegistryRoot>[
          SkillRegistryRoot(
            path: builtInRoot.path,
            sourceType: SkillSourceType.builtin,
          ),
        ],
      ),
      toolCatalog: _toolCatalog(),
      stateFile: File('${tempRoot.path}${Platform.pathSeparator}state.json'),
    );
    await catalog.reload();

    expect(catalog.snapshots, hasLength(2));
    expect(
      catalog.snapshots.every(
        (snapshot) => snapshot.skill.sourceType == SkillSourceType.builtin,
      ),
      isTrue,
    );
  });

  test('skill-required tool can be pulled into final exposure', () async {
    await _createSkillDirectory(
      root: tempRoot,
      name: 'file_checker',
      markdown: '''---
name: File Checker
tools_required: [file_read]
trigger_patterns: [inspect file]
activation_terms: [file]
---
# File Checker
Read the file before answering.
''',
    );
    final toolCatalog = _toolCatalog(
      extraTools: <ToolDefinition>[
        ToolDefinition(
          id: 'file_read',
          embedding: const <double>[0, 0, 0, 0, 0, 0, 1],
          description: 'Read files',
          execute: _noopExecute,
        ),
      ],
    );
    final skillCatalog = await _skillCatalog(toolCatalog, tempRoot);

    final result =
        await _assembler(
          memoryIndex: memoryIndex,
          toolCatalog: toolCatalog,
          skillCatalog: skillCatalog,
        ).assemble(
          sessionKey: 'agent:main',
          userMessage: 'inspect file notes.txt',
          conversationHistory: const <AgentMessage>[],
          modelContextWindow: 4096,
        );

    expect(
      result.activeSkills.map((skill) => skill.id),
      contains('file_checker'),
    );
    expect(result.selectedTools.map((tool) => tool.id), contains('file_read'));
    expect(
      result.compiledPackage!.auditTrace.toolInclusionReasons['file_read'],
      anyOf(contains('required by'), contains('policy valid')),
    );
  });

  test('disabled skill is excluded and audited as policy skip', () async {
    await _createSkillDirectory(
      root: tempRoot,
      name: 'reef_planner',
      markdown: '''---
tools_required: [notify]
trigger_patterns: [reef plan]
---
# Reef Planner
Do not inject while disabled.
''',
    );
    final toolCatalog = _toolCatalog();
    final skillCatalog = await _skillCatalog(toolCatalog, tempRoot);
    await skillCatalog.setSkillEnabled('reef_planner', false);

    final result =
        await _assembler(
          memoryIndex: memoryIndex,
          toolCatalog: toolCatalog,
          skillCatalog: skillCatalog,
        ).assemble(
          sessionKey: 'agent:main',
          userMessage: 'Please make a reef plan.',
          conversationHistory: const <AgentMessage>[],
          modelContextWindow: 4096,
        );

    final package = result.compiledPackage!;
    expect(result.activeSkills, isEmpty);
    expect(result.toPrompt(), isNot(contains('Do not inject while disabled')));
    expect(
      package.auditTrace.exclusionReasons['skill:reef_planner'],
      contains('runtime-ineligible'),
    );
  });

  test('workflow state is first class when continuation is relevant', () async {
    final result =
        await _assembler(
          memoryIndex: memoryIndex,
          toolCatalog: _toolCatalog(),
          skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
        ).assemble(
          sessionKey: 'agent:main',
          userMessage: 'Continue the workflow and use the current variables.',
          conversationHistory: const <AgentMessage>[
            AgentMessage(
              role: AgentMessageRole.system,
              content: 'EXECUTION_CONTINUATION_STATE',
              metadata: <String, Object?>{
                'currentStepIndex': 2,
                'variables': <String, Object?>{'lastToolId': 'notify'},
                'waitingReason': 'awaiting next step',
              },
            ),
          ],
          modelContextWindow: 4096,
        );

    final package = result.compiledPackage!;
    expect(package.executionMode, ExecutionMode.workflowContinuation);
    expect(result.toPrompt(), contains('[WORKFLOW STATE]'));
    expect(package.auditTrace.includedSectionIds, contains('workflow'));
  });

  test(
    'budget pressure reduces old tool state and preserves memory pointer',
    () async {
      final oldToolPayload = List<String>.filled(260, 'verbose').join(' ');
      final result =
          await _assembler(
            memoryIndex: memoryIndex,
            toolCatalog: _toolCatalog(),
            skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
          ).assemble(
            sessionKey: 'agent:main',
            userMessage: 'Summarize where we are.',
            conversationHistory: <AgentMessage>[
              AgentMessage(
                role: AgentMessageRole.tool,
                content: oldToolPayload,
                turnNumber: 1,
                metadata: const <String, Object?>{
                  'toolId': 'notify',
                  'status': 'success',
                },
              ),
              ...List<AgentMessage>.generate(
                8,
                (index) => AgentMessage(
                  role: AgentMessageRole.assistant,
                  content: List<String>.filled(80, 'history$index').join(' '),
                  turnNumber: index + 2,
                ),
              ),
            ],
            modelContextWindow: 1700,
          );

      final package = result.compiledPackage!;
      expect(result.toPrompt(), contains('[MEMORY INDEX]'));
      expect(package.compactRecommended, isTrue);
      expect(
        package.auditTrace.reductions.any(
          (reduction) => reduction.sectionId == 'tool_state',
        ),
        isTrue,
      );
      expect(package.auditTrace.includedSectionIds, contains('memory_index'));
      expect(package.auditTrace.droppedItems, isNotEmpty);
    },
  );

  test(
    'rendered package fits or degrades explicitly under impossible budget',
    () async {
      final result =
          await _assembler(
            memoryIndex: memoryIndex,
            toolCatalog: _toolCatalog(),
            skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
          ).assemble(
            sessionKey: 'agent:main',
            userMessage: List<String>.filled(1200, 'oversized').join(' '),
            conversationHistory: List<AgentMessage>.generate(
              10,
              (index) => AgentMessage(
                role: AgentMessageRole.assistant,
                content: List<String>.filled(60, 'optional$index').join(' '),
                turnNumber: index + 1,
              ),
            ),
            modelContextWindow: 1200,
          );

      final package = result.compiledPackage!;
      expect(package.degraded, isTrue);
      expect(
        package.auditTrace.policyDecisions.any(
          (decision) => decision.id == 'context_degraded',
        ),
        isTrue,
      );
      expect(
        package.prompt.estimatedTokens,
        lessThanOrEqualTo(
          package.tokenAllocation.totalBudget -
              package.tokenAllocation.outputReserve,
        ),
      );
      expect(package.auditTrace.droppedSectionIds, isNotEmpty);
    },
  );

  test(
    'incompatible skills and allowed modes are enforced from frontmatter',
    () async {
      await _createSkillDirectory(
        root: tempRoot,
        name: 'alpha_skill',
        markdown: '''---
tools_required: [notify]
trigger_patterns: [mode policy]
incompatible_skill_ids: [beta_skill]
priority: 10
---
# Alpha
Alpha instructions.
''',
      );
      await _createSkillDirectory(
        root: tempRoot,
        name: 'beta_skill',
        markdown: '''---
tools_required: [notify]
trigger_patterns: [mode policy]
priority: 9
---
# Beta
Beta instructions.
''',
      );
      await _createSkillDirectory(
        root: tempRoot,
        name: 'workflow_only',
        markdown: '''---
tools_required: [notify]
trigger_patterns: [mode policy]
allowed_modes: [workflowContinuation]
priority: 20
---
# Workflow only
Workflow instructions.
''',
      );
      final skillCatalog = await _skillCatalog(_toolCatalog(), tempRoot);
      final result =
          await _assembler(
            memoryIndex: memoryIndex,
            toolCatalog: _toolCatalog(),
            skillCatalog: skillCatalog,
          ).assemble(
            sessionKey: 'agent:main',
            userMessage: 'mode policy',
            conversationHistory: const <AgentMessage>[],
            modelContextWindow: 4096,
          );

      final ids = result.activeSkills.map((skill) => skill.id).toSet();
      expect(ids, contains('alpha_skill'));
      expect(ids, isNot(contains('beta_skill')));
      expect(ids, isNot(contains('workflow_only')));
      expect(
        result.compiledPackage!.auditTrace.policyRejections['workflow_only'],
        contains('not allowed'),
      );
    },
  );
}

ContextAssembler _assembler({
  required MemoryIndex memoryIndex,
  required ToolCatalog toolCatalog,
  required SkillCatalog skillCatalog,
}) {
  return ContextAssembler(
    memoryIndex: memoryIndex,
    embedder: const _FixedEmbedder(<double>[1, 0, 0, 0, 0, 0, 0]),
    toolCatalog: toolCatalog,
    skillCatalog: skillCatalog,
  );
}

InMemoryToolCatalog _toolCatalog({
  List<ToolDefinition> extraTools = const <ToolDefinition>[],
}) {
  return InMemoryToolCatalog(<ToolDefinition>[
    ToolDefinition(
      id: 'session_status',
      embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
      execute: _noopExecute,
    ),
    ToolDefinition(
      id: 'memory_save',
      embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
      execute: _noopExecute,
    ),
    ToolDefinition(
      id: 'memory_search',
      embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
      execute: _noopExecute,
    ),
    ToolDefinition(
      id: 'notify',
      embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
      execute: _noopExecute,
    ),
    ...extraTools,
  ]);
}

Future<SkillRuntimeCatalog> _skillCatalog(
  ToolCatalog toolCatalog,
  Directory tempRoot,
) async {
  final catalog = SkillRuntimeCatalog(
    registry: SkillRegistry(rootPaths: <String>[tempRoot.path]),
    toolCatalog: toolCatalog,
    stateFile: File('${tempRoot.path}${Platform.pathSeparator}state.json'),
  );
  await catalog.reload();
  return catalog;
}

Future<void> _createSkillDirectory({
  required Directory root,
  required String name,
  required String markdown,
}) async {
  final directory = await Directory(
    '${root.path}${Platform.pathSeparator}$name',
  ).create();
  await File(
    '${directory.path}${Platform.pathSeparator}SKILL.md',
  ).writeAsString(markdown);
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

class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(this._assets);

  final Map<String, String> _assets;

  @override
  Future<ByteData> load(String key) async {
    final value = _assets[key];
    if (value == null) {
      throw FlutterError('missing asset $key');
    }
    final bytes = Uint8List.fromList(value.codeUnits);
    return ByteData.sublistView(bytes);
  }
}
